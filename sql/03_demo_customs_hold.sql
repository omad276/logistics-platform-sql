-- =============================================================================
-- 03_demo_customs_hold.sql
-- Logistics Operations & Task Dispatch Platform - Demo Scenario
--
-- A nine-act walkthrough: customs hold at Jebel Ali, resolution, delivery,
-- and financial closure. Run after 01_schema.sql and 02_seed.sql.
-- =============================================================================

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
    s.tracking_number,
    s.container_number,
    s.status,
    c.contract_number,
    seller.trade_name AS seller,
    buyer.trade_name AS buyer
FROM shipments s
JOIN contracts c ON c.id = s.contract_id
JOIN parties seller ON seller.id = c.seller_party_id
JOIN parties buyer ON buyer.id = c.buyer_party_id
WHERE s.id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Latest tracking events
SELECT
    event_type,
    event_timestamp,
    location_name,
    description
FROM tracking_events
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
ORDER BY event_timestamp DESC
LIMIT 5;

-- The incident blocking progress
SELECT
    incident_number,
    incident_type,
    severity,
    title,
    status,
    reported_at
FROM incidents
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND status = 'open';

-- The customs declaration
SELECT
    declaration_number,
    declaration_type,
    status,
    port_code,
    declared_value,
    duty_amount,
    vat_amount,
    hold_reason
FROM customs_declarations
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

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
JOIN shipment_stages ss ON ss.id = t.shipment_stage_id
WHERE t.shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
ORDER BY ss.sequence_order, t.code;

-- What is ready to work on? (Uses v_ready_tasks view)
\echo ''
\echo 'Ready tasks (unblocked):'
SELECT
    task_no,
    task_name,
    stage_name,
    priority,
    is_overdue
FROM v_ready_tasks
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

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
WHERE t.shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
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

-- Current profitability
SELECT
    tracking_no,
    total_revenue,
    total_cost,
    gross_profit,
    margin_percent
FROM v_shipment_profitability
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Cost breakdown
SELECT
    cost_type,
    description,
    amount,
    currency,
    base_currency_amount AS amount_aed,
    status
FROM cost_records
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
ORDER BY incurred_date;

-- =============================================================================
-- ACT 4: DEMURRAGE ACCRUING
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 4: DEMURRAGE ACCRUING                                               ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Add demurrage cost (day 1 of hold)
INSERT INTO cost_records (id, shipment_id, company_id, cost_type, description, amount, currency, exchange_rate_to_base, base_currency_amount, incurred_date, status)
VALUES (
    'cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'demurrage',
    'Container detention - day 1 of customs hold',
    150.00,
    'USD',
    3.67,
    550.50,
    NOW(),
    'accrued'
);

