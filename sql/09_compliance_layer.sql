-- =============================================================================
-- 09_compliance_layer.sql
-- Compliance infrastructure: registrations, legal basis, sanctions screening
--
-- Addresses:
--   - CARM release-blocking (Canada)
--   - EORI requirements (GB, XI, EU)
--   - CBAM declarant authorization
--   - IEEPA retroactive duty voids (US)
--   - Sanctions screening with list versioning
--
-- Run after 08_realistic_financials.sql
-- =============================================================================

-- =============================================================================
-- PART 1: PARTY REGISTRATIONS
-- =============================================================================
-- One row per party per jurisdiction per registration type.
-- CARM, EORI, CBAM declarant status, IOSS, bonds — all here.

CREATE TYPE registration_type AS ENUM (
    'EORI_GB',           -- UK post-Brexit
    'EORI_XI',           -- Northern Ireland
    'EORI_EU',           -- EU member state issued
    'CARM_BN',           -- Canada business number
    'CARM_RM',           -- Canada importer RM account
    'CBAM_DECLARANT',    -- EU CBAM authorized declarant
    'IOSS',              -- Import One-Stop Shop (EU VAT)
    'US_EIN',            -- US Employer Identification Number
    'US_CBP_BOND',       -- US Customs bond
    'UK_DEFERMENT',      -- UK duty deferment account
    'AEO_C',             -- Authorized Economic Operator - Customs
    'AEO_S',             -- Authorized Economic Operator - Security
    'AEO_F'              -- Authorized Economic Operator - Full
);

CREATE TYPE registration_status AS ENUM (
    'pending',           -- Application submitted
    'active',            -- Valid and usable
    'suspended',         -- Temporarily invalid
    'expired',           -- Past valid_to date
    'revoked'            -- Permanently invalid
);

CREATE TABLE party_registrations (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    party_id            BIGINT        NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
    jurisdiction        CHAR(2)       NOT NULL,  -- ISO country code
    registration_type   registration_type NOT NULL,
    identifier          VARCHAR(50)   NOT NULL,  -- The actual registration number
    status              registration_status NOT NULL DEFAULT 'active',
    valid_from          DATE          NOT NULL DEFAULT CURRENT_DATE,
    valid_to            DATE,                    -- NULL = no expiry
    issuing_authority   VARCHAR(150),
    notes               TEXT,

    -- Financial security (bonds, guarantees)
    bond_amount         NUMERIC(14,2),
    bond_currency       CHAR(3),
    bond_provider       VARCHAR(150),
    bond_expiry         DATE,
    bond_reference      VARCHAR(50),

    -- CARM-specific: Release Prior to Payment eligibility
    carm_rpp_eligible   BOOLEAN       DEFAULT FALSE,

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT registration_bond_complete CHECK (
        (bond_amount IS NULL AND bond_currency IS NULL) OR
        (bond_amount IS NOT NULL AND bond_currency IS NOT NULL)
    )
);

-- A party can only have one active registration of each type per jurisdiction
CREATE UNIQUE INDEX idx_registration_unique_active
    ON party_registrations(party_id, jurisdiction, registration_type)
    WHERE status = 'active';

CREATE INDEX idx_registrations_party ON party_registrations(party_id, status);
CREATE INDEX idx_registrations_expiry ON party_registrations(valid_to)
    WHERE valid_to IS NOT NULL AND status = 'active';

COMMENT ON TABLE party_registrations IS
'Customs and trade registrations per party per jurisdiction. CARM, EORI, CBAM declarant, bonds.
Critical: Some registrations are release-blocking (CARM RM without RPP means no release).';

-- =============================================================================
-- PART 2: WORKFLOW INTEGRATION
-- =============================================================================
-- Add registration requirement to task templates.
-- The dispatch engine excludes tasks where required registration is missing/expired.

ALTER TABLE task_templates
    ADD COLUMN requires_registration_type registration_type;

COMMENT ON COLUMN task_templates.requires_registration_type IS
'If set, task cannot enter ready state unless the relevant party has an active
registration of this type. Enforced by v_ready_tasks view.';

-- Recreate v_ready_tasks to include registration check
DROP VIEW IF EXISTS v_ready_tasks;

