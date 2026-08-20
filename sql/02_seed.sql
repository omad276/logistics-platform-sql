-- =============================================================================
-- 02_seed.sql
-- Logistics Operations & Task Dispatch Platform - Seed Data
--
-- Realistic scenario: Sudan → Sharjah sesame seed shipment held at customs
-- All IDs use BIGSERIAL sequences (BIGINT), matching schema
-- =============================================================================

BEGIN;

-- =============================================================================
-- SECTION 1: REFERENCE DATA
-- =============================================================================

-- Location types
INSERT INTO location_types (id, code, name) VALUES
    (1, 'ORIGIN_WAREHOUSE', 'Origin Warehouse'),
    (2, 'PORT', 'Seaport'),
    (3, 'AIRPORT', 'Airport'),
    (4, 'BONDED_WAREHOUSE', 'Bonded Warehouse'),
    (5, 'CUSTOMER_PREMISES', 'Customer Premises'),
    (6, 'CFS', 'Container Freight Station'),
    (7, 'ICD', 'Inland Container Depot');

-- =============================================================================
-- SECTION 2: COMPANY SETUP
-- =============================================================================

-- Main logistics company (ID will be 1)
INSERT INTO companies (id, legal_name, trade_name, registration_no, tax_no, base_currency, country_code, timezone)
OVERRIDING SYSTEM VALUE
VALUES (1, 'Gulf Freight Logistics LLC', 'GFL Logistics', 'SHJ-2018-123456', 'AE100123456', 'AED', 'AE', 'Asia/Dubai');

-- Reset sequence
SELECT setval('companies_id_seq', 1);

-- Branch
INSERT INTO branches (id, company_id, code, name, country_code, city)
OVERRIDING SYSTEM VALUE
VALUES (1, 1, 'SHJ-HQ', 'Sharjah Headquarters', 'AE', 'Sharjah');

SELECT setval('branches_id_seq', 1);

-- Departments
INSERT INTO departments (id, company_id, branch_id, code, name) VALUES
    (1, 1, 1, 'OPS', 'Operations'),
    (2, 1, 1, 'CUSTOMS', 'Customs'),
    (3, 1, 1, 'WAREHOUSE', 'Warehouse'),
    (4, 1, 1, 'TRANSPORT', 'Transport'),
    (5, 1, 1, 'FINANCE', 'Finance');

SELECT setval('departments_id_seq', 5);

-- =============================================================================
-- SECTION 3: USERS AND ROLES
-- =============================================================================

INSERT INTO roles (id, company_id, code, name, description) VALUES
    (1, 1, 'ADMIN', 'Administrator', 'Full system access'),
    (2, 1, 'OPS_MGR', 'Operations Manager', 'Manage shipments and tasks'),
    (3, 1, 'CUSTOMS_OFF', 'Customs Officer', 'Handle customs declarations'),
    (4, 1, 'WH_LEAD', 'Warehouse Lead', 'Warehouse operations'),
    (5, 1, 'DRIVER', 'Driver', 'Execute transport tasks');

SELECT setval('roles_id_seq', 5);

INSERT INTO users (id, company_id, branch_id, department_id, employee_no, full_name, email, phone, password_hash) VALUES
    (1, 1, 1, 1, 'EMP001', 'System Admin', 'admin@gfl.ae', '+971501234567', '$2b$10$placeholder'),
    (2, 1, 1, 1, 'EMP002', 'Ahmed Hassan', 'ahmed@gfl.ae', '+971501234568', '$2b$10$placeholder'),
    (3, 1, 1, 2, 'EMP003', 'Fatima Al-Rashid', 'fatima@gfl.ae', '+971501234569', '$2b$10$placeholder'),
    (4, 1, 1, 3, 'EMP004', 'Omar Khalil', 'omar@gfl.ae', '+971501234570', '$2b$10$placeholder'),
    (5, 1, 1, 4, 'EMP005', 'Ali Mohammed', 'ali@gfl.ae', '+971501234571', '$2b$10$placeholder');

SELECT setval('users_id_seq', 5);

INSERT INTO user_roles (user_id, role_id) VALUES
    (1, 1), (2, 2), (3, 3), (4, 4), (5, 5);

-- Set session user for audit triggers
SET app.current_user_id = '1';

-- =============================================================================
-- SECTION 4: PARTIES (Business Partners)
-- =============================================================================

-- Seller in Sudan
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_no, country_code, city, address_line, phone, email, is_seller)
VALUES (1, 1, 'NVAE', 'Nile Valley Agro Export Ltd', 'Nile Valley Agro', 'SD9876543', 'SD', 'Khartoum North',
        'Industrial Area Block 7', '+249123456789', 'ibrahim@nilevalley.sd', TRUE);

