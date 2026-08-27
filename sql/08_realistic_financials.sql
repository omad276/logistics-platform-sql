-- =============================================================================
-- Realistic Financial Seed Data
-- Demonstrates three-way margin analysis with a shipment going underwater
-- =============================================================================
-- Run AFTER: 01_schema.sql, 02_seed.sql, 06_rls_policies.sql, 07_margin_analysis.sql
-- Cost categories are created in 02_seed.sql

-- =============================================================================
-- RLS SETUP: Session variable required after 06_rls_policies.sql
-- current_company_id() fails loud when unset, so we must set it before DML
-- =============================================================================
SET app.company_id = '1';

-- =============================================================================
-- PART 1: Replace seed financials with realistic actuals showing loss
-- =============================================================================

-- Clear estimates from 02_seed.sql (we'll recreate with realistic costs)
DELETE FROM shipment_financials WHERE shipment_id = 1;

-- =============================================================================
-- ESTIMATES (is_estimated = TRUE) - What was quoted at booking
-- These represent the "committed cost" at contract signing
-- =============================================================================

-- 1. Ocean freight estimate (quoted $8,200 USD = 30,094 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 1, 'cost', 'MSC ocean freight Port Sudan - Jebel Ali (quoted)',
    8200.00, 'USD', 3.67, 30094.00, TRUE, CURRENT_DATE - 14
);

-- 2. Origin inland trucking estimate ($1,400 = 5,138 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 2, 'cost', 'Road freight Khartoum - Port Sudan (quoted)',
    1400.00, 'USD', 3.67, 5138.00, TRUE, CURRENT_DATE - 14
);

-- 3. Loading/handling estimate ($600 = 2,202 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 4, 'cost', 'Loading at origin + stuffing (quoted)',
    600.00, 'USD', 3.67, 2202.00, TRUE, CURRENT_DATE - 14
);

-- 4. THC estimate ($500 = 1,835 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 6, 'cost', 'Jebel Ali THC (quoted)',
    500.00, 'USD', 3.67, 1835.00, TRUE, CURRENT_DATE - 14
);

-- 5. Export customs estimate ($280 = 1,028 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 7, 'cost', 'Export clearance Port Sudan (quoted)',
    280.00, 'USD', 3.67, 1027.60, TRUE, CURRENT_DATE - 14
);

-- 6. Import customs estimate ($350 = 1,285 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 8, 'cost', 'Import clearance UAE (quoted)',
    350.00, 'USD', 3.67, 1284.50, TRUE, CURRENT_DATE - 14
);

-- 7. Storage estimate (standard 2 days: $180 = 660 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 11, 'cost', 'Bonded storage 2 days (quoted standard)',
    180.00, 'USD', 3.67, 660.60, TRUE, CURRENT_DATE - 14
);

-- 8. Destination delivery estimate ($550 = 2,019 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 3, 'cost', 'Delivery Jebel Ali - SAIF Zone (quoted)',
    550.00, 'USD', 3.67, 2018.50, TRUE, CURRENT_DATE - 14
);

-- 9. Unloading estimate ($150 = 551 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 5, 'cost', 'Unloading at buyer (quoted)',
    150.00, 'USD', 3.67, 550.50, TRUE, CURRENT_DATE - 14
);

-- PASS-THROUGH ESTIMATES (duty + VAT charged to customer, appear as cost AND revenue)

-- 10. Import duty estimate (5% on 68,500 = 3,425 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 9, 'cost', 'Import duty 5% (estimated)',
    3425.00, 'AED', 1.00, 3425.00, TRUE, CURRENT_DATE - 14
);

-- 11. Import VAT estimate (5% on 71,925 = 3,596 AED)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES (
    1, 1, 10, 'cost', 'Import VAT 5% (estimated)',
    3596.00, 'AED', 1.00, 3596.00, TRUE, CURRENT_DATE - 14
);

-- Pass-through recovery (same amounts as revenue)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES
    (1, 1, 16, 'revenue', 'Duty recovery from customer (estimated)', 3425.00, 'AED', 1.00, 3425.00, TRUE, CURRENT_DATE - 14),
    (1, 1, 17, 'revenue', 'VAT recovery from customer (estimated)', 3596.00, 'AED', 1.00, 3596.00, TRUE, CURRENT_DATE - 14);

-- =============================================================================
-- SUMMARY: Original committed costs at booking
-- =============================================================================
-- Ocean freight:        30,094 AED
-- Origin trucking:       5,138 AED
-- Loading/handling:      2,202 AED
-- THC:                   1,835 AED
-- Export customs:        1,028 AED
-- Import customs:        1,285 AED
-- Storage (2 days):        661 AED
-- Destination delivery:  2,019 AED
-- Unloading:               551 AED
-- Duty (pass-through):   3,425 AED
-- VAT (pass-through):    3,596 AED
-- ---------------------------------
-- TOTAL COMMITTED:      51,834 AED  (excluding pass-through: 44,813 AED)
-- REVENUE:              68,500 AED  (contract value)
-- PASS-THROUGH:          7,021 AED  (nets to zero)
-- BOOKED MARGIN:        23,687 AED  (34.6% - still optimistic!)
-- =============================================================================

-- =============================================================================
-- PART 3: ACTUALS - What actually happened (supersedes estimates)
-- =============================================================================

-- Store IDs for superseded_by linking
DO $$
DECLARE
    est_ocean_id BIGINT;
    est_storage_id BIGINT;
    est_duty_id BIGINT;
    est_vat_id BIGINT;
    act_ocean_id BIGINT;
    act_storage_id BIGINT;
    act_demurrage_id BIGINT;
    act_inspection_id BIGINT;
BEGIN
    -- Get estimate IDs
    SELECT id INTO est_ocean_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 1 AND is_estimated;

    SELECT id INTO est_storage_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 11 AND is_estimated;

    SELECT id INTO est_duty_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 9 AND is_estimated AND direction = 'cost';

    SELECT id INTO est_vat_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 10 AND is_estimated AND direction = 'cost';

    -- Insert actuals and get their IDs

    -- 1. Ocean freight ACTUAL (higher than quoted: $8,580 = 31,489 AED)
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 1, 'cost', 'MSC ocean freight Port Sudan - Jebel Ali (invoice)',
        8580.00, 'USD', 3.67, 31488.60, FALSE, CURRENT_DATE - 2
    ) RETURNING id INTO act_ocean_id;

    -- Link estimate to actual
    UPDATE shipment_financials
    SET superseded_by = act_ocean_id
    WHERE id = est_ocean_id;

    -- 2. Extended storage ACTUAL (7 days due to customs hold: $630 = 2,312 AED)
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 11, 'cost', 'Bonded storage 7 days (extended due to customs hold)',
        630.00, 'USD', 3.67, 2312.10, FALSE, CURRENT_DATE - 1
    ) RETURNING id INTO act_storage_id;

    -- Link storage estimate to actual
    UPDATE shipment_financials
    SET superseded_by = act_storage_id
    WHERE id = est_storage_id;

    -- 3. UNEXPECTED: Demurrage charges ($1,350 = 4,955 AED) - NOT IN ORIGINAL QUOTE
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 12, 'cost', 'Container demurrage - 5 days customs hold @ $270/day',
        1350.00, 'USD', 3.67, 4954.50, FALSE, CURRENT_DATE - 1
    );

    -- 4. UNEXPECTED: MOCCAE phytosanitary inspection ($280 = 1,028 AED)
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 13, 'cost', 'MOCCAE phytosanitary inspection fee',
        280.00, 'USD', 3.67, 1027.60, FALSE, CURRENT_DATE - 1
    );

    -- 5. UNEXPECTED: Inspection handling ($180 = 661 AED)
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 13, 'cost', 'Container unstuffing/restuffing for inspection',
        180.00, 'USD', 3.67, 660.60, FALSE, CURRENT_DATE - 1
    );

    -- 6. Duty ACTUAL (same as estimate - no change needed, but log as actual)
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 9, 'cost', 'Import duty 5% (paid)',
        3425.00, 'AED', 1.00, 3425.00, FALSE, CURRENT_DATE - 1
    ) RETURNING id INTO act_demurrage_id;

    UPDATE shipment_financials
    SET superseded_by = act_demurrage_id
    WHERE id = est_duty_id;

    -- 7. VAT ACTUAL
    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 10, 'cost', 'Import VAT 5% (paid)',
        3596.00, 'AED', 1.00, 3596.00, FALSE, CURRENT_DATE - 1
    ) RETURNING id INTO act_inspection_id;

    UPDATE shipment_financials
    SET superseded_by = act_inspection_id
    WHERE id = est_vat_id;