CREATE VIEW v_ready_tasks AS
SELECT
    t.id,
    t.company_id,
    t.task_no,
    t.name              AS task_name,
    t.status,
    t.priority,
    t.scheduled_start_at,
    ss.name             AS stage_name,
    s.shipment_no,
    -- Check if overdue
    CASE WHEN t.scheduled_start_at < now() THEN TRUE ELSE FALSE END AS is_overdue
FROM tasks t
JOIN shipment_stages ss ON ss.id = t.stage_id
JOIN shipments s ON s.id = t.shipment_id
LEFT JOIN task_templates tt ON tt.id = t.task_template_id
LEFT JOIN contracts c ON c.id = s.contract_id
-- Check registration requirement if specified
LEFT JOIN party_registrations pr ON
    tt.requires_registration_type IS NOT NULL
    AND pr.party_id = c.customer_id  -- Or importer_id when added
    AND pr.registration_type = tt.requires_registration_type
    AND pr.status = 'active'
    AND (pr.valid_to IS NULL OR pr.valid_to >= CURRENT_DATE)
WHERE t.status IN ('created', 'assigned', 'scheduled')
  AND t.company_id = current_company_id()
  -- No unsatisfied dependencies
  AND NOT EXISTS (
      SELECT 1 FROM task_dependencies td
      JOIN tasks blocker ON blocker.id = td.depends_on_task_id
      WHERE td.task_id = t.id
        AND blocker.status NOT IN ('completed', 'closed', 'cancelled')
  )
  -- Registration check: if required, must exist and be valid
  AND (tt.requires_registration_type IS NULL OR pr.id IS NOT NULL);

COMMENT ON VIEW v_ready_tasks IS
'Tasks that can be worked: dependencies satisfied, registration requirements met.
CARM, EORI, CBAM checks happen here via party_registrations join.';


-- =============================================================================
-- PART 3: LEGAL BASIS AND REFUNDS
-- =============================================================================
-- Duty amounts can be retroactively voided (IEEPA ruling).
-- Track the legal basis and provide a refund claim lifecycle.

-- Add legal basis to customs declarations (idempotent)
DO $fn$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'customs_declarations' AND column_name = 'legal_basis') THEN
        ALTER TABLE customs_declarations ADD COLUMN legal_basis VARCHAR(100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'customs_declarations' AND column_name = 'legal_basis_statute') THEN
        ALTER TABLE customs_declarations ADD COLUMN legal_basis_statute VARCHAR(50);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'customs_declarations' AND column_name = 'legal_basis_effective_date') THEN
        ALTER TABLE customs_declarations ADD COLUMN legal_basis_effective_date DATE;
    END IF;
END;
$fn$;

COMMENT ON COLUMN customs_declarations.legal_basis IS
'Regulatory/statutory authority for duty assessment (e.g., "Section 301", "IEEPA", "MFN")';

-- Add legal basis to financial entries (idempotent)
DO $fn$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'shipment_financials' AND column_name = 'legal_basis') THEN
        ALTER TABLE shipment_financials ADD COLUMN legal_basis VARCHAR(100);
    END IF;
    -- customs_declaration_id already exists in base schema
END;
$fn$;

-- Refund claims table - separate lifecycle from original payment
CREATE TYPE refund_status AS ENUM (
    'draft',             -- Being prepared
    'filed',             -- Submitted to authority
    'under_review',      -- Authority processing
    'partial_approved',  -- Some amount approved
    'approved',          -- Full amount approved
    'paid',              -- Funds received
    'denied',            -- Claim rejected
    'withdrawn'          -- Cancelled by claimant
);

CREATE TABLE refund_claims (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

    -- What we're claiming against
    shipment_financial_id BIGINT      NOT NULL REFERENCES shipment_financials(id),
    customs_declaration_id BIGINT     REFERENCES customs_declarations(id),

    -- Claim details
    claim_reference     VARCHAR(50),  -- Authority's reference once filed
    claim_type          VARCHAR(50)   NOT NULL,  -- 'IEEPA_REFUND', 'DRAWBACK', 'PROTEST'
    legal_basis         VARCHAR(100)  NOT NULL,  -- Why we're entitled to refund

    -- Amounts
    amount_claimed      NUMERIC(14,2) NOT NULL,
    currency            CHAR(3)       NOT NULL,
    amount_approved     NUMERIC(14,2),
    amount_received     NUMERIC(14,2),

    -- Lifecycle
    status              refund_status NOT NULL DEFAULT 'draft',
    filed_at            TIMESTAMPTZ,
    decided_at          TIMESTAMPTZ,
    received_at         TIMESTAMPTZ,

    -- Documentation
    filed_by            BIGINT        REFERENCES users(id),
    decision_reference  VARCHAR(100),
    denial_reason       TEXT,
    notes               TEXT,

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT refund_amounts_valid CHECK (
        amount_claimed > 0 AND
        (amount_approved IS NULL OR amount_approved >= 0) AND
        (amount_received IS NULL OR amount_received >= 0)
    ),
    CONSTRAINT refund_received_requires_approved CHECK (
        amount_received IS NULL OR amount_approved IS NOT NULL
    )
);