-- Buyer in UAE
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_no, country_code, city, address_line, phone, email, is_customer, is_buyer)
VALUES (2, 1, 'EFI', 'Emirates Food Industries PJSC', 'Emirates Food', 'AE200987654', 'AE', 'Sharjah',
        'SAIF Zone, Plot 34', '+97165551234', 'mohammed@emiratesfood.ae', TRUE, TRUE);

-- Shipping line
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_no, country_code, city, address_line, phone, email, is_carrier)
VALUES (3, 1, 'MSC', 'Mediterranean Shipping Company SA', 'MSC', 'CH123456', 'CH', 'Geneva',
        '12-14 Chemin Rieu', '+41229296000', 'bookings@msc.com', TRUE);

SELECT setval('parties_id_seq', 3);

-- =============================================================================
-- SECTION 5: LOCATIONS
-- =============================================================================

-- Origin: Seller's warehouse in Khartoum
INSERT INTO locations (id, company_id, location_type_id, party_id, code, name, country_code, city, address_line)
VALUES (1, 1, 1, 1, 'NVAE-WH', 'Nile Valley Warehouse', 'SD', 'Khartoum North', 'Industrial Area Block 7');

-- Port Sudan
INSERT INTO locations (id, company_id, location_type_id, code, name, unlocode, country_code, city)
VALUES (2, 1, 2, 'SDPZU', 'Port Sudan', 'SDPZU', 'SD', 'Port Sudan');

-- Jebel Ali
INSERT INTO locations (id, company_id, location_type_id, code, name, unlocode, country_code, city)
VALUES (3, 1, 2, 'AEJEA', 'Jebel Ali Port', 'AEJEA', 'AE', 'Dubai');

-- SAIF Zone Bonded Warehouse
INSERT INTO locations (id, company_id, location_type_id, code, name, country_code, city, address_line)
VALUES (4, 1, 4, 'SAIF-WH1', 'SAIF Zone Bonded Warehouse', 'AE', 'Sharjah', 'SAIF Zone, Warehouse Block C');

-- Buyer's premises
INSERT INTO locations (id, company_id, location_type_id, party_id, code, name, country_code, city, address_line)
VALUES (5, 1, 5, 2, 'EFI-PLANT', 'Emirates Food Industries Plant', 'AE', 'Sharjah', 'SAIF Zone, Plot 34');

SELECT setval('locations_id_seq', 5);

-- =============================================================================
-- SECTION 6: PRODUCT SETUP
-- =============================================================================

-- Product category: Agricultural
INSERT INTO product_categories (id, company_id, code, name, requires_phytosanitary)
VALUES (1, 1, 'AGRI', 'Agricultural Products', TRUE);

SELECT setval('product_categories_id_seq', 1);

-- Product: White sesame seed
INSERT INTO products (id, company_id, category_id, sku, name, hs_code, uom, unit_weight_kg)
VALUES (1, 1, 1, 'SESAME-WHITE-991', 'White Sesame Seed 99/1 Purity', '1207.40', 'BAG', 50.0);

SELECT setval('products_id_seq', 1);

-- =============================================================================
-- SECTION 7: DOCUMENT TYPES
-- =============================================================================

INSERT INTO document_types (id, company_id, code, name, is_customs_document) VALUES
    (1, 1, 'PACKING_LIST', 'Packing List', FALSE),
    (2, 1, 'COMMERCIAL_INV', 'Commercial Invoice', TRUE),
    (3, 1, 'BILL_LADING', 'Bill of Lading', TRUE),
    (4, 1, 'PHYTO_CERT', 'Phytosanitary Certificate', TRUE),
    (5, 1, 'COO', 'Certificate of Origin', TRUE),
    (6, 1, 'CUSTOMS_DEC', 'Customs Declaration', TRUE),
    (7, 1, 'DELIVERY_NOTE', 'Delivery Note', FALSE),
    (8, 1, 'POD', 'Proof of Delivery', FALSE);

SELECT setval('document_types_id_seq', 8);

-- =============================================================================
-- SECTION 8: CONTRACT TYPE AND WORKFLOW TEMPLATE
-- =============================================================================

-- Contract type for door-to-door sea freight
INSERT INTO contract_types (id, company_id, code, name, default_mode, origin_is_door, destination_is_door, is_international, involves_customs, involves_warehouse)
VALUES (1, 1, 'DOOR_DOOR_SEA', 'Door-to-Door Sea Freight', 'sea', TRUE, TRUE, TRUE, TRUE, TRUE);

