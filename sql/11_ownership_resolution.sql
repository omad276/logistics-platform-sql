-- =============================================================================
-- 11_ownership_resolution.sql
-- Recursive ownership resolution and sanctions exposure analysis
--
-- Functions:
--   fn_effective_ownership   - walks ownership graph, handles cycles
--   fn_sanctions_exposure    - jurisdiction-specific blocking determination
--
-- Three traps this implementation avoids:
--   1. Circular ownership detection (path array + depth guard)
--   2. Aggregate at end, not during recursion (sum by owner in final SELECT)
--   3. Multiply along path, sum across paths
--
-- Run after 10_usage_metering.sql
-- =============================================================================

SET app.company_id = '1';

-- =============================================================================
-- PART 1: EFFECTIVE OWNERSHIP RESOLUTION
-- =============================================================================
-- Walks the ownership graph from a target party upward to all ultimate owners.
-- Returns effective ownership percentage accounting for indirect chains.
--
-- Example: A owns 60% of B, B owns 80% of C
--   → A effectively owns 48% of C (0.60 × 0.80 = 0.48)
-- If A also owns 10% of C directly:
--   → A's total effective ownership is 58% (48% + 10%)

CREATE OR REPLACE FUNCTION fn_effective_ownership(
    p_target_party_id BIGINT,
    p_as_of DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    owner_party_id BIGINT,
    effective_percent NUMERIC(10,4),
    path_count INT
)
LANGUAGE plpgsql
STABLE
AS $own$
BEGIN
    RETURN QUERY
    WITH RECURSIVE chain AS (
        -- Base case: direct owners of the target
        SELECT
            po.owner_party_id,
            po.owned_party_id,
            po.ownership_percent::NUMERIC AS effective_pct,  -- cast to avoid type mismatch
            ARRAY[po.owned_party_id] AS path,
            1 AS depth
        FROM party_ownership po
        WHERE po.owned_party_id = p_target_party_id
          AND po.owner_party_id IS NOT NULL  -- skip individual-only records
          AND p_as_of >= po.effective_from
          AND p_as_of <= COALESCE(po.effective_to, 'infinity'::DATE)

        UNION ALL

        -- Recursive case: owners of owners
        SELECT
            po.owner_party_id,
            c.owned_party_id,
            (c.effective_pct * po.ownership_percent / 100)::NUMERIC,
            c.path || po.owner_party_id,
            c.depth + 1
        FROM chain c
        JOIN party_ownership po ON po.owned_party_id = c.owner_party_id
        WHERE po.owner_party_id IS NOT NULL
          AND NOT po.owner_party_id = ANY(c.path)  -- cycle guard: don't revisit an owner
          AND c.depth < 10                          -- depth guard
          AND p_as_of >= po.effective_from
          AND p_as_of <= COALESCE(po.effective_to, 'infinity'::DATE)
    )
    -- Aggregate: sum effective percentages across all paths to each owner
    SELECT
        c.owner_party_id,
        SUM(c.effective_pct)::NUMERIC(10,4) AS effective_percent,
        COUNT(*)::INT AS path_count
    FROM chain c
    GROUP BY c.owner_party_id;
END;
$own$;

COMMENT ON FUNCTION fn_effective_ownership(BIGINT, DATE) IS
'Resolves effective ownership percentage for all owners of a target party.
Handles circular ownership (cycle detection), multi-path ownership (sums paths),
and chain ownership (multiplies along path). Temporal: uses p_as_of for validity.';

-- =============================================================================
-- PART 2: SANCTIONS EXPOSURE ANALYSIS
-- =============================================================================
-- Determines if a party is blocked under various sanctions regimes.
-- Thresholds differ by jurisdiction:
--   US OFAC: >= 50% aggregate sanctioned ownership
--   EU:      >= 50% aggregate sanctioned ownership
--   UK:      >  50% (strictly greater) OR has_control regardless of %
--   Canada:  >= 50% (assumed, verify before production use)
--
-- Returns one row per jurisdiction with blocking determination.

CREATE OR REPLACE FUNCTION fn_sanctions_exposure(
    p_target_party_id BIGINT,
    p_as_of DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    jurisdiction TEXT,
    threshold_percent NUMERIC,
    aggregate_sanctioned_percent NUMERIC(10,4),
    is_blocked BOOLEAN,
    basis TEXT
)
LANGUAGE plpgsql
STABLE
AS $own$
DECLARE
    v_direct_match BOOLEAN := FALSE;
    v_sanctioned_ownership NUMERIC(10,4) := 0;
    v_has_sanctioned_control BOOLEAN := FALSE;