CREATE INDEX idx_refunds_shipment ON refund_claims(shipment_financial_id);
CREATE INDEX idx_refunds_status ON refund_claims(company_id, status)
    WHERE status NOT IN ('paid', 'denied', 'withdrawn');

COMMENT ON TABLE refund_claims IS
'Duty refund claims (IEEPA, drawback, protests). Separate table because refunds have
their own lifecycle and partial payments are common. FK to shipment_financials.';


-- =============================================================================
-- PART 4: SANCTIONS SCREENING
-- =============================================================================
-- Append-only log. Automated screening produces hits; humans make dispositions.
-- List version is critical: screening against Tuesday's list doesn't clear Wednesday's.

CREATE TYPE screening_result AS ENUM (
    'clear',             -- No matches
    'potential_match',   -- Automated hit, needs review
    'confirmed_match'    -- Verified match to sanctioned party
);

CREATE TYPE screening_disposition AS ENUM (
    'pending_review',    -- Hit not yet reviewed
    'false_positive',    -- Reviewed, not a match
    'true_positive',     -- Reviewed, confirmed match
    'escalated'          -- Sent to compliance officer
);

CREATE TABLE party_screenings (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    party_id            BIGINT        NOT NULL REFERENCES parties(id) ON DELETE CASCADE,

    -- What was screened
    screened_name       VARCHAR(200)  NOT NULL,  -- Name as submitted
    screened_country    CHAR(2),
    screened_identifiers JSONB,                  -- Additional identifiers checked

    -- Screening execution
    screened_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    screened_by         BIGINT        REFERENCES users(id),  -- NULL = automated
    screening_provider  VARCHAR(50),             -- 'dow_jones', 'refinitiv', 'internal'

    -- List information (critical for audit)
    list_source         VARCHAR(50)   NOT NULL,  -- 'OFAC_SDN', 'EU_CONSOLIDATED', 'UK_OFSI', etc.
    list_version        VARCHAR(50),             -- Publication date or version ID
    list_publication_date DATE,

    -- Result
    result              screening_result NOT NULL,
    match_score         NUMERIC(5,2),            -- 0-100 confidence score
    matched_entries     JSONB,                   -- Details of what matched

    -- Human disposition (separate from automated result)
    disposition         screening_disposition,
    disposition_at      TIMESTAMPTZ,
    disposition_by      BIGINT        REFERENCES users(id),
    disposition_rationale TEXT,

    -- For gating shipments: when does this screening expire?
    valid_until         TIMESTAMPTZ,

    CONSTRAINT screening_disposition_requires_review CHECK (
        disposition IS NULL OR disposition_by IS NOT NULL
    )
);

CREATE INDEX idx_screenings_party ON party_screenings(party_id, screened_at DESC);
CREATE INDEX idx_screenings_pending ON party_screenings(company_id, disposition)
    WHERE disposition = 'pending_review';
CREATE INDEX idx_screenings_validity ON party_screenings(party_id, valid_until)
    WHERE result = 'clear' AND (disposition IS NULL OR disposition = 'false_positive');

COMMENT ON TABLE party_screenings IS
'Append-only sanctions screening log. Each row is one screening event.
Automated hits need human disposition. List version tracked for audit.
Validity window enforces re-screening when lists update.';

-- =============================================================================
-- PART 5: BENEFICIAL OWNERSHIP (for 50% rule)
-- =============================================================================
-- OFAC aggregates ownership; EU codified 50% threshold.
-- Need to track ownership chains to compute effective control.