SELECT setval('contract_types_id_seq', 1);

-- Workflow template
INSERT INTO workflow_templates (id, company_id, contract_type_id, code, name, version, is_active)
VALUES (1, 1, 1, 'D2D-SEA-V1', 'Door-to-Door Sea Freight Workflow', 1, TRUE);

SELECT setval('workflow_templates_id_seq', 1);

-- Stage templates (8 stages)
INSERT INTO stage_templates (id, workflow_template_id, sequence_no, code, name, skip_if_no_warehouse, skip_if_domestic) VALUES
    (1, 1, 10, 'PICKUP', 'Pickup from Seller', FALSE, FALSE),
    (2, 1, 20, 'LOADING', 'Loading & Stuffing', FALSE, FALSE),
    (3, 1, 30, 'EXPORT_CUSTOMS', 'Export Customs', FALSE, TRUE),
    (4, 1, 40, 'MAIN_LEG', 'Ocean Freight', FALSE, FALSE),
    (5, 1, 50, 'IMPORT_CUSTOMS', 'Import Customs', FALSE, TRUE),
    (6, 1, 60, 'WAREHOUSE', 'Bonded Warehousing', TRUE, FALSE),
    (7, 1, 70, 'FINAL_DELIVERY', 'Final Delivery', FALSE, FALSE),
    (8, 1, 80, 'CLOSURE', 'Operational Closure', FALSE, FALSE);

SELECT setval('stage_templates_id_seq', 8);

-- Task templates
-- PICKUP stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, blocks_shipment_on_failure) VALUES
    (1, 1, 1, 'PREP_VEHICLE', 'Prepare vehicle for collection', 4, 'high', 0, 2, TRUE),
    (2, 1, 2, 'COLLECT_CARGO', 'Collect cargo from seller', 4, 'high', 2, 4, TRUE);

-- LOADING stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_document, required_document_type_id, blocks_shipment_on_failure) VALUES
    (3, 2, 1, 'VERIFY_DOCS', 'Verify shipping documents', 1, 'high', 0, 2, TRUE, 1, TRUE),
    (4, 2, 2, 'STUFF_CONTAINER', 'Stuff and seal container', 3, 'high', 2, 6, FALSE, NULL, TRUE);

-- EXPORT_CUSTOMS stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_document, required_document_type_id, blocks_shipment_on_failure) VALUES
    (5, 3, 1, 'FILE_EXPORT_DEC', 'File export declaration', 2, 'high', 0, 4, TRUE, 6, TRUE),
    (6, 3, 2, 'OBTAIN_EXPORT_REL', 'Obtain export release', 2, 'urgent', 4, 8, FALSE, NULL, TRUE);

-- MAIN_LEG (Ocean) stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_document, required_document_type_id, blocks_shipment_on_failure) VALUES
    (7, 4, 1, 'BOOK_VESSEL', 'Book vessel space', 1, 'high', 0, 4, FALSE, NULL, TRUE),
    (8, 4, 2, 'ISSUE_BL', 'Issue bill of lading', 1, 'high', 4, 2, TRUE, 3, TRUE),
    (9, 4, 3, 'MONITOR_TRANSIT', 'Monitor ocean transit', 1, 'normal', 6, 168, FALSE, NULL, FALSE);

-- IMPORT_CUSTOMS stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_document, required_document_type_id, blocks_shipment_on_failure) VALUES
    (10, 5, 1, 'FILE_IMPORT_DEC', 'File import declaration', 2, 'high', 0, 4, TRUE, 6, TRUE),
    (11, 5, 2, 'SETTLE_DUTY', 'Settle duty and VAT', 5, 'high', 4, 4, FALSE, NULL, TRUE),
    (12, 5, 3, 'OBTAIN_IMPORT_REL', 'Obtain import release', 2, 'urgent', 8, 8, FALSE, NULL, TRUE);

-- WAREHOUSE stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_photo, blocks_shipment_on_failure) VALUES
    (13, 6, 1, 'RECEIVE_INSPECT', 'Receive and inspect cargo', 3, 'high', 0, 4, TRUE, TRUE),
    (14, 6, 2, 'PUT_AWAY', 'Put away to storage', 3, 'normal', 4, 2, FALSE, FALSE);

-- FINAL_DELIVERY stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, requires_signature, requires_photo, blocks_shipment_on_failure) VALUES
    (15, 7, 1, 'FINAL_LEG', 'Final leg delivery', 4, 'high', 0, 4, FALSE, FALSE, TRUE),
    (16, 7, 2, 'UNLOAD_BUYER', 'Unload at buyer premises', 4, 'high', 4, 3, FALSE, TRUE, TRUE),
    (17, 7, 3, 'CAPTURE_POD', 'Capture proof of delivery', 4, 'urgent', 7, 1, TRUE, TRUE, TRUE);

