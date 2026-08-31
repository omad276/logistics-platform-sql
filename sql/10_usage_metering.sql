-- =============================================================================
-- 10_usage_metering.sql
-- Usage metering and billing layer: meter consumption in points, compute margin
--
-- Tables:
--   billing_plans         - Platform-defined subscription tiers (no RLS)
--   plan_event_rates      - Points per event type (no RLS)
--   company_subscriptions - Tenant subscription state
--   usage_events          - Append-only metering log
--   usage_periods         - Closed monthly aggregates for invoicing
--   tenant_costs          - Internal cost tracking (admin-only)
--
-- Run after 09_compliance_layer.sql
-- =============================================================================

SET app.company_id = '1';

-- =============================================================================
-- PART 1: ENUMERATIONS
-- =============================================================================

CREATE TYPE billable_event_type AS ENUM (
    'task_completed',
    'shipment_closed',
    'document_stored',
    'screening_run',
    'customs_declaration_filed',
    'api_call'
);

CREATE TYPE subscription_status AS ENUM (
    'trial',
    'active',
    'past_due',
    'cancelled',
    'suspended'
);

CREATE TYPE plan_tier AS ENUM (
    'individual',
    'company',
    'enterprise'
);

-- =============================================================================
-- PART 2: BILLING PLANS (GLOBAL REFERENCE DATA)
-- =============================================================================
-- Platform-defined plans, not tenant-defined. Readable by all, writable only
-- by migration role. No RLS.

CREATE TABLE billing_plans (
    id                    BIGSERIAL PRIMARY KEY,
    code                  VARCHAR(30)   NOT NULL UNIQUE,
    name                  VARCHAR(100)  NOT NULL,
    tier                  plan_tier     NOT NULL,
    base_fee              NUMERIC(14,2) NOT NULL DEFAULT 0,
    points_included       INTEGER       NOT NULL,
    overage_point_price   NUMERIC(10,4) NOT NULL,
    currency              CHAR(3)       NOT NULL DEFAULT 'USD',
    billing_cycle_days    SMALLINT      NOT NULL DEFAULT 30,
    is_active             BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT billing_plans_points_positive CHECK (points_included >= 0),
    CONSTRAINT billing_plans_price_positive CHECK (overage_point_price >= 0),
    CONSTRAINT billing_plans_base_fee_positive CHECK (base_fee >= 0),
    CONSTRAINT billing_plans_cycle_positive CHECK (billing_cycle_days > 0)
);

COMMENT ON TABLE billing_plans IS
'Platform-defined subscription plans. Global reference data, no tenant ownership.
Points-based metering with overage pricing.';

-- =============================================================================
-- PART 3: PLAN EVENT RATES
-- =============================================================================
-- Points charged per event type. Pricing is data, not code.

CREATE TABLE plan_event_rates (
    plan_id           BIGINT             NOT NULL REFERENCES billing_plans(id) ON DELETE CASCADE,
    event_type        billable_event_type NOT NULL,
    points_per_event  NUMERIC(10,3)      NOT NULL DEFAULT 1,

    PRIMARY KEY (plan_id, event_type),
    CONSTRAINT plan_event_rates_positive CHECK (points_per_event >= 0)
);

COMMENT ON TABLE plan_event_rates IS
'Points charged per event type per plan. Same principle as workflow templates:
pricing is data, not code.';

-- =============================================================================
-- PART 4: COMPANY SUBSCRIPTIONS
-- =============================================================================
-- One active subscription per company at a time. EXCLUDE prevents overlapping periods.

CREATE TABLE company_subscriptions (
    id                    BIGSERIAL PRIMARY KEY,
    company_id            BIGINT            NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    plan_id               BIGINT            NOT NULL REFERENCES billing_plans(id),
    status                subscription_status NOT NULL DEFAULT 'trial',
    started_on            DATE              NOT NULL DEFAULT CURRENT_DATE,
    current_period_start  DATE              NOT NULL DEFAULT CURRENT_DATE,
    current_period_end    DATE              NOT NULL,
    auto_renew            BOOLEAN           NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMPTZ       NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ       NOT NULL DEFAULT now(),

    CONSTRAINT subscriptions_period_order CHECK (current_period_end >= current_period_start),
    CONSTRAINT subscriptions_no_overlap EXCLUDE USING gist (
        company_id WITH =,
        daterange(current_period_start, current_period_end, '[]') WITH &&
    )
);