-- Update financials
UPDATE shipment_financials
SET total_cost = (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'),
    gross_profit = total_revenue - (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01')
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

\echo 'Demurrage added. Updated profitability:'
SELECT
    tracking_no,
    total_revenue,
    total_cost,
    gross_profit,
    margin_percent
FROM v_shipment_profitability
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

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
    cleared_date = NOW(),
    hold_reason = NULL
WHERE id = 'cd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Close the incident
UPDATE incidents
SET status = 'resolved',
    resolved_at = NOW(),
    resolved_by_user_id = 'u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03',
    resolution_action = 'Phytosanitary certificate verified by MOCCAE. Certificate number PPD-SD-2024-08721 confirmed authentic. Declaration released.'
WHERE id = 'in0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Release the waiting task
UPDATE tasks
SET status = 'in_progress',
    hold_reason = NULL
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'SETTLE_DUTY';

-- Add tracking event
INSERT INTO tracking_events (id, shipment_id, company_id, event_type, event_timestamp, location_name, location_country_code, description)
VALUES (
    'te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a06',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'customs_cleared',
    NOW(),
    'Jebel Ali',
    'AE',
    'Import declaration cleared - MOCCAE verification complete'
);

\echo 'Customs cleared. Ready tasks now:'
SELECT
    task_no,
    task_name,
    stage_name,
    priority
FROM v_ready_tasks
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

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
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'SETTLE_DUTY';

-- Complete import release
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'OBTAIN_IMPORT_REL';

-- Add duty and VAT costs
INSERT INTO cost_records (id, shipment_id, company_id, cost_type, description, amount, currency, exchange_rate_to_base, base_currency_amount, incurred_date, status)
VALUES
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a06', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'customs_duty', 'Import duty 0.5%', 342.50, 'AED', 1.0, 342.50, NOW(), 'paid'),
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a07', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'vat', 'Import VAT 5%', 3425.00, 'AED', 1.0, 3425.00, NOW(), 'paid');

-- Warehouse operations
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'RECEIVE_INSPECT';

-- Record inventory movement into warehouse
INSERT INTO inventory_movements (id, shipment_id, warehouse_id, storage_bin_id, company_id, movement_type, quantity, unit_of_measure, reference_number, moved_at)
VALUES (
    'im0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sb0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'receipt',
    520,  -- All 520 bags
    'bags',
    'GRN-2024-00412',
    NOW()
);

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'PUT_AWAY';

-- Add warehousing cost
INSERT INTO cost_records (id, shipment_id, company_id, cost_type, description, amount, currency, exchange_rate_to_base, base_currency_amount, incurred_date, status)
VALUES (
    'cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a08',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'warehousing',
    'SAIF Zone bonded storage - 2 days',
    180.00,
    'USD',
    3.67,
    660.60,
    NOW(),
    'paid'
);

\echo 'Warehouse operations complete. Stock on hand:'
SELECT * FROM v_stock_on_hand
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Final delivery
UPDATE tasks SET status = 'in_progress', started_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'FINAL_LEG';

-- Create final delivery transport order
INSERT INTO transport_orders (id, shipment_id, company_id, order_number, transport_mode, origin_address, destination_address, vehicle_id, driver_id, status, scheduled_departure)
VALUES (
    'to0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'TO-2024-00293',
    'road',
    'SAIF Zone Warehouse Block C',
    'SAIF Zone Plot 34, Emirates Food Industries',
    've0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'dr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'in_progress',
    NOW()
);

-- Dispatch inventory
INSERT INTO inventory_movements (id, shipment_id, warehouse_id, storage_bin_id, company_id, movement_type, quantity, unit_of_measure, reference_number, moved_at)
VALUES (
    'im0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sb0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'dispatch',
    -520,  -- Negative = out
    'bags',
    'DN-2024-00398',
    NOW()
);

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'FINAL_LEG';

-- Unloading with damage discovery
UPDATE tasks SET status = 'in_progress', started_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'UNLOAD_BUYER';

-- Create handling operation with discrepancy
INSERT INTO handling_operations (id, shipment_id, company_id, operation_type, location_type, location_name, planned_start, actual_start, actual_end, quantity_expected, quantity_handled, discrepancy_quantity, discrepancy_remark, status)
VALUES (
    'ho0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'unloading',
    'customer',
    'Emirates Food Industries - SAIF Zone',
    NOW(),
    NOW(),
    NOW() + INTERVAL '2 hours',
    520,
    516,  -- 4 bags water damaged
    -4,
    'Four bags (200 kg) water damaged during ocean transit. Buyer rejected. Discrepancy note DN-2024-00398-A issued. Insurance claim to follow.',
    'completed'
);

UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'UNLOAD_BUYER';

-- Update cargo line with actual delivery
UPDATE shipment_cargo_lines
SET quantity_delivered = 516,
    weight_delivered_kg = 25800.0
WHERE id = 'scl0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- =============================================================================
-- ACT 7: PROOF OF DELIVERY AND CLOSURE
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 7: PROOF OF DELIVERY, PARTIAL ACCEPTANCE, CLOSURE                   ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Capture POD
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'CAPTURE_POD';

-- Create delivery record
INSERT INTO deliveries (id, shipment_id, company_id, delivery_number, delivery_date, received_by_name, received_by_title, quantity_delivered, unit_of_measure, has_discrepancy, discrepancy_note, signature_captured, photo_captured, status)
VALUES (
    'de0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'POD-2024-00147',
    NOW(),
    'Mohammed Al-Sayed',
    'Warehouse Manager',
    516,
    'bags',
    true,
    'Received 516 bags in good condition. 4 bags rejected due to water damage. Shortfall claim lodged.',
    true,
    true,
    'completed'
);

-- Add tracking event
INSERT INTO tracking_events (id, shipment_id, company_id, event_type, event_timestamp, location_name, location_country_code, description)
VALUES (
    'te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a07',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'delivered',
    NOW(),
    'SAIF Zone, Sharjah',
    'AE',
    'Delivered to Emirates Food Industries - 516/520 bags (4 rejected water damage)'
);

-- Update shipment status
UPDATE shipments
SET status = 'delivered',
    actual_arrival = NOW()
WHERE id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Complete transport order
UPDATE transport_orders
SET status = 'completed',
    actual_departure = NOW() - INTERVAL '3 hours',
    actual_arrival = NOW()
WHERE id = 'to0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03';

-- Add final delivery cost
INSERT INTO cost_records (id, shipment_id, company_id, cost_type, description, amount, currency, exchange_rate_to_base, base_currency_amount, incurred_date, status)
VALUES (
    'cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a09',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'final_delivery',
    'Delivery SAIF Zone warehouse to buyer',
    350.00,
    'USD',
    3.67,
    1284.50,
    NOW(),
    'paid'
);

-- Reconcile costs
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'RECONCILE_COSTS';

-- Update financials
UPDATE shipment_financials
SET total_cost = (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'),
    gross_profit = total_revenue - (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01')
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Close file
UPDATE tasks SET status = 'completed', completed_at = NOW()
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND code = 'CLOSE_FILE';

-- Close shipment
UPDATE shipments SET status = 'closed' WHERE id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Create invoice
INSERT INTO invoices (id, shipment_id, company_id, invoice_number, invoice_date, due_date, party_id, subtotal, tax_amount, total_amount, currency, status)
VALUES (
    'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'INV-2024-00892',
    NOW(),
    NOW() + INTERVAL '30 days',
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02',  -- Emirates Food (buyer)
    65142.50,  -- Contract less damage claim
    3257.13,   -- 5% VAT
    68399.63,
    'AED',
    'issued'
);

-- Invoice lines
INSERT INTO invoice_lines (id, invoice_id, company_id, line_number, description, quantity, unit_price, line_total)
VALUES
    ('il0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 1, 'Door-to-door freight services - Contract GFL-2024-00147', 1, 68500.00, 68500.00),
    ('il0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 2, 'Less: Credit for damaged cargo (4 bags @ 200kg)', 1, -3357.50, -3357.50);

-- Record payment
INSERT INTO payments (id, invoice_id, company_id, payment_number, payment_date, amount, currency, payment_method, reference_number)
VALUES (
    'pa0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'PAY-2024-00654',
    NOW(),
    68399.63,
    'AED',
    'bank_transfer',
    'EFI-TT-20240815-001'
);

-- Update invoice status
UPDATE invoices
SET status = 'paid',
    amount_paid = 68399.63
WHERE id = 'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

\echo 'Shipment closed and invoiced.'

-- =============================================================================
-- ACT 8: THE AUDIT TRAIL THAT WROTE ITSELF
-- =============================================================================

\echo ''
\echo '╔══════════════════════════════════════════════════════════════════════════╗'
\echo '║  ACT 8: THE AUDIT TRAIL THAT WROTE ITSELF                                ║'
\echo '╚══════════════════════════════════════════════════════════════════════════╝'
\echo ''

-- Task status history - populated automatically by trigger
SELECT
    t.code AS task,
    h.from_status,
    h.to_status,
    h.changed_at,
    u.username AS changed_by
FROM task_status_history h
JOIN tasks t ON t.id = h.task_id
LEFT JOIN users u ON u.id = h.changed_by_user_id
WHERE t.shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
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

-- Final profitability
SELECT
    tracking_no,
    total_revenue,
    total_cost,
    gross_profit,
    margin_percent
FROM v_shipment_profitability
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Cost breakdown
\echo ''
\echo 'Cost breakdown:'
SELECT
    cost_type,
    description,
    base_currency_amount AS amount_aed
FROM cost_records
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
ORDER BY incurred_date;

-- Cargo reconciliation
\echo ''
\echo 'Cargo reconciliation:'
SELECT
    ccl.description,
    ccl.quantity AS contracted,
    scl.quantity_loaded AS loaded,
    scl.quantity_delivered AS delivered,
    (ccl.quantity - scl.quantity_delivered) AS shortfall
FROM contract_cargo_lines ccl
JOIN shipment_cargo_lines scl ON scl.contract_cargo_line_id = ccl.id
WHERE scl.shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- Customer timeline
\echo ''
\echo 'Customer timeline:'
SELECT * FROM v_shipment_tracking
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

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
BEGIN
    -- Create a test task
    INSERT INTO tasks (id, shipment_id, shipment_stage_id, company_id, code, name, status)
    SELECT
        'test-task-001',
        'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
        (SELECT id FROM shipment_stages WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' LIMIT 1),
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'TEST_TASK',
        'Test task',
        'created';

    -- Try to set waiting without reason
    UPDATE tasks SET status = 'waiting' WHERE id = 'test-task-001';
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint tasks_hold_reason prevented waiting status without reason';
        DELETE FROM tasks WHERE id = 'test-task-001';
END $$;

-- Test 2: Cannot deliver more than loaded
\echo ''
\echo 'Test 2: Cannot deliver more than was loaded'
DO $$
BEGIN
    UPDATE shipment_cargo_lines
    SET quantity_delivered = 600  -- More than the 520 loaded
    WHERE id = 'scl0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';
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
    test_shipment_id UUID := 'test-ship-001';
BEGIN
    -- Create test shipment
    INSERT INTO shipments (id, company_id, contract_id, tracking_number, status, origin_country_code, origin_city, destination_country_code, destination_city)
    VALUES (test_shipment_id, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'TEST001', 'in_transit', 'SD', 'Khartoum', 'AE', 'Sharjah');

    -- Try to close without delivery
    UPDATE shipments SET status = 'closed' WHERE id = test_shipment_id;
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint shipments_closure_rule prevented closing undelivered shipment';
        DELETE FROM shipments WHERE id = test_shipment_id;
END $$;

-- Test 4: Cannot over-pay invoice
\echo ''
\echo 'Test 4: Cannot over-pay invoice'
DO $$
BEGIN
    -- Try to pay more than invoice total
    INSERT INTO payments (id, invoice_id, company_id, payment_number, payment_date, amount, currency, payment_method)
    VALUES (
        'pa-test-001',
        'iv0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'PAY-TEST-001',
        NOW(),
        100000.00,  -- Way more than invoice total
        'AED',
        'cash'
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
    INSERT INTO handling_operations (id, shipment_id, company_id, operation_type, location_type, location_name, quantity_expected, quantity_handled, discrepancy_quantity, status)
    VALUES (
        'ho-test-001',
        'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'loading',
        'warehouse',
        'Test Warehouse',
        100,
        95,
        -5,  -- Discrepancy without remark
        'completed'
    );
    RAISE NOTICE 'ERROR: Should have failed!';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASSED: Constraint handling_discrepancy_needs_remark prevented unexPlained shortage';
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
\echo '  - 17 tasks generated automatically from workflow template'
\echo '  - Customs hold incident raised and resolved'
\echo '  - Demurrage accrued during hold'
\echo '  - 516 of 520 bags delivered (4 water damaged)'
\echo '  - Invoice issued with damage credit'
\echo '  - Payment received in full'
\echo '  - Audit trail complete (no manual inserts)'
\echo ''
\echo 'Explore with:'
\echo '  SELECT * FROM v_ready_tasks;'
\echo '  SELECT * FROM v_shipment_profitability;'
\echo '  SELECT * FROM v_shipment_tracking;'
\echo '  SELECT * FROM v_stock_on_hand;'
\echo ''