-- CLOSURE stage
INSERT INTO task_templates (id, stage_template_id, sequence_no, code, name, default_department_id, default_priority, offset_hours, duration_hours, blocks_shipment_on_failure) VALUES
    (18, 8, 1, 'RECONCILE_COSTS', 'Reconcile all costs', 5, 'high', 0, 4, TRUE),
    (19, 8, 2, 'CLOSE_FILE', 'Close shipment file', 1, 'normal', 4, 2, FALSE);

SELECT setval('task_templates_id_seq', 19);

-- Task template dependencies (finish-to-start)
INSERT INTO task_template_dependencies (task_template_id, depends_on_template_id) VALUES
    -- Pickup chain
    (2, 1),
    -- Loading depends on pickup
    (3, 2), (4, 3),
    -- Export depends on loading
    (5, 4), (6, 5),
    -- Ocean depends on export
    (7, 6), (8, 7), (9, 8),
    -- Import depends on transit
    (10, 9), (11, 10), (12, 11),
    -- Warehouse depends on import
    (13, 12), (14, 13),
    -- Delivery depends on warehouse
    (15, 14), (16, 15), (17, 16),
    -- Closure depends on POD
    (18, 17), (19, 18);

-- =============================================================================
-- SECTION 9: CONTRACT
-- =============================================================================

INSERT INTO contracts (
    id, company_id, contract_no, contract_type_id, status,
    customer_id, seller_id, buyer_id,
    origin_location_id, destination_location_id, primary_mode,
    incoterm, contract_value, currency, valid_from, valid_to,
    approved_by, approved_at, created_by
)
VALUES (
    1, 1, 'GFL-2024-00147', 1, 'active',
    2, 1, 2,  -- Customer=EFI, Seller=NVAE, Buyer=EFI
    1, 5, 'sea',  -- Origin: NVAE warehouse, Dest: EFI plant
    'CIF', 68500.00, 'AED', CURRENT_DATE - 14, CURRENT_DATE + 30,
    1, now() - INTERVAL '14 days', 1
);

SELECT setval('contracts_id_seq', 1);

-- Contract cargo line
INSERT INTO contract_cargo_lines (id, contract_id, line_no, product_id, description, quantity, uom, gross_weight_kg, net_weight_kg)
VALUES (1, 1, 1, 1, 'White sesame seed, 99/1 purity - 520 bags @ 50kg', 520, 'BAG', 26000.0, 26000.0);

SELECT setval('contract_cargo_lines_id_seq', 1);

-- Contract charges (agreed pricing in USD, converted to AED at 3.67)
INSERT INTO contract_charges (id, contract_id, charge_code, description, amount, currency, is_pass_through) VALUES
    (1, 1, 'OCEAN_FREIGHT', 'Port Sudan to Jebel Ali - 1x20ft', 2800.00, 'USD', FALSE),
    (2, 1, 'INLAND_ORIGIN', 'Khartoum to Port Sudan (830km)', 1200.00, 'USD', FALSE),
    (3, 1, 'CUSTOMS_CLEAR', 'Export + Import clearance', 650.00, 'USD', FALSE),
    (4, 1, 'WAREHOUSING', 'SAIF Zone bonded storage (5 days)', 400.00, 'USD', FALSE),
    (5, 1, 'FINAL_DELIVERY', 'SAIF Zone to buyer premises', 350.00, 'USD', FALSE);

SELECT setval('contract_charges_id_seq', 5);

-- =============================================================================
-- SECTION 10: SHIPMENT
-- =============================================================================

INSERT INTO shipments (
    id, company_id, contract_id, workflow_template_id,
    shipment_no, tracking_no, status, priority,
    origin_location_id, destination_location_id,
    total_gross_weight_kg, total_packages, container_no, seal_no,
    planned_pickup_at, planned_delivery_at, actual_pickup_at,
    created_by
)
VALUES (
    1, 1, 1, 1,
    'GFL2024147001', 'GFL2024147001', 'in_progress', 'normal',
    1, 5,  -- Origin: NVAE warehouse, Dest: EFI plant
    26000.0, 520, 'MSCU7734190', 'MSC12345678',
    now() - INTERVAL '12 days', now() + INTERVAL '2 days', now() - INTERVAL '12 days',
    1
);

SELECT setval('shipments_id_seq', 1);