BEGIN
    -- Check if target itself is directly designated
    SELECT EXISTS (
        SELECT 1 FROM party_screenings ps
        WHERE ps.party_id = p_target_party_id
          AND ps.result = 'confirmed_match'
          AND (ps.disposition IS NULL OR ps.disposition <> 'false_positive')
          AND (ps.valid_until IS NULL OR ps.valid_until > now())
        ORDER BY ps.screened_at DESC
        LIMIT 1
    ) INTO v_direct_match;

    -- If directly designated, blocked everywhere
    IF v_direct_match THEN
        RETURN QUERY
        SELECT j.jurisdiction, j.threshold_pct, 100.0::NUMERIC(10,4), TRUE, 'direct_designation'::TEXT
        FROM (VALUES
            ('US_OFAC', 50.0),
            ('EU', 50.0),
            ('UK', 50.0),
            ('CA', 50.0)
        ) AS j(jurisdiction, threshold_pct);
        RETURN;
    END IF;

    -- Calculate aggregate sanctioned ownership
    SELECT COALESCE(SUM(eo.effective_percent), 0)
    INTO v_sanctioned_ownership
    FROM fn_effective_ownership(p_target_party_id, p_as_of) eo
    WHERE EXISTS (
        SELECT 1 FROM party_screenings ps
        WHERE ps.party_id = eo.owner_party_id
          AND ps.result = 'confirmed_match'
          AND (ps.disposition IS NULL OR ps.disposition <> 'false_positive')
          AND (ps.valid_until IS NULL OR ps.valid_until > now())
    );

    -- Check for control by sanctioned party (UK-specific basis)
    SELECT EXISTS (
        SELECT 1
        FROM party_ownership po
        WHERE po.owned_party_id = p_target_party_id
          AND po.is_controlling = TRUE
          AND p_as_of >= po.effective_from
          AND p_as_of <= COALESCE(po.effective_to, 'infinity'::DATE)
          AND EXISTS (
              SELECT 1 FROM party_screenings ps
              WHERE ps.party_id = po.owner_party_id
                AND ps.result = 'confirmed_match'
                AND (ps.disposition IS NULL OR ps.disposition <> 'false_positive')
                AND (ps.valid_until IS NULL OR ps.valid_until > now())
          )
    ) INTO v_has_sanctioned_control;

    -- Return jurisdiction-specific determinations
    -- US OFAC: >= 50%
    RETURN QUERY
    SELECT
        'US_OFAC'::TEXT,
        50.0::NUMERIC,
        v_sanctioned_ownership,
        v_sanctioned_ownership >= 50.0,
        CASE WHEN v_sanctioned_ownership >= 50.0 THEN 'ownership' ELSE NULL END;

    -- EU: >= 50%
    RETURN QUERY
    SELECT
        'EU'::TEXT,
        50.0::NUMERIC,
        v_sanctioned_ownership,
        v_sanctioned_ownership >= 50.0,
        CASE WHEN v_sanctioned_ownership >= 50.0 THEN 'ownership' ELSE NULL END;

    -- UK: > 50% OR control
    RETURN QUERY
    SELECT
        'UK'::TEXT,
        50.0::NUMERIC,
        v_sanctioned_ownership,
        v_sanctioned_ownership > 50.0 OR v_has_sanctioned_control,
        CASE
            WHEN v_has_sanctioned_control AND v_sanctioned_ownership <= 50.0 THEN 'control'
            WHEN v_sanctioned_ownership > 50.0 THEN 'ownership'
            ELSE NULL
        END;

    -- Canada: threshold UNVERIFIED - using 50% as placeholder
    -- TODO: Verify against SEMA (Special Economic Measures Act) guidance before production
    RETURN QUERY
    SELECT
        'CA'::TEXT,
        50.0::NUMERIC,  -- UNVERIFIED: confirm against Canadian SEMA guidance
        v_sanctioned_ownership,
        v_sanctioned_ownership >= 50.0,
        CASE WHEN v_sanctioned_ownership >= 50.0 THEN 'ownership (UNVERIFIED)' ELSE NULL END;

    RETURN;
END;
$own$;

COMMENT ON FUNCTION fn_sanctions_exposure(BIGINT, DATE) IS
'Determines sanctions blocking status across jurisdictions.
US/EU: blocked at >= 50% sanctioned ownership.
UK: blocked at > 50% OR if sanctioned party has control (is_controlling).
Canada: UNVERIFIED - using 50% placeholder. Confirm against SEMA guidance before production.
Returns one row per jurisdiction with blocking determination and basis.';

-- =============================================================================
-- PART 3: HELPER VIEW FOR CURRENT EXPOSURE
-- =============================================================================
-- Convenience view showing sanctions exposure for all parties as of today.

CREATE VIEW v_party_sanctions_status AS
SELECT
    p.id AS party_id,
    p.legal_name,
    p.company_id,
    se.jurisdiction,
    se.threshold_percent,
    se.aggregate_sanctioned_percent,
    se.is_blocked,
    se.basis
FROM parties p
CROSS JOIN LATERAL fn_sanctions_exposure(p.id, CURRENT_DATE) se
WHERE p.is_active = TRUE;

COMMENT ON VIEW v_party_sanctions_status IS
'Current sanctions exposure for all active parties across all jurisdictions.
Use for dashboards and compliance reporting.';