CREATE INDEX idx_subscriptions_company ON company_subscriptions(company_id, status);
CREATE INDEX idx_subscriptions_active ON company_subscriptions(company_id)
    WHERE status IN ('trial', 'active');

COMMENT ON TABLE company_subscriptions IS
'Tenant subscription state. EXCLUDE constraint prevents overlapping periods for one company.
Only trial/active subscriptions generate metering records.';

-- =============================================================================
-- PART 5: USAGE EVENTS (APPEND-ONLY)
-- =============================================================================
-- Core metering table. Never updated, never deleted.

CREATE TABLE usage_events (
    id                      BIGSERIAL PRIMARY KEY,
    company_id              BIGINT             NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id         BIGINT             NOT NULL REFERENCES company_subscriptions(id),
    event_type              billable_event_type NOT NULL,
    points_charged          NUMERIC(10,3)      NOT NULL,
    occurred_at             TIMESTAMPTZ        NOT NULL DEFAULT now(),

    -- Exclusive arc: exactly one source reference (except api_call which has none)
    task_id                 BIGINT             REFERENCES tasks(id) ON DELETE SET NULL,
    shipment_id             BIGINT             REFERENCES shipments(id) ON DELETE SET NULL,
    document_id             BIGINT             REFERENCES documents(id) ON DELETE SET NULL,
    customs_declaration_id  BIGINT             REFERENCES customs_declarations(id) ON DELETE SET NULL,
    party_screening_id      BIGINT             REFERENCES party_screenings(id) ON DELETE SET NULL,

    CONSTRAINT usage_events_points_positive CHECK (points_charged >= 0),
    CONSTRAINT usage_events_source_arc CHECK (
        -- At most one source reference
        num_nonnulls(task_id, shipment_id, document_id, customs_declaration_id, party_screening_id) <= 1
    ),
    CONSTRAINT usage_events_source_required CHECK (
        -- Non-api_call events must have exactly one source
        event_type = 'api_call'
        OR num_nonnulls(task_id, shipment_id, document_id, customs_declaration_id, party_screening_id) = 1
    )
);

CREATE INDEX idx_usage_events_period ON usage_events(company_id, occurred_at);
CREATE INDEX idx_usage_events_subscription ON usage_events(subscription_id, occurred_at);

COMMENT ON TABLE usage_events IS
'Append-only metering log. Written by triggers on operational tables.
Never updated, never deleted. Source FK identifies what triggered the event.';

-- =============================================================================
-- PART 6: USAGE PERIODS
-- =============================================================================
-- Closed monthly aggregates. Written once when period ends, then immutable.

CREATE TABLE usage_periods (
    id                    BIGSERIAL PRIMARY KEY,
    company_id            BIGINT         NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    subscription_id       BIGINT         NOT NULL REFERENCES company_subscriptions(id),
    period_start          DATE           NOT NULL,
    period_end            DATE           NOT NULL,
    points_included       INTEGER        NOT NULL,
    points_consumed       NUMERIC(12,3)  NOT NULL DEFAULT 0,
    points_overage        NUMERIC(12,3)  NOT NULL DEFAULT 0,
    overage_amount        NUMERIC(14,2)  NOT NULL DEFAULT 0,
    currency              CHAR(3)        NOT NULL,
    closed_at             TIMESTAMPTZ,
    invoice_id            BIGINT         REFERENCES invoices(id) ON DELETE SET NULL,

    UNIQUE (company_id, period_start),
    CONSTRAINT usage_periods_order CHECK (period_end >= period_start),
    CONSTRAINT usage_periods_overage_math CHECK (
        points_overage = GREATEST(0, points_consumed - points_included)
    )
);

CREATE INDEX idx_usage_periods_subscription ON usage_periods(subscription_id);
CREATE INDEX idx_usage_periods_open ON usage_periods(company_id)
    WHERE closed_at IS NULL;

COMMENT ON TABLE usage_periods IS
'Closed monthly aggregates for invoicing. Written once when period ends.
Immutable after closure so invoices never change retroactively.';

-- =============================================================================
-- PART 7: TENANT COSTS (INTERNAL ONLY)
-- =============================================================================
-- Platform economics: your actual cost to serve each tenant.
-- No tenant access. Populated by scheduled job, not application.