-- Shipment cargo lines
INSERT INTO shipment_cargo_lines (id, shipment_id, contract_line_id, line_no, product_id, planned_quantity, loaded_quantity, uom, gross_weight_kg, package_count)
VALUES (1, 1, 1, 1, 1, 520, 520, 'BAG', 26000.0, 520);

SELECT setval('shipment_cargo_lines_id_seq', 1);

-- =============================================================================
-- SECTION 11: INSTANTIATE WORKFLOW (Manual instantiation)
-- =============================================================================

-- Create shipment stages
INSERT INTO shipment_stages (id, shipment_id, stage_template_id, sequence_no, code, name, status) VALUES
    (1, 1, 1, 10, 'PICKUP', 'Pickup from Seller', 'completed'),
    (2, 1, 2, 20, 'LOADING', 'Loading & Stuffing', 'completed'),
    (3, 1, 3, 30, 'EXPORT_CUSTOMS', 'Export Customs', 'completed'),
    (4, 1, 4, 40, 'MAIN_LEG', 'Ocean Freight', 'completed'),
    (5, 1, 5, 50, 'IMPORT_CUSTOMS', 'Import Customs', 'active'),
    (6, 1, 6, 60, 'WAREHOUSE', 'Bonded Warehousing', 'pending'),
    (7, 1, 7, 70, 'FINAL_DELIVERY', 'Final Delivery', 'pending'),
    (8, 1, 8, 80, 'CLOSURE', 'Operational Closure', 'pending');

SELECT setval('shipment_stages_id_seq', 8);

-- Update shipment current stage
UPDATE shipments SET current_stage_id = 5 WHERE id = 1;

-- Create tasks (company_id and task_no are required)
INSERT INTO tasks (id, company_id, shipment_id, stage_id, task_template_id, task_no, code, name, department_id, priority, status, scheduled_start_at, completed_at) VALUES
    -- PICKUP (completed)
    (1, 1, 1, 1, 1, 'TSK-001', 'PREP_VEHICLE', 'Prepare vehicle for collection', 4, 'high', 'completed', now() - INTERVAL '12 days', now() - INTERVAL '12 days'),
    (2, 1, 1, 1, 2, 'TSK-002', 'COLLECT_CARGO', 'Collect cargo from seller', 4, 'high', 'completed', now() - INTERVAL '12 days', now() - INTERVAL '12 days'),
    -- LOADING (completed)
    (3, 1, 1, 2, 3, 'TSK-003', 'VERIFY_DOCS', 'Verify shipping documents', 1, 'high', 'completed', now() - INTERVAL '11 days', now() - INTERVAL '11 days'),
    (4, 1, 1, 2, 4, 'TSK-004', 'STUFF_CONTAINER', 'Stuff and seal container', 3, 'high', 'completed', now() - INTERVAL '11 days', now() - INTERVAL '11 days'),
    -- EXPORT_CUSTOMS (completed)
    (5, 1, 1, 3, 5, 'TSK-005', 'FILE_EXPORT_DEC', 'File export declaration', 2, 'high', 'completed', now() - INTERVAL '10 days', now() - INTERVAL '10 days'),
    (6, 1, 1, 3, 6, 'TSK-006', 'OBTAIN_EXPORT_REL', 'Obtain export release', 2, 'urgent', 'completed', now() - INTERVAL '10 days', now() - INTERVAL '10 days'),
    -- MAIN_LEG (completed)
    (7, 1, 1, 4, 7, 'TSK-007', 'BOOK_VESSEL', 'Book vessel space', 1, 'high', 'completed', now() - INTERVAL '9 days', now() - INTERVAL '9 days'),
    (8, 1, 1, 4, 8, 'TSK-008', 'ISSUE_BL', 'Issue bill of lading', 1, 'high', 'completed', now() - INTERVAL '9 days', now() - INTERVAL '9 days'),
    (9, 1, 1, 4, 9, 'TSK-009', 'MONITOR_TRANSIT', 'Monitor ocean transit', 1, 'normal', 'completed', now() - INTERVAL '9 days', now() - INTERVAL '2 days'),
    -- IMPORT_CUSTOMS (in progress - THIS IS THE HOLD)
    (10, 1, 1, 5, 10, 'TSK-010', 'FILE_IMPORT_DEC', 'File import declaration', 2, 'high', 'completed', now() - INTERVAL '1 day', now() - INTERVAL '1 day'),
    (11, 1, 1, 5, 11, 'TSK-011', 'SETTLE_DUTY', 'Settle duty and VAT', 5, 'high', 'waiting', now() - INTERVAL '20 hours', NULL),
    (12, 1, 1, 5, 12, 'TSK-012', 'OBTAIN_IMPORT_REL', 'Obtain import release', 2, 'urgent', 'created', now(), NULL),
    -- WAREHOUSE (pending)
    (13, 1, 1, 6, 13, 'TSK-013', 'RECEIVE_INSPECT', 'Receive and inspect cargo', 3, 'high', 'created', now() + INTERVAL '1 day', NULL),
    (14, 1, 1, 6, 14, 'TSK-014', 'PUT_AWAY', 'Put away to storage', 3, 'normal', 'created', now() + INTERVAL '1 day', NULL),
    -- FINAL_DELIVERY (pending)
    (15, 1, 1, 7, 15, 'TSK-015', 'FINAL_LEG', 'Final leg delivery', 4, 'high', 'created', now() + INTERVAL '2 days', NULL),
    (16, 1, 1, 7, 16, 'TSK-016', 'UNLOAD_BUYER', 'Unload at buyer premises', 4, 'high', 'created', now() + INTERVAL '2 days', NULL),
    (17, 1, 1, 7, 17, 'TSK-017', 'CAPTURE_POD', 'Capture proof of delivery', 4, 'urgent', 'created', now() + INTERVAL '2 days', NULL),
    -- CLOSURE (pending)
    (18, 1, 1, 8, 18, 'TSK-018', 'RECONCILE_COSTS', 'Reconcile all costs', 5, 'high', 'created', now() + INTERVAL '3 days', NULL),
    (19, 1, 1, 8, 19, 'TSK-019', 'CLOSE_FILE', 'Close shipment file', 1, 'normal', 'created', now() + INTERVAL '3 days', NULL);