END $$;

-- Other actuals that match estimates (trucking, loading, customs, delivery, unloading)
-- These supersede their estimates but at the same price

DO $$
DECLARE
    est_id BIGINT;
    act_id BIGINT;
BEGIN
    -- Origin trucking
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 2 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 2, 'cost', 'Road freight Khartoum - Port Sudan (invoice)',
        1400.00, 'USD', 3.67, 5138.00, FALSE, CURRENT_DATE - 12
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- Loading
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 4 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 4, 'cost', 'Loading at origin + stuffing (invoice)',
        600.00, 'USD', 3.67, 2202.00, FALSE, CURRENT_DATE - 11
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- THC
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 6 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 6, 'cost', 'Jebel Ali THC (invoice)',
        500.00, 'USD', 3.67, 1835.00, FALSE, CURRENT_DATE - 2
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- Export customs
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 7 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 7, 'cost', 'Export clearance Port Sudan (invoice)',
        280.00, 'USD', 3.67, 1027.60, FALSE, CURRENT_DATE - 10
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- Import customs
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 8 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 8, 'cost', 'Import clearance UAE (invoice)',
        350.00, 'USD', 3.67, 1284.50, FALSE, CURRENT_DATE - 1
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- Destination delivery
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 3 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 3, 'cost', 'Delivery Jebel Ali - SAIF Zone (invoice)',
        550.00, 'USD', 3.67, 2018.50, FALSE, CURRENT_DATE
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;

    -- Unloading
    SELECT id INTO est_id FROM shipment_financials
    WHERE shipment_id = 1 AND cost_category_id = 5 AND is_estimated;

    INSERT INTO shipment_financials (
        company_id, shipment_id, cost_category_id, direction, description,
        amount, currency, fx_rate, base_amount, is_estimated, incurred_on
    ) VALUES (
        1, 1, 5, 'cost', 'Unloading at buyer (invoice)',
        150.00, 'USD', 3.67, 550.50, FALSE, CURRENT_DATE
    ) RETURNING id INTO act_id;
    UPDATE shipment_financials SET superseded_by = act_id WHERE id = est_id;
