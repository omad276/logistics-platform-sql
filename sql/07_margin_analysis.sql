-- =============================================================================
-- Margin Analysis: Currency Fix, Committed Cost Tracking, Three-Way Margins
-- =============================================================================
-- RLS SETUP: After 06_rls_policies.sql, DML requires session variable.
-- Set to company 1 (Gulf Freight) which owns the seed data.
-- =============================================================================
SET app.company_id = '1';

-- =============================================================================
-- PART 1: Fix contract_charges currency handling
-- Original bug: contract_charges had currency but no fx_rate/base_amount,
-- causing meaningless sums across mixed currencies
-- =============================================================================

ALTER TABLE contract_charges
ADD COLUMN fx_rate NUMERIC(12,6) NOT NULL DEFAULT 1,
ADD COLUMN base_amount NUMERIC(15,2);

-- Backfill (assumes existing rows need conversion)
UPDATE contract_charges SET base_amount = amount * fx_rate;

ALTER TABLE contract_charges
ALTER COLUMN base_amount SET NOT NULL;

COMMENT ON COLUMN contract_charges.fx_rate IS 'Exchange rate to base currency at contract time';
COMMENT ON COLUMN contract_charges.base_amount IS 'Amount in company base currency (amount * fx_rate)';

-- =============================================================================
-- PART 2: Add superseded_by for estimate → actual linkage
-- =============================================================================

ALTER TABLE shipment_financials
ADD COLUMN superseded_by BIGINT REFERENCES shipment_financials(id);

-- Only estimates can be superseded
ALTER TABLE shipment_financials
ADD CONSTRAINT fin_only_estimates_superseded
    CHECK (superseded_by IS NULL OR is_estimated);

-- No self-reference
ALTER TABLE shipment_financials
ADD CONSTRAINT fin_no_self_supersede
    CHECK (superseded_by IS NULL OR superseded_by <> id);

-- One actual supersedes at most one estimate
CREATE UNIQUE INDEX uq_fin_superseded_by
    ON shipment_financials(superseded_by)
    WHERE superseded_by IS NOT NULL;

CREATE INDEX idx_fin_superseded_by ON shipment_financials(superseded_by)
    WHERE superseded_by IS NOT NULL;

-- =============================================================================
-- PART 3: Trigger for cross-row validation
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_validate_superseded_by()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_superseding RECORD;
BEGIN
    IF NEW.superseded_by IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT id, shipment_id, cost_category_id, is_estimated, direction
    INTO v_superseding
    FROM shipment_financials
    WHERE id = NEW.superseded_by;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'superseded_by references non-existent row %', NEW.superseded_by;
    END IF;

    IF v_superseding.is_estimated THEN
        RAISE EXCEPTION 'superseded_by must reference an actual (is_estimated=FALSE)';
    END IF;

    IF v_superseding.shipment_id <> NEW.shipment_id THEN
        RAISE EXCEPTION 'superseded_by must reference same shipment';
    END IF;

    IF v_superseding.cost_category_id <> NEW.cost_category_id THEN
        RAISE EXCEPTION 'superseded_by must reference same cost category';
    END IF;

    IF v_superseding.direction <> NEW.direction THEN
        RAISE EXCEPTION 'superseded_by must reference same direction';
    END IF;

    RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_validate_superseded_by
    BEFORE INSERT OR UPDATE OF superseded_by ON shipment_financials
    FOR EACH ROW
    EXECUTE FUNCTION fn_validate_superseded_by();

-- =============================================================================
-- PART 4: Three-way margin view
-- =============================================================================

DROP VIEW IF EXISTS v_shipment_profitability;

