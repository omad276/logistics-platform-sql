-- =============================================================================
-- 03_demo_customs_hold.sql
-- Logistics Operations & Task Dispatch Platform - Demo Scenario
--
-- A nine-act walkthrough: customs hold at Jebel Ali, resolution, delivery,
-- and financial closure. Run after 01_schema.sql and 02_seed.sql.
-- =============================================================================

-- Session variables required for RLS and audit triggers
SET app.company_id = '1';
SET app.current_user_id = '1';

-- =============================================================================
-- ACT 1: WHERE IS THE SHIPMENT AND WHY HAS IT STOPPED?
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 1: WHERE IS THE SHIPMENT AND WHY HAS IT STOPPED?                    ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Current shipment status
SELECT
    s.tracking_no,
    s.container_no,
    s.status,
    c.contract_no,
    seller.trade_name AS seller,
    buyer.trade_name AS buyer
FROM shipments s
JOIN contracts c ON c.id = s.contract_id
JOIN parties seller ON seller.id = c.seller_id
JOIN parties buyer ON buyer.id = c.buyer_id
WHERE s.id = 1;

-- Latest tracking events
SELECT
    event_code,
    occurred_at,
    title,
    description
FROM tracking_events
WHERE shipment_id = 1
ORDER BY occurred_at DESC
LIMIT 5;

-- The incident blocking progress
SELECT
    incident_no,
    it.name AS incident_type,
    i.severity,
    i.description AS title,
    i.status
FROM incidents i
JOIN incident_types it ON it.id = i.incident_type_id
WHERE i.shipment_id = 1
  AND i.status = 'open';

-- The customs declaration
SELECT
    declaration_no,
    direction,
    status,
    customs_office,
    declared_value,
    duty_amount,
    vat_amount,
    hold_reason
FROM customs_declarations
WHERE shipment_id = 1;

-- =============================================================================
-- ACT 2: THE DEPENDENCY GRAPH - WHAT IS BLOCKED?
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 2: THE DEPENDENCY GRAPH - WHAT IS BLOCKED?                          ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- All tasks and their current status
SELECT
    ss.code AS stage,
    t.code AS task,
    t.name,
    t.status,
    t.priority
FROM tasks t
JOIN shipment_stages ss ON ss.id = t.stage_id
WHERE t.shipment_id = 1
ORDER BY ss.sequence_no, t.code;

-- What is ready to work on? (tasks with no unfinished dependencies)
\echo ''
\echo 'Ready tasks (unblocked):'
SELECT
    t.task_no,
    t.name AS task_name,
    ss.name AS stage_name,
    t.priority,
    CASE WHEN t.scheduled_start_at < now() THEN 'YES' ELSE 'NO' END AS is_overdue
FROM tasks t
JOIN shipment_stages ss ON ss.id = t.stage_id
WHERE t.shipment_id = 1
  AND t.status NOT IN ('completed', 'closed', 'cancelled')
  AND NOT EXISTS (
      SELECT 1 FROM task_dependencies td
      JOIN tasks dep ON dep.id = td.depends_on_task_id
      WHERE td.task_id = t.id
        AND dep.status NOT IN ('completed', 'closed')
  );

-- What is blocked and by what?
\echo ''
\echo 'Blocked tasks and their blockers:'
SELECT
    t.code AS blocked_task,
    t.name AS blocked_name,
    t.status,
    p.code AS blocked_by,
    p.status AS blocker_status
FROM tasks t
JOIN task_dependencies td ON td.task_id = t.id
JOIN tasks p ON p.id = td.depends_on_task_id
WHERE t.shipment_id = 1
  AND t.status NOT IN ('completed', 'closed')
  AND p.status NOT IN ('completed', 'closed')
ORDER BY t.code;

-- =============================================================================
-- ACT 3: WHAT IS THE HOLD COSTING?
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 3: WHAT IS THE HOLD COSTING?                                        ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Current cost position
SELECT
    SUM(CASE WHEN direction = 'revenue' THEN base_amount ELSE 0 END) AS total_revenue,
    SUM(CASE WHEN direction = 'cost' AND is_estimated THEN base_amount ELSE 0 END) AS committed_cost,
    SUM(CASE WHEN direction = 'cost' AND NOT is_estimated THEN base_amount ELSE 0 END) AS actual_cost,
    SUM(CASE WHEN direction = 'revenue' THEN base_amount ELSE 0 END) -
        SUM(CASE WHEN direction = 'cost' THEN base_amount ELSE 0 END) AS current_margin
FROM shipment_financials
WHERE shipment_id = 1;