CREATE TABLE tenant_costs (
    id                    BIGSERIAL PRIMARY KEY,
    company_id            BIGINT         NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    period_start          DATE           NOT NULL,
    period_end            DATE           NOT NULL,
    db_storage_mb         NUMERIC(12,2)  NOT NULL DEFAULT 0,
    db_queries            BIGINT         NOT NULL DEFAULT 0,
    compute_units         NUMERIC(12,3)  NOT NULL DEFAULT 0,
    storage_cost          NUMERIC(14,2)  NOT NULL DEFAULT 0,
    compute_cost          NUMERIC(14,2)  NOT NULL DEFAULT 0,
    support_cost          NUMERIC(14,2)  NOT NULL DEFAULT 0,
    other_cost            NUMERIC(14,2)  NOT NULL DEFAULT 0,
    total_cost            NUMERIC(14,2)  NOT NULL DEFAULT 0,
    currency              CHAR(3)        NOT NULL DEFAULT 'USD',
    recorded_at           TIMESTAMPTZ    NOT NULL DEFAULT now(),

    UNIQUE (company_id, period_start),
    CONSTRAINT tenant_costs_period_order CHECK (period_end >= period_start),
    CONSTRAINT tenant_costs_total_sum CHECK (
        total_cost = storage_cost + compute_cost + support_cost + other_cost
    )
);

COMMENT ON TABLE tenant_costs IS
'Internal platform economics. Cost to serve each tenant per period.
Never exposed to tenants. Populated by scheduled job for margin analysis.';

-- =============================================================================
-- PART 8: METERING TRIGGERS
-- =============================================================================
-- Metering must be a trigger, not application code.
-- Important: metering must never block operations. If no active subscription
-- exists, the SELECT returns no rows and nothing is inserted.

-- -----------------------------------------------------------------------------
-- Task completion metering
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meter_task_completion() RETURNS TRIGGER AS $meter$
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
        INSERT INTO usage_events (company_id, subscription_id, event_type,
                                  points_charged, task_id)
        SELECT NEW.company_id, s.id, 'task_completed',
               COALESCE(r.points_per_event, 1), NEW.id
          FROM company_subscriptions s
          LEFT JOIN plan_event_rates r
                 ON r.plan_id = s.plan_id AND r.event_type = 'task_completed'
         WHERE s.company_id = NEW.company_id
           AND s.status IN ('trial', 'active');
    END IF;
    RETURN NEW;
END;
$meter$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_meter_completion
    AFTER UPDATE ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION fn_meter_task_completion();

COMMENT ON FUNCTION fn_meter_task_completion() IS
'Meters task completion events. Never raises exceptions; missing subscription
means no row inserted, operation proceeds normally.';

-- -----------------------------------------------------------------------------
-- Shipment close metering
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meter_shipment_close() RETURNS TRIGGER AS $meter$
BEGIN
    IF NEW.status = 'closed' AND OLD.status IS DISTINCT FROM 'closed' THEN
        INSERT INTO usage_events (company_id, subscription_id, event_type,
                                  points_charged, shipment_id)
        SELECT NEW.company_id, s.id, 'shipment_closed',
               COALESCE(r.points_per_event, 1), NEW.id
          FROM company_subscriptions s
          LEFT JOIN plan_event_rates r
                 ON r.plan_id = s.plan_id AND r.event_type = 'shipment_closed'
         WHERE s.company_id = NEW.company_id
           AND s.status IN ('trial', 'active');
    END IF;
    RETURN NEW;
END;
$meter$ LANGUAGE plpgsql;

CREATE TRIGGER trg_shipments_meter_close
    AFTER UPDATE ON shipments
    FOR EACH ROW
    EXECUTE FUNCTION fn_meter_shipment_close();

COMMENT ON FUNCTION fn_meter_shipment_close() IS
'Meters shipment close events. Silent on missing subscription.';

-- -----------------------------------------------------------------------------
-- Document storage metering
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meter_document_stored() RETURNS TRIGGER AS $meter$
BEGIN
    INSERT INTO usage_events (company_id, subscription_id, event_type,
                              points_charged, document_id)
    SELECT NEW.company_id, s.id, 'document_stored',
           COALESCE(r.points_per_event, 1), NEW.id
      FROM company_subscriptions s
      LEFT JOIN plan_event_rates r
             ON r.plan_id = s.plan_id AND r.event_type = 'document_stored'
     WHERE s.company_id = NEW.company_id
       AND s.status IN ('trial', 'active');
    RETURN NEW;
END;
$meter$ LANGUAGE plpgsql;