CREATE VIEW v_shipment_margin_analysis AS
WITH contract_revenue AS (
    SELECT
        s.id AS shipment_id,
        SUM(cc.base_amount) AS contracted_revenue
    FROM shipments s
    JOIN contracts c ON c.id = s.contract_id
    JOIN contract_charges cc ON cc.contract_id = c.id
    GROUP BY s.id
),
financials AS (
    SELECT
        shipment_id,
        -- Actual revenue (invoiced)
        SUM(CASE WHEN direction = 'revenue' AND NOT is_estimated
            THEN base_amount ELSE 0 END) AS actual_revenue,
        -- Actual cost (invoiced)
        SUM(CASE WHEN direction = 'cost' AND NOT is_estimated
            THEN base_amount ELSE 0 END) AS actual_cost,
        -- Original committed cost (ALL estimates at booking)
        SUM(CASE WHEN direction = 'cost' AND is_estimated
            THEN base_amount ELSE 0 END) AS original_committed_cost,
        -- Remaining committed (estimates NOT yet superseded)
        SUM(CASE WHEN direction = 'cost' AND is_estimated AND superseded_by IS NULL
            THEN base_amount ELSE 0 END) AS remaining_committed_cost
    FROM shipment_financials
    GROUP BY shipment_id
)
SELECT
    s.id AS shipment_id,
    s.shipment_no,
    s.status,
    s.company_id,

    -- Revenue
    COALESCE(cr.contracted_revenue, 0) AS contracted_revenue,
    COALESCE(f.actual_revenue, 0) AS actual_revenue,

    -- Costs
    COALESCE(f.original_committed_cost, 0) AS original_committed_cost,
    COALESCE(f.remaining_committed_cost, 0) AS remaining_committed_cost,
    COALESCE(f.actual_cost, 0) AS actual_cost,
    COALESCE(f.actual_cost, 0) + COALESCE(f.remaining_committed_cost, 0) AS total_projected_cost,

    -- =========================================
    -- BOOKED MARGIN (at contract signing)
    -- contracted_revenue - original_committed_cost
    -- =========================================
    COALESCE(cr.contracted_revenue, 0) - COALESCE(f.original_committed_cost, 0)
        AS booked_margin_amount,
    CASE WHEN COALESCE(cr.contracted_revenue, 0) > 0 THEN
        ROUND(((cr.contracted_revenue - COALESCE(f.original_committed_cost, 0))
               / cr.contracted_revenue * 100)::NUMERIC, 2)
    ELSE NULL END AS booked_margin_pct,

    -- =========================================
    -- PROJECTED MARGIN (current estimate)
    -- contracted_revenue - (actuals + remaining committed)
    -- =========================================
    COALESCE(cr.contracted_revenue, 0) -
        (COALESCE(f.actual_cost, 0) + COALESCE(f.remaining_committed_cost, 0))
        AS projected_margin_amount,
    CASE WHEN COALESCE(cr.contracted_revenue, 0) > 0 THEN
        ROUND(((cr.contracted_revenue - (COALESCE(f.actual_cost, 0) + COALESCE(f.remaining_committed_cost, 0)))
               / cr.contracted_revenue * 100)::NUMERIC, 2)
    ELSE NULL END AS projected_margin_pct,

    -- =========================================
    -- ACTUAL MARGIN (only when closed)
    -- actual_revenue - actual_cost
    -- Reflects disputes, credit notes, rebilling
    -- =========================================
    CASE WHEN s.status IN ('delivered', 'closed') THEN
        COALESCE(f.actual_revenue, 0) - COALESCE(f.actual_cost, 0)
    ELSE NULL END AS actual_margin_amount,
    CASE WHEN s.status IN ('delivered', 'closed') AND COALESCE(f.actual_revenue, 0) > 0 THEN
        ROUND(((f.actual_revenue - COALESCE(f.actual_cost, 0)) / f.actual_revenue * 100)::NUMERIC, 2)
    ELSE NULL END AS actual_margin_pct,

    -- =========================================
    -- VARIANCE: how much actual differs from committed
    -- Positive = over budget, Negative = under budget
    -- =========================================
    COALESCE(f.actual_cost, 0) -
        (COALESCE(f.original_committed_cost, 0) - COALESCE(f.remaining_committed_cost, 0))
        AS cost_variance_to_date

FROM shipments s
LEFT JOIN contract_revenue cr ON cr.shipment_id = s.id
LEFT JOIN financials f ON f.shipment_id = s.id;

COMMENT ON VIEW v_shipment_margin_analysis IS
'Three-way margin analysis with proper cost tracking:

BOOKED MARGIN (at signing):
  contracted_revenue - original_committed_cost
  All supplier quotes recorded as estimates at booking time.

PROJECTED MARGIN (during execution):
  contracted_revenue - (actual_cost + remaining_committed_cost)
  Updates as estimates are superseded by actuals.

ACTUAL MARGIN (closed shipments only):
  actual_revenue - actual_cost
  Uses invoiced revenue (not contracted) to reflect disputes/credits.
  NULL for open shipments - do not misuse as final margin.

COST VARIANCE TO DATE:
  actual_cost - superseded_committed_cost
  Positive = running over budget
  Negative = running under budget

WORKFLOW:
1. At booking: INSERT estimates (is_estimated=TRUE)
2. When invoice arrives: INSERT actual, UPDATE estimate.superseded_by = actual.id
3. View automatically tracks original vs remaining committed costs';