SELECT setval('tasks_id_seq', 19);

-- Set hold reason on waiting task
UPDATE tasks SET hold_reason = 'Awaiting customs release - declaration held pending phytosanitary verification' WHERE id = 11;

-- Task dependencies (mirrors template dependencies)
INSERT INTO task_dependencies (task_id, depends_on_task_id) VALUES
    (2, 1), (3, 2), (4, 3), (5, 4), (6, 5), (7, 6), (8, 7), (9, 8),
    (10, 9), (11, 10), (12, 11), (13, 12), (14, 13), (15, 14), (16, 15), (17, 16), (18, 17), (19, 18);

-- =============================================================================
-- SECTION 12: CUSTOMS DECLARATION (HELD)
-- =============================================================================

INSERT INTO customs_declarations (
    id, company_id, shipment_id, declaration_no, direction, country_code, customs_office,
    declared_value, currency, duty_amount, vat_amount,
    status, hold_reason, submitted_at
)
VALUES (
    1, 1, 1, 'JAFZA-2024-087421', 'import', 'AE', 'Jebel Ali Free Zone',
    68500.00, 'AED', 342.50, 3425.00,
    'held', 'Phytosanitary certificate verification required by MOCCAE',
    now() - INTERVAL '1 day'
);

SELECT setval('customs_declarations_id_seq', 1);

-- =============================================================================
-- SECTION 13: INCIDENT TYPES AND INCIDENT
-- =============================================================================

-- Incident types (reference data)
INSERT INTO incident_types (id, code, name, default_severity) VALUES
    (1, 'CUSTOMS_HOLD', 'Customs Hold', 'critical'),
    (2, 'CARGO_DAMAGE', 'Cargo Damage', 'high'),
    (3, 'DELAY', 'Delivery Delay', 'medium'),
    (4, 'DOCUMENTATION', 'Documentation Issue', 'medium'),
    (5, 'VEHICLE_BREAKDOWN', 'Vehicle Breakdown', 'high');

SELECT setval('incident_types_id_seq', 5);

-- The customs hold incident
INSERT INTO incidents (
    id, company_id, shipment_id, incident_no, incident_type_id, severity,
    description, occurred_at, reported_by, status
)
VALUES (
    1, 1, 1, 'INC-2024-00089', 1, 'critical',
    'Import declaration held at Jebel Ali. MOCCAE has requested verification of the phytosanitary certificate issued by Sudan Plant Protection Directorate. Container MSCU7734190 is currently on terminal awaiting release. Demurrage will accrue from day 4.',
    now() - INTERVAL '20 hours', 3, 'open'
);

SELECT setval('incidents_id_seq', 1);

-- =============================================================================
-- SECTION 14: TRACKING EVENTS
-- =============================================================================