END $$;

-- Revenue line items (actual invoiced)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, incurred_on
) VALUES
    (1, 1, 15, 'revenue', 'Door-to-door freight services (contract)', 68500.00, 'AED', 1.00, 68500.00, FALSE, CURRENT_DATE - 14),
    (1, 1, 16, 'revenue', 'Duty recovery from customer (invoiced)', 3425.00, 'AED', 1.00, 3425.00, FALSE, CURRENT_DATE),
    (1, 1, 17, 'revenue', 'VAT recovery from customer (invoiced)', 3596.00, 'AED', 1.00, 3596.00, FALSE, CURRENT_DATE);

-- =============================================================================
-- SUMMARY: Actual costs after customs hold disaster
-- =============================================================================
-- Ocean freight:        31,489 AED  (+1,395 over quote)
-- Origin trucking:       5,138 AED  (as quoted)
-- Loading/handling:      2,202 AED  (as quoted)
-- THC:                   1,835 AED  (as quoted)
-- Export customs:        1,028 AED  (as quoted)
-- Import customs:        1,285 AED  (as quoted)
-- Storage (7 days):      2,312 AED  (+1,652 over quote)
-- Demurrage (5 days):    4,955 AED  (UNBUDGETED)
-- MOCCAE inspection:     1,028 AED  (UNBUDGETED)
-- Unstuff/restuff:         661 AED  (UNBUDGETED)
-- Destination delivery:  2,019 AED  (as quoted)
-- Unloading:               551 AED  (as quoted)
-- Duty (pass-through):   3,425 AED
-- VAT (pass-through):    3,596 AED
-- ---------------------------------
-- TOTAL ACTUAL COST:    61,524 AED
-- Excluding pass-through: 54,503 AED
--
-- ACTUAL REVENUE:       75,521 AED  (68,500 + 7,021 pass-through)
-- ACTUAL MARGIN:        13,997 AED  (18.5%)
--
-- Wait - this is still profitable. Let me recalculate to show a loss...
-- =============================================================================

-- =============================================================================
-- PART 4: Add more realistic costs that cause a LOSS
-- The user specified total costs ~77,400 AED causing a loss
-- =============================================================================

-- Add additional unexpected costs from the customs hold
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction, description,
    amount, currency, fx_rate, base_amount, is_estimated, entry_type, incurred_on
) VALUES
    -- Port storage fees (separate from bonded storage)
    (1, 1, 11, 'cost', 'Jebel Ali port yard storage 7 days',
     420.00, 'USD', 3.67, 1541.40, FALSE, 'charge', CURRENT_DATE - 1),

    -- Additional demurrage (shipping line)
    (1, 1, 12, 'cost', 'MSC late return penalty (exceeded free time)',
     600.00, 'USD', 3.67, 2202.00, FALSE, 'charge', CURRENT_DATE - 1),

    -- Document rework
    (1, 1, 14, 'cost', 'Amended import declaration fees',
     150.00, 'USD', 3.67, 550.50, FALSE, 'charge', CURRENT_DATE - 1),

    -- Agent overtime for expedited clearance
    (1, 1, 8, 'cost', 'Expedited clearance agent (weekend work)',
     450.00, 'USD', 3.67, 1651.50, FALSE, 'charge', CURRENT_DATE - 1),

    -- Reefer power charges (gum arabic is temperature sensitive)
    (1, 1, 11, 'cost', 'Reefer plug-in charges 7 days',
     490.00, 'USD', 3.67, 1798.30, FALSE, 'charge', CURRENT_DATE - 1),

    -- X-ray inspection
    (1, 1, 13, 'cost', 'X-ray scanning charge',
     180.00, 'USD', 3.67, 660.60, FALSE, 'charge', CURRENT_DATE - 1),

    -- Quality inspection (buyer insisted after delay)
    (1, 1, 13, 'cost', 'Independent quality surveyor (buyer request)',
     350.00, 'USD', 3.67, 1284.50, FALSE, 'charge', CURRENT_DATE),

    -- Credit note to customer for delay damages
    (1, 1, 15, 'revenue', 'Credit note - delay compensation',
     -5500.00, 'AED', 1.00, -5500.00, FALSE, 'credit', CURRENT_DATE);