-- Cost breakdown by category
\echo ''
\echo 'Cost breakdown:'
SELECT
    cc.name AS category,
    sf.description,
    CASE WHEN sf.is_estimated THEN 'ESTIMATE' ELSE 'ACTUAL' END AS type,
    sf.base_amount AS amount_aed
FROM shipment_financials sf
JOIN cost_categories cc ON cc.id = sf.cost_category_id
WHERE sf.shipment_id = 1 AND sf.direction = 'cost'
ORDER BY cc.name, sf.is_estimated DESC;

-- =============================================================================
-- ACT 4: DEMURRAGE ACCRUING
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 4: DEMURRAGE ACCRUING                                               ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Add demurrage cost (day 1 of hold)
INSERT INTO shipment_financials (
    company_id, shipment_id, cost_category_id, direction,
    description, amount, currency, fx_rate, base_amount,
    is_estimated, incurred_on
)
VALUES (
    1, 1, 12, 'cost',
    'Container detention - day 1 of customs hold',
    150.00, 'USD', 3.67, 550.50,
    FALSE, CURRENT_DATE
);

\echo 'Demurrage added. Updated cost position:'
SELECT
    SUM(CASE WHEN direction = 'revenue' THEN base_amount ELSE 0 END) AS total_revenue,
    SUM(CASE WHEN direction = 'cost' THEN base_amount ELSE 0 END) AS total_cost,
    SUM(CASE WHEN direction = 'revenue' THEN base_amount ELSE 0 END) -
        SUM(CASE WHEN direction = 'cost' THEN base_amount ELSE 0 END) AS current_margin
FROM shipment_financials
WHERE shipment_id = 1;

-- =============================================================================
-- ACT 5: RESOLUTION - CUSTOMS RELEASE
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 5: RESOLUTION - CERTIFICATE VERIFIED, DECLARATION CLEARED           ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Clear the customs declaration
UPDATE customs_declarations
SET status = 'cleared',
    cleared_at = NOW(),
    hold_reason = NULL
WHERE id = 1;

-- Close the incident
UPDATE incidents
SET status = 'resolved',
    resolved_at = NOW(),
    resolved_by = 3,
    action_taken = 'Phytosanitary certificate verified by MOCCAE. Certificate number PPD-SD-2024-08721 confirmed authentic. Declaration released.'
WHERE id = 1;

-- Release the waiting task
UPDATE tasks
SET status = 'in_progress',
    hold_reason = NULL,
    assigned_to_user_id = 3
WHERE id = 11;

-- Add tracking event
INSERT INTO tracking_events (shipment_id, event_code, title, location_id, occurred_at, description)
VALUES (
    1, 'CUSTOMS_CLEARED', 'Customs Cleared',
    3, NOW(), 'Import declaration cleared - MOCCAE verification complete'
);

\echo 'Customs cleared. Ready tasks now:'
SELECT
    t.task_no,
    t.name AS task_name,
    ss.name AS stage_name,
    t.priority
FROM tasks t
JOIN shipment_stages ss ON ss.id = t.stage_id
WHERE t.shipment_id = 1
  AND t.status NOT IN ('completed', 'closed', 'cancelled')
  AND NOT EXISTS (
      SELECT 1 FROM task_dependencies td
      JOIN tasks dep ON dep.id = td.depends_on_task_id
      WHERE td.task_id = t.id
        AND dep.status NOT IN ('completed', 'closed')
  );

-- =============================================================================
-- ACT 6: REMAINING WORKFLOW - WAREHOUSE TO DELIVERY
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 6: REMAINING WORKFLOW - WAREHOUSE TO DELIVERY                       ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Complete duty settlement
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'SETTLE_DUTY';

-- Complete import release
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'OBTAIN_IMPORT_REL';

-- Add duty and VAT costs (actuals matching estimates)
INSERT INTO shipment_financials (company_id, shipment_id, cost_category_id, direction, description, amount, currency, fx_rate, base_amount, is_estimated, incurred_on)
VALUES
    (1, 1, 9, 'cost', 'Import duty 0.5%', 342.50, 'AED', 1.0, 342.50, FALSE, CURRENT_DATE),
    (1, 1, 10, 'cost', 'Import VAT 5%', 3425.00, 'AED', 1.0, 3425.00, FALSE, CURRENT_DATE);

-- Update import customs stage to completed
UPDATE shipment_stages SET status = 'completed', actual_end_at = NOW() WHERE id = 5;

-- Warehouse operations
UPDATE shipment_stages SET status = 'active', actual_start_at = NOW() WHERE id = 6;