CREATE TRIGGER trg_documents_meter_insert
    AFTER INSERT ON documents
    FOR EACH ROW
    EXECUTE FUNCTION fn_meter_document_stored();

COMMENT ON FUNCTION fn_meter_document_stored() IS
'Meters document upload events. Silent on missing subscription.';

-- -----------------------------------------------------------------------------
-- Customs declaration submission metering
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meter_customs_declaration() RETURNS TRIGGER AS $meter$
BEGIN
    -- Meter when submitted_at is set (status changes to submitted)
    IF NEW.status = 'submitted' AND OLD.status IS DISTINCT FROM 'submitted' THEN
        INSERT INTO usage_events (company_id, subscription_id, event_type,
                                  points_charged, customs_declaration_id)
        SELECT NEW.company_id, s.id, 'customs_declaration_filed',
               COALESCE(r.points_per_event, 1), NEW.id
          FROM company_subscriptions s
          LEFT JOIN plan_event_rates r
                 ON r.plan_id = s.plan_id AND r.event_type = 'customs_declaration_filed'
         WHERE s.company_id = NEW.company_id
           AND s.status IN ('trial', 'active');
    END IF;
    RETURN NEW;
END;
$meter$ LANGUAGE plpgsql;

CREATE TRIGGER trg_customs_declarations_meter_submit
    AFTER UPDATE ON customs_declarations
    FOR EACH ROW
    EXECUTE FUNCTION fn_meter_customs_declaration();

COMMENT ON FUNCTION fn_meter_customs_declaration() IS
'Meters customs declaration submission. Silent on missing subscription.';

-- -----------------------------------------------------------------------------
-- Party screening metering
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meter_party_screening() RETURNS TRIGGER AS $meter$
BEGIN
    INSERT INTO usage_events (company_id, subscription_id, event_type,
                              points_charged, party_screening_id)
    SELECT NEW.company_id, s.id, 'screening_run',
           COALESCE(r.points_per_event, 1), NEW.id
      FROM company_subscriptions s
      LEFT JOIN plan_event_rates r
             ON r.plan_id = s.plan_id AND r.event_type = 'screening_run'
     WHERE s.company_id = NEW.company_id
       AND s.status IN ('trial', 'active');
    RETURN NEW;
END;
$meter$ LANGUAGE plpgsql;

CREATE TRIGGER trg_party_screenings_meter_insert
    AFTER INSERT ON party_screenings
    FOR EACH ROW
    EXECUTE FUNCTION fn_meter_party_screening();

COMMENT ON FUNCTION fn_meter_party_screening() IS
'Meters sanctions screening events. Silent on missing subscription.';

-- =============================================================================
-- PART 9: VIEWS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Current period usage for a tenant
-- -----------------------------------------------------------------------------
CREATE VIEW v_tenant_usage_current AS
SELECT
    s.company_id,
    c.legal_name AS company_name,
    s.id AS subscription_id,
    bp.name AS plan_name,
    bp.points_included,
    s.current_period_start,
    s.current_period_end,
    COALESCE(SUM(ue.points_charged), 0) AS points_consumed,
    bp.points_included - COALESCE(SUM(ue.points_charged), 0) AS points_remaining,
    GREATEST(0, COALESCE(SUM(ue.points_charged), 0) - bp.points_included) AS projected_overage,
    CASE
        WHEN bp.points_included = 0 THEN 100
        ELSE ROUND(COALESCE(SUM(ue.points_charged), 0) / bp.points_included * 100, 2)
    END AS percent_used
FROM company_subscriptions s
JOIN companies c ON c.id = s.company_id
JOIN billing_plans bp ON bp.id = s.plan_id
LEFT JOIN usage_events ue ON ue.subscription_id = s.id
    AND ue.occurred_at >= s.current_period_start
    AND ue.occurred_at < s.current_period_end + INTERVAL '1 day'
WHERE s.status IN ('trial', 'active')
  AND s.company_id = current_company_id()
GROUP BY s.id, c.legal_name, bp.name, bp.points_included,
         s.current_period_start, s.current_period_end, s.company_id;

COMMENT ON VIEW v_tenant_usage_current IS
'Live period usage: points consumed, remaining, projected overage, percent used.
Tenant-isolated via current_company_id().';