INSERT INTO tracking_events (id, shipment_id, event_code, title, location_id, occurred_at, description) VALUES
    (1, 1, 'PICKED_UP', 'Cargo Collected', 1, now() - INTERVAL '12 days', 'Cargo collected from Nile Valley Agro Export'),
    (2, 1, 'LOADED', 'Container Loaded', 2, now() - INTERVAL '11 days', 'Loaded into container MSCU7734190'),
    (3, 1, 'DEPARTED', 'Vessel Departed', 2, now() - INTERVAL '9 days', 'Vessel MSC RAVENNA departed Port Sudan'),
    (4, 1, 'ARRIVED', 'Vessel Arrived', 3, now() - INTERVAL '2 days', 'Vessel arrived Jebel Ali'),
    (5, 1, 'HELD', 'Customs Hold', 3, now() - INTERVAL '20 hours', 'Import declaration held - phytosanitary verification');

SELECT setval('tracking_events_id_seq', 5);

-- =============================================================================
-- SECTION 15: RESOURCES (Vehicles, Drivers, Warehouses)
-- =============================================================================

-- Warehouse
INSERT INTO warehouses (id, company_id, location_id, code, name, is_bonded, capacity_cbm)
VALUES (1, 1, 4, 'SAIF-WH1', 'SAIF Zone Bonded Warehouse', TRUE, 5000);

SELECT setval('warehouses_id_seq', 1);

-- Storage bins
INSERT INTO storage_bins (id, warehouse_id, code, zone, capacity_cbm) VALUES
    (1, 1, 'A-01-01', 'A', 50),
    (2, 1, 'A-01-02', 'A', 50),
    (3, 1, 'A-01-03', 'A', 50);

SELECT setval('storage_bins_id_seq', 3);

-- Vehicles
INSERT INTO vehicles (id, company_id, plate_no, vehicle_type, capacity_kg, capacity_cbm, status) VALUES
    (1, 1, 'SHJ-12345', 'truck_20ft', 18000, 33, 'available'),
    (2, 1, 'SHJ-67890', 'truck_40ft', 26000, 67, 'available');

SELECT setval('vehicles_id_seq', 2);

-- Drivers
INSERT INTO drivers (id, company_id, user_id, full_name, phone, licence_no, licence_expiry) VALUES
    (1, 1, 5, 'Ali Mohammed', '+971501234571', 'DL-UAE-2023-78901', '2026-06-30');

SELECT setval('drivers_id_seq', 1);

-- =============================================================================
-- SECTION 16: TRANSPORT ORDERS
-- =============================================================================

-- Origin transport order (completed)
INSERT INTO transport_orders (id, company_id, shipment_id, order_no, mode, origin_location_id, destination_location_id, status, actual_departure, actual_arrival)
VALUES (1, 1, 1, 'TO-2024-00291', 'road', 1, 2, 'completed', now() - INTERVAL '12 days', now() - INTERVAL '11 days');

-- Ocean transport order (completed)
INSERT INTO transport_orders (id, company_id, shipment_id, order_no, mode, carrier_party_id, vessel_or_flight_no, origin_location_id, destination_location_id, status, actual_departure, actual_arrival)
VALUES (2, 1, 1, 'TO-2024-00292', 'sea', 3, 'MSC RAVENNA / AE425E', 2, 3, 'completed', now() - INTERVAL '9 days', now() - INTERVAL '2 days');

SELECT setval('transport_orders_id_seq', 2);

-- =============================================================================
-- SECTION 17: COST CATEGORIES (for shipment_financials)
-- =============================================================================

INSERT INTO cost_categories (id, company_id, code, name, direction, is_billable) VALUES
    (1, 1, 'OCEAN_FREIGHT', 'Ocean Freight', 'cost', TRUE),
    (2, 1, 'INLAND_ORIGIN', 'Inland Trucking (Origin)', 'cost', TRUE),
    (3, 1, 'INLAND_DEST', 'Inland Trucking (Dest)', 'cost', TRUE),
    (4, 1, 'LOADING', 'Loading/Handling', 'cost', TRUE),
    (5, 1, 'UNLOADING', 'Unloading', 'cost', TRUE),
    (6, 1, 'THC', 'Terminal Handling', 'cost', TRUE),
    (7, 1, 'CUSTOMS_EXPORT', 'Customs Export Clearance', 'cost', TRUE),
    (8, 1, 'CUSTOMS_IMPORT', 'Customs Import Clearance', 'cost', TRUE),
    (9, 1, 'DUTY', 'Import Duty', 'cost', TRUE),
    (10, 1, 'VAT', 'Import VAT', 'cost', TRUE),
    (11, 1, 'STORAGE', 'Storage/Warehousing', 'cost', TRUE),
    (12, 1, 'DEMURRAGE', 'Demurrage/Detention', 'cost', TRUE),
    (13, 1, 'INSPECTION', 'Inspection Fees', 'cost', TRUE),
    (14, 1, 'DOCUMENTATION', 'Documentation', 'cost', TRUE),
    (15, 1, 'FREIGHT_REVENUE', 'Freight Charges', 'revenue', TRUE),
    (16, 1, 'DUTY_RECOVERY', 'Duty Recovery', 'revenue', TRUE),
    (17, 1, 'VAT_RECOVERY', 'VAT Recovery', 'revenue', TRUE);