UPDATE tasks SET status = 'in_progress', started_at = NOW(), assigned_to_user_id = 4
WHERE shipment_id = 1 AND code = 'RECEIVE_INSPECT';

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'RECEIVE_INSPECT';

-- Record inventory movement into warehouse
INSERT INTO inventory_movements (
    company_id, warehouse_id, shipment_id, product_id,
    movement_type, to_bin_id, quantity, uom, batch_no,
    reference_no, moved_by, moved_at
)
VALUES (
    1, 1, 1, 1,
    'receipt', 1, 520,
    'BAG', 'LOT-2024-SESAME-001',
    'GRN-2024-00412', 4, NOW()
);

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'PUT_AWAY';

-- Add warehousing cost (actual - extended due to hold)
INSERT INTO shipment_financials (company_id, shipment_id, cost_category_id, direction, description, amount, currency, fx_rate, base_amount, is_estimated, incurred_on)
VALUES (1, 1, 11, 'cost', 'Bonded storage - 3 days extended due to customs hold', 270.00, 'USD', 3.67, 990.90, FALSE, CURRENT_DATE);

UPDATE shipment_stages SET status = 'completed', actual_end_at = NOW() WHERE id = 6;

-- Final delivery
UPDATE shipment_stages SET status = 'active', actual_start_at = NOW() WHERE id = 7;

UPDATE tasks SET status = 'in_progress', started_at = NOW(), assigned_to_user_id = 5
WHERE shipment_id = 1 AND code = 'FINAL_LEG';

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'FINAL_LEG';

-- Add final delivery cost
INSERT INTO shipment_financials (company_id, shipment_id, cost_category_id, direction, description, amount, currency, fx_rate, base_amount, is_estimated, incurred_on)
VALUES (1, 1, 3, 'cost', 'Final leg - SAIF Zone to buyer premises', 350.00, 'USD', 3.67, 1284.50, FALSE, CURRENT_DATE);

-- Unloading - discover 4 bags water damaged
UPDATE tasks SET status = 'in_progress', started_at = NOW()
WHERE shipment_id = 1 AND code = 'UNLOAD_BUYER';

-- Record damage
UPDATE shipment_cargo_lines
SET delivered_quantity = 516,
    damaged_quantity = 4,
    condition = 'partially_damaged'
WHERE id = 1;

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'UNLOAD_BUYER';

-- Capture POD
UPDATE tasks SET status = 'in_progress', started_at = NOW()
WHERE shipment_id = 1 AND code = 'CAPTURE_POD';

-- Record delivery
INSERT INTO deliveries (
    company_id, shipment_id, delivery_no, location_id, delivered_at,
    driver_id, vehicle_id, receiver_name, receiver_phone,
    delivered_quantity, accepted_in_full, discrepancy_note
)
VALUES (
    1, 1, 'DEL-2024-00412', 5, NOW(),
    1, 1, 'Mohammed Al-Rashid', '+97165551234',
    520, FALSE, '4 bags water damaged from rain exposure during customs hold. Buyer accepted 516, claims for 4.'
);

-- Dispatch the stock
INSERT INTO inventory_movements (
    company_id, warehouse_id, shipment_id, product_id,
    movement_type, from_bin_id, quantity, uom, batch_no,
    reference_no, moved_by, moved_at
)
VALUES (
    1, 1, 1, 1,
    'dispatch', 1, -520,
    'BAG', 'LOT-2024-SESAME-001',
    'DEL-2024-00412', 5, NOW()
);

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'CAPTURE_POD';

UPDATE shipment_stages SET status = 'completed', actual_end_at = NOW() WHERE id = 7;

-- Update shipment status to delivered
UPDATE shipments
SET status = 'delivered',
    actual_delivery_at = NOW()
WHERE id = 1;

-- Add tracking event
INSERT INTO tracking_events (shipment_id, event_code, title, location_id, occurred_at, description)
VALUES (1, 'DELIVERED', 'Delivered', 5, NOW(), 'Delivered to Emirates Food Industries. 516 of 520 bags accepted, 4 damaged.');

\echo 'Delivery complete. Cargo reconciliation:'
SELECT
    p.name AS product,
    scl.planned_quantity AS planned,
    scl.loaded_quantity AS loaded,
    scl.delivered_quantity AS delivered,
    scl.damaged_quantity AS damaged,
    scl.condition
FROM shipment_cargo_lines scl
JOIN products p ON p.id = scl.product_id
WHERE scl.shipment_id = 1;