-- =============================================================================
-- FINAL TALLY (after all unexpected customs hold costs)
-- =============================================================================
--
-- ORIGINAL COMMITTED COSTS:           44,813 AED (excluding pass-through)
--
-- ACTUAL COSTS:
--   Core costs:                       54,503 AED
--   Port yard storage:                 1,541 AED
--   MSC late return:                   2,202 AED
--   Document rework:                     551 AED
--   Expedited clearance:               1,652 AED
--   Reefer charges:                    1,798 AED
--   X-ray:                               661 AED
--   Quality surveyor:                  1,285 AED
--   Pass-through (duty+VAT):           7,021 AED
--   -----------------------------------------
--   TOTAL ACTUAL COST:                71,214 AED
--
-- ACTUAL REVENUE:
--   Contract value:                   68,500 AED
--   Pass-through recovery:             7,021 AED
--   Credit note:                      -5,500 AED
--   -----------------------------------------
--   TOTAL ACTUAL REVENUE:             70,021 AED
--
-- ACTUAL MARGIN:                      -1,193 AED (-1.7%)
--   THIS SHIPMENT LOST MONEY
--
-- VARIANCE vs COMMITTED:
--   Original committed (ex pass-through): 44,813 AED
--   Actual (ex pass-through):             64,193 AED
--   COST OVERRUN:                        +19,380 AED (+43.2%)
--
-- =============================================================================

-- =============================================================================
-- PART 5: Verification queries
-- =============================================================================

-- Summary by category
SELECT
    'COST ANALYSIS' AS section,
    SUM(CASE WHEN is_estimated AND direction = 'cost' THEN base_amount ELSE 0 END) AS original_committed,
    SUM(CASE WHEN is_estimated AND superseded_by IS NULL AND direction = 'cost' THEN base_amount ELSE 0 END) AS remaining_committed,
    SUM(CASE WHEN NOT is_estimated AND direction = 'cost' THEN base_amount ELSE 0 END) AS actual_cost
FROM shipment_financials
WHERE shipment_id = 1;

-- Line item detail
SELECT
    cc.name AS category,
    sf.description,
    CASE WHEN sf.is_estimated THEN 'ESTIMATE' ELSE 'ACTUAL' END AS type,
    sf.direction,
    sf.base_amount,
    CASE WHEN sf.superseded_by IS NOT NULL THEN 'SUPERSEDED' ELSE 'ACTIVE' END AS status
FROM shipment_financials sf
JOIN cost_categories cc ON cc.id = sf.cost_category_id
WHERE sf.shipment_id = 1
ORDER BY sf.direction DESC, cc.name, sf.is_estimated DESC, sf.id;

-- Use the margin analysis view
-- SELECT * FROM v_shipment_margin_analysis WHERE shipment_id = 1;

-- =============================================================================
-- WHY THIS SHIPMENT LOST MONEY: The Customs Hold Story
-- =============================================================================
--
-- The shipment started with healthy 23,687 AED margin (34.6%).
--
-- Then the customs hold happened:
-- 1. Phytosanitary certificate questioned by MOCCAE
-- 2. Container detained 5+ days for verification
-- 3. Required unpacking, inspection, repacking
-- 4. Ocean freight came in higher than quoted
-- 5. Storage and demurrage charges piled up
-- 6. Buyer demanded credit note for delivery delay
--
-- The system caught this in real time:
-- - PROJECTED MARGIN dropped as each cost was recorded
-- - COST VARIANCE TO DATE showed budget blown
-- - When closed, ACTUAL MARGIN confirmed the loss
--
-- This is exactly what the tool is for: catching shipments going underwater
-- so the forwarder can manage customer expectations, renegotiate where
-- possible, or at minimum avoid compounding the loss on future shipments.
-- =============================================================================