CREATE TABLE party_ownership (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

    -- The entity being owned
    owned_party_id      BIGINT        NOT NULL REFERENCES parties(id) ON DELETE CASCADE,

    -- The owner (can be another party or an individual)
    owner_party_id      BIGINT        REFERENCES parties(id) ON DELETE CASCADE,
    owner_name          VARCHAR(200),            -- For individuals not in parties table
    owner_country       CHAR(2),

    -- Ownership details
    ownership_percent   NUMERIC(5,2)  NOT NULL,
    ownership_type      VARCHAR(50)   NOT NULL,  -- 'direct', 'indirect', 'beneficial'
    is_controlling      BOOLEAN       DEFAULT FALSE,  -- Control beyond ownership %

    -- Validity
    effective_from      DATE          NOT NULL DEFAULT CURRENT_DATE,
    effective_to        DATE,
    source_document     VARCHAR(200),
    verified_at         TIMESTAMPTZ,
    verified_by         BIGINT        REFERENCES users(id),

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT ownership_percent_valid CHECK (
        ownership_percent > 0 AND ownership_percent <= 100
    ),
    CONSTRAINT ownership_has_owner CHECK (
        owner_party_id IS NOT NULL OR owner_name IS NOT NULL
    )
);

CREATE INDEX idx_ownership_owned ON party_ownership(owned_party_id, effective_from);
CREATE INDEX idx_ownership_owner ON party_ownership(owner_party_id)
    WHERE owner_party_id IS NOT NULL;

COMMENT ON TABLE party_ownership IS
'Beneficial ownership for sanctions 50% rule. OFAC aggregates ownership;
EU codified threshold in 19th sanctions package. Track chains to compute control.';

-- =============================================================================
-- PART 6: HELPER FUNCTIONS
-- =============================================================================

-- Check if a party has valid registration of a given type
CREATE OR REPLACE FUNCTION fn_has_valid_registration(
    p_party_id BIGINT,
    p_registration_type registration_type,
    p_as_of_date DATE DEFAULT CURRENT_DATE
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $fn$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM party_registrations
        WHERE party_id = p_party_id
          AND registration_type = p_registration_type
          AND status = 'active'
          AND valid_from <= p_as_of_date
          AND (valid_to IS NULL OR valid_to >= p_as_of_date)
    );
END;
$fn$;

-- Check if a party has been screened against a list version
CREATE OR REPLACE FUNCTION fn_screening_valid(
    p_party_id BIGINT,
    p_list_source VARCHAR(50),
    p_min_list_date DATE DEFAULT CURRENT_DATE - INTERVAL '7 days'
) RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $fn$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM party_screenings
        WHERE party_id = p_party_id
          AND list_source = p_list_source
          AND list_publication_date >= p_min_list_date
          AND result = 'clear'
          AND (disposition IS NULL OR disposition = 'false_positive')
          AND (valid_until IS NULL OR valid_until > now())
    );
END;
$fn$;

-- Calculate aggregate ownership (for 50% rule)
-- Note: This is simplified; real implementation needs recursive CTE for chains
CREATE OR REPLACE FUNCTION fn_aggregate_ownership(
    p_owned_party_id BIGINT,
    p_owner_party_id BIGINT
) RETURNS NUMERIC(5,2)
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
    v_total NUMERIC(5,2);
BEGIN
    -- Direct ownership only for now
    -- TODO: Recursive CTE for indirect ownership chains
    SELECT COALESCE(SUM(ownership_percent), 0)
    INTO v_total
    FROM party_ownership
    WHERE owned_party_id = p_owned_party_id
      AND owner_party_id = p_owner_party_id
      AND (effective_to IS NULL OR effective_to >= CURRENT_DATE);

    RETURN v_total;
END;
$fn$;

COMMENT ON FUNCTION fn_aggregate_ownership IS
'Calculate aggregate ownership percentage. Simplified: direct only.
Production version needs recursive CTE to sum through ownership chains.';

-- =============================================================================
-- PART 7: ROW-LEVEL SECURITY
-- =============================================================================
-- All compliance tables have company_id and use direct tenant isolation.

ALTER TABLE party_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_registrations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON party_registrations
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE refund_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE refund_claims FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON refund_claims
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE party_screenings ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_screenings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON party_screenings
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE party_ownership ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_ownership FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON party_ownership
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

-- Grant access to authenticated role (matches 06_rls_policies.sql pattern)
GRANT SELECT, INSERT, UPDATE, DELETE ON party_registrations TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON refund_claims TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON party_screenings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON party_ownership TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE party_registrations_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE refund_claims_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE party_screenings_id_seq TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE party_ownership_id_seq TO authenticated;