-- =============================================================================
-- ACT 7: INVOICING AND PAYMENT
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 7: INVOICING AND PAYMENT                                            ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Create invoice to customer
INSERT INTO invoices (
    id, company_id, invoice_no, direction, status,
    party_id, contract_id, shipment_id,
    issue_date, due_date, currency,
    subtotal, tax_amount, total_amount, paid_amount,
    notes, created_by
)
OVERRIDING SYSTEM VALUE
VALUES (
    1, 1, 'INV-2024-00412', 'receivable', 'issued',
    2, 1, 1,
    CURRENT_DATE, CURRENT_DATE + 30, 'AED',
    68500.00, 0, 68500.00, 0,
    'Credit for 4 damaged bags: -1315 AED (4 bags × 328.75 AED)', 1
);

SELECT setval('invoices_id_seq', 1);

-- Create invoice lines
INSERT INTO invoice_lines (invoice_id, line_no, cost_category_id, description, quantity, unit_price, line_total, entry_type) VALUES
    (1, 1, 15, 'Door-to-door freight services per contract GFL-2024-00147', 1, 68500.00, 68500.00, 'charge'),
    (1, 2, 15, 'Credit: 4 damaged bags (water damage during customs hold)', 4, -328.75, -1315.00, 'credit');

-- Update invoice total after credit
UPDATE invoices SET subtotal = 67185.00, total_amount = 67185.00 WHERE id = 1;

\echo 'Invoice issued:'
SELECT invoice_no, total_amount, status, due_date FROM invoices WHERE id = 1;

-- Receive payment
INSERT INTO payments (id, company_id, invoice_id, payment_no, paid_on, amount, currency, method, reference_no, recorded_by)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, 1, 'PAY-2024-00298', CURRENT_DATE, 67185.00, 'AED', 'bank_transfer', 'ADCB-REF-2024-87654', 1);

SELECT setval('payments_id_seq', 1);

\echo 'Payment received. Invoice status:'
SELECT invoice_no, total_amount, paid_amount, status FROM invoices WHERE id = 1;

-- =============================================================================
-- ACT 8: AUDIT TRAIL - EVERY STATUS CHANGE LOGGED
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 8: AUDIT TRAIL - EVERY STATUS CHANGE LOGGED                         ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

SELECT
    t.task_no,
    t.code AS task,
    h.from_status,
    h.to_status,
    h.changed_at,
    u.full_name AS changed_by
FROM task_status_history h
JOIN tasks t ON t.id = h.task_id
LEFT JOIN users u ON u.id = h.changed_by
WHERE t.shipment_id = 1
ORDER BY h.changed_at
LIMIT 25;

\echo ''
\echo 'Note: Every status change above was recorded automatically by database trigger.'
\echo 'No application code inserted a single row into task_status_history.'

-- =============================================================================
-- ACT 9: FINAL PROFITABILITY AND RECONCILIATION
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 9: FINAL PROFITABILITY AND RECONCILIATION                           ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Complete closure tasks
UPDATE shipment_stages SET status = 'active', actual_start_at = NOW() WHERE id = 8;

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'RECONCILE_COSTS';

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 1 AND code = 'CLOSE_FILE';

UPDATE shipment_stages SET status = 'completed', actual_end_at = NOW() WHERE id = 8;

-- Close shipment
UPDATE shipments SET status = 'closed', closed_at = NOW() WHERE id = 1;

-- Final profitability
\echo 'Final cost position:'
SELECT
    SUM(CASE WHEN direction = 'revenue' AND NOT is_estimated THEN base_amount ELSE 0 END) AS actual_revenue,
    SUM(CASE WHEN direction = 'cost' AND NOT is_estimated THEN base_amount ELSE 0 END) AS actual_cost,
    SUM(CASE WHEN direction = 'cost' AND is_estimated THEN base_amount ELSE 0 END) AS original_committed,
    SUM(CASE WHEN direction = 'revenue' AND NOT is_estimated THEN base_amount ELSE 0 END) -
        SUM(CASE WHEN direction = 'cost' AND NOT is_estimated THEN base_amount ELSE 0 END) AS actual_margin
FROM shipment_financials
WHERE shipment_id = 1;

-- Cost breakdown
\echo ''
\echo 'Cost breakdown by category:'
SELECT
    cc.name AS category,
    SUM(sf.base_amount) AS amount_aed
FROM shipment_financials sf
JOIN cost_categories cc ON cc.id = sf.cost_category_id
WHERE sf.shipment_id = 1 AND sf.direction = 'cost' AND NOT sf.is_estimated
GROUP BY cc.name
ORDER BY SUM(sf.base_amount) DESC;

-- Tracking timeline
\echo ''
\echo 'Shipment timeline:'
SELECT event_code, title, occurred_at, description
FROM tracking_events
WHERE shipment_id = 1
ORDER BY occurred_at;