SELECT setval('cost_categories_id_seq', 17);

-- =============================================================================
-- SECTION 18: SHIPMENT FINANCIALS (Initial estimates at booking)
-- =============================================================================

-- Estimates (committed costs at booking time)
INSERT INTO shipment_financials (company_id, shipment_id, cost_category_id, direction, description, amount, currency, fx_rate, base_amount, is_estimated, incurred_on) VALUES
    -- Ocean freight estimate
    (1, 1, 1, 'cost', 'MSC ocean freight Port Sudan - Jebel Ali (quoted)', 2800.00, 'USD', 3.67, 10276.00, TRUE, CURRENT_DATE - 14),
    -- Origin trucking estimate
    (1, 1, 2, 'cost', 'Road freight Khartoum - Port Sudan (quoted)', 1200.00, 'USD', 3.67, 4404.00, TRUE, CURRENT_DATE - 14),
    -- Loading estimate
    (1, 1, 4, 'cost', 'Loading at origin + stuffing (quoted)', 450.00, 'USD', 3.67, 1651.50, TRUE, CURRENT_DATE - 14),
    -- Export customs estimate
    (1, 1, 7, 'cost', 'Export clearance Port Sudan (quoted)', 250.00, 'USD', 3.67, 917.50, TRUE, CURRENT_DATE - 14),
    -- THC estimate
    (1, 1, 6, 'cost', 'Jebel Ali THC (quoted)', 450.00, 'USD', 3.67, 1651.50, TRUE, CURRENT_DATE - 14),
    -- Import customs estimate
    (1, 1, 8, 'cost', 'Import clearance UAE (quoted)', 400.00, 'USD', 3.67, 1468.00, TRUE, CURRENT_DATE - 14),
    -- Storage estimate (standard 2 days)
    (1, 1, 11, 'cost', 'Bonded storage 2 days (quoted)', 180.00, 'USD', 3.67, 660.60, TRUE, CURRENT_DATE - 14),
    -- Final delivery estimate
    (1, 1, 3, 'cost', 'Delivery Jebel Ali - SAIF Zone (quoted)', 350.00, 'USD', 3.67, 1284.50, TRUE, CURRENT_DATE - 14),
    -- Revenue
    (1, 1, 15, 'revenue', 'Door-to-door freight services (contract)', 68500.00, 'AED', 1.00, 68500.00, FALSE, CURRENT_DATE - 14);

-- Some costs already incurred (actuals)
-- These will supersede the estimates in 08_realistic_financials.sql

COMMIT;

-- =============================================================================
-- SUMMARY
-- =============================================================================

DO $$
DECLARE
    task_count INTEGER;
    completed_count INTEGER;
    blocked_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO task_count FROM tasks WHERE shipment_id = 1;
    SELECT COUNT(*) INTO completed_count FROM tasks WHERE shipment_id = 1 AND status = 'completed';
    SELECT COUNT(*) INTO blocked_count FROM tasks t
        WHERE t.shipment_id = 1
        AND t.status NOT IN ('completed', 'closed')
        AND EXISTS (
            SELECT 1 FROM task_dependencies td
            JOIN tasks p ON p.id = td.depends_on_task_id
            WHERE td.task_id = t.id AND p.status NOT IN ('completed', 'closed')
        );

    RAISE NOTICE '';
    RAISE NOTICE '=== SEED DATA LOADED ===';
    RAISE NOTICE 'Contract: GFL-2024-00147 (Door-to-Door Sea Freight)';
    RAISE NOTICE 'Shipment: GFL2024147001 (Container MSCU7734190)';
    RAISE NOTICE 'Route: Khartoum North → Port Sudan → Jebel Ali → SAIF Zone';
    RAISE NOTICE 'Cargo: 26 MT white sesame seed (520 bags @ 50kg)';
    RAISE NOTICE '';
    RAISE NOTICE 'Tasks: % total, % completed, % blocked', task_count, completed_count, blocked_count;
    RAISE NOTICE 'Status: HELD at Jebel Ali - phytosanitary verification pending';
    RAISE NOTICE '';
    RAISE NOTICE 'Run 03_demo_customs_hold.sql to continue the scenario.';
END $$;