-- -----------------------------------------------------------------------------
-- Tenant profitability analysis (admin view, no tenant access)
-- -----------------------------------------------------------------------------
CREATE VIEW v_tenant_profitability AS
SELECT
    c.id AS company_id,
    c.legal_name AS company_name,
    tc.period_start,
    -- Revenue: subscription base_fee + overage
    COALESCE(bp.base_fee, 0) + COALESCE(up.overage_amount, 0) AS revenue,
    tc.total_cost AS cost,
    (COALESCE(bp.base_fee, 0) + COALESCE(up.overage_amount, 0)) - tc.total_cost AS gross_profit,
    CASE
        WHEN COALESCE(bp.base_fee, 0) + COALESCE(up.overage_amount, 0) = 0 THEN NULL
        ELSE ROUND(
            ((COALESCE(bp.base_fee, 0) + COALESCE(up.overage_amount, 0)) - tc.total_cost)
            / (COALESCE(bp.base_fee, 0) + COALESCE(up.overage_amount, 0)) * 100, 2
        )
    END AS margin_percent
FROM tenant_costs tc
JOIN companies c ON c.id = tc.company_id
LEFT JOIN usage_periods up ON up.company_id = tc.company_id
    AND up.period_start = tc.period_start
LEFT JOIN company_subscriptions cs ON cs.company_id = tc.company_id
    AND cs.current_period_start <= tc.period_start
    AND cs.current_period_end >= tc.period_end
LEFT JOIN billing_plans bp ON bp.id = cs.plan_id;

COMMENT ON VIEW v_tenant_profitability IS
'Revenue vs cost per tenant per period. Same shape as v_shipment_profitability.
Admin-only: no tenant should see their cost-to-serve.';

-- =============================================================================
-- PART 10: ROW LEVEL SECURITY
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tenant-isolated tables: standard policy
-- -----------------------------------------------------------------------------
ALTER TABLE company_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON company_subscriptions
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON usage_events
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE usage_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON usage_periods
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

-- -----------------------------------------------------------------------------
-- Global reference tables: no RLS, SELECT only
-- -----------------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON billing_plans FROM authenticated;
GRANT SELECT ON billing_plans TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON plan_event_rates FROM authenticated;
GRANT SELECT ON plan_event_rates TO authenticated;

-- -----------------------------------------------------------------------------
-- tenant_costs: NO tenant access at all
-- Internal platform economics only readable by admin role
-- -----------------------------------------------------------------------------
ALTER TABLE tenant_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_costs FORCE ROW LEVEL SECURITY;
-- No policy for authenticated role = no access
-- Admin role bypasses RLS

-- Defense in depth: revoke all privileges even though RLS blocks access.
-- If RLS were ever disabled, this prevents immediate exposure.
REVOKE ALL ON tenant_costs FROM authenticated;

COMMENT ON TABLE tenant_costs IS
'Internal platform economics. RLS enabled with NO policy for authenticated role.
A tenant must never see what they cost you.';

-- =============================================================================
-- PART 11: SEED DATA - EXAMPLE BILLING PLANS
-- =============================================================================

INSERT INTO billing_plans (code, name, tier, base_fee, points_included, overage_point_price, currency, billing_cycle_days) VALUES
    ('STARTER', 'Starter Plan', 'individual', 49.00, 500, 0.0200, 'USD', 30),
    ('BUSINESS', 'Business Plan', 'company', 299.00, 5000, 0.0150, 'USD', 30),
    ('ENTERPRISE', 'Enterprise Plan', 'enterprise', 1499.00, 50000, 0.0100, 'USD', 30);

-- Default event rates for each plan
INSERT INTO plan_event_rates (plan_id, event_type, points_per_event) VALUES
    -- Starter: higher per-event costs
    (1, 'task_completed', 1.0),
    (1, 'shipment_closed', 5.0),
    (1, 'document_stored', 0.5),
    (1, 'screening_run', 2.0),
    (1, 'customs_declaration_filed', 3.0),
    (1, 'api_call', 0.1),
    -- Business: moderate costs
    (2, 'task_completed', 0.8),
    (2, 'shipment_closed', 4.0),
    (2, 'document_stored', 0.3),
    (2, 'screening_run', 1.5),
    (2, 'customs_declaration_filed', 2.5),
    (2, 'api_call', 0.05),
    -- Enterprise: lowest unit costs
    (3, 'task_completed', 0.5),
    (3, 'shipment_closed', 3.0),
    (3, 'document_stored', 0.2),
    (3, 'screening_run', 1.0),
    (3, 'customs_declaration_filed', 2.0),
    (3, 'api_call', 0.02);