-- =============================================================================
-- CONSTRAINT DEMONSTRATIONS - THINGS THE DATABASE REFUSES
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  CONSTRAINT DEMONSTRATIONS - THINGS THE DATABASE REFUSES                 ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Test 1: Cannot set task to waiting without a reason
\echo 'Test 1: Cannot set task to waiting without hold_reason'
DO $$
DECLARE
    v_stage_id BIGINT;
BEGIN
    SELECT id INTO v_stage_id FROM shipment_stages WHERE shipment_id = 1 LIMIT 1;

    -- Create a test task
    INSERT INTO tasks (company_id, shipment_id, stage_id, task_no, code, name, status)
    VALUES (1, 1, v_stage_id, 'TSK-TEST-001', 'TEST_TASK', 'Test task', 'created');

    -- Try to set waiting without reason
    UPDATE tasks SET status = 'waiting' WHERE task_no = 'TSK-TEST-001';
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint tasks_hold_reason prevented waiting status without reason';
        DELETE FROM tasks WHERE task_no = 'TSK-TEST-001';
END $$;

-- Test 2: Cannot deliver more than loaded
\echo ''
\echo 'Test 2: Cannot deliver more than was loaded'
DO $$
BEGIN
    UPDATE shipment_cargo_lines
    SET delivered_quantity = 600  -- More than the 520 loaded
    WHERE id = 1;
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint shipment_cargo_quantities prevented over-delivery';
END $$;

-- Test 3: Cannot close undelivered shipment
\echo ''
\echo 'Test 3: Cannot close undelivered shipment'
DO $$
DECLARE
    v_origin_id BIGINT;
    v_dest_id BIGINT;
BEGIN
    SELECT origin_location_id, destination_location_id INTO v_origin_id, v_dest_id FROM shipments WHERE id = 1;

    -- Create test shipment
    INSERT INTO shipments (company_id, contract_id, shipment_no, tracking_no, status, origin_location_id, destination_location_id)
    VALUES (1, 1, 'TEST-SHP-001', 'TEST-TRK-001', 'in_progress', v_origin_id, v_dest_id);

    -- Try to close without delivery
    UPDATE shipments SET status = 'closed', closed_at = NOW() WHERE shipment_no = 'TEST-SHP-001';
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint shipments_closure_rule prevented closing undelivered shipment';
        DELETE FROM shipments WHERE shipment_no = 'TEST-SHP-001';
END $$;

-- Test 4: Cannot over-pay invoice
\echo ''
\echo 'Test 4: Cannot over-pay invoice'
DO $$
BEGIN
    -- Try to pay more than invoice total
    INSERT INTO payments (company_id, invoice_id, payment_no, paid_on, amount, currency, method)
    VALUES (
        1, 1, 'PAY-TEST-001', CURRENT_DATE,
        100000.00,  -- Way more than invoice total of 67185
        'AED', 'cash'
    );
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint invoices_totals prevented over-payment';
END $$;

-- Test 5: Handling discrepancy requires remark
\echo ''
\echo 'Test 5: Handling discrepancy requires remark'
DO $$
BEGIN
    INSERT INTO handling_operations (
        company_id, shipment_id, operation_no, handling_type, location_id,
        total_quantity, damaged_quantity, missing_quantity
    )
    VALUES (
        1, 1, 'HOP-TEST-001', 'loading', 1,
        100, 5, 0  -- Discrepancy (5 damaged) without remarks
    );
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint handling_discrepancy_needs_remark prevented unexplained shortage';
END $$;

-- =============================================================================
-- DEMO COMPLETE
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  DEMO COMPLETE                                                           ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''
\echo 'The shipment has been completed end-to-end:'
\echo '  - Contract GFL-2024-00147 approved'
\echo '  - 19 tasks generated from workflow template'
\echo '  - Customs hold incident raised and resolved'
\echo '  - Demurrage accrued during hold'
\echo '  - 516 of 520 bags delivered (4 water damaged)'
\echo '  - Invoice issued with damage credit'
\echo '  - Payment received in full'
\echo '  - Audit trail complete (no manual inserts)'
\echo ''
\echo 'Explore with:'
\echo '  SELECT * FROM tasks WHERE shipment_id = 1 ORDER BY id;'
\echo '  SELECT * FROM shipment_financials WHERE shipment_id = 1;'
\echo '  SELECT * FROM tracking_events WHERE shipment_id = 1 ORDER BY occurred_at;'
\echo '  SELECT * FROM inventory_movements WHERE shipment_id = 1;'
\echo ''
