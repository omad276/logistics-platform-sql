-- =============================================================================
-- 02_seed.sql
-- Logistics Operations & Task Dispatch Platform - Seed Data
--
-- This file populates the database with a realistic scenario:
-- Sudan → Sharjah sesame seed shipment, currently held at customs
-- =============================================================================

-- Set acting user for audit trail
SET app.current_user_id = '1';

-- =============================================================================
-- SECTION 1: COMPANY SETUP
-- =============================================================================

-- Main logistics company operating the platform
INSERT INTO companies (id, code, legal_name, trade_name, tax_id, company_type, base_currency)
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'GFL',
    'Gulf Freight Logistics LLC',
    'GFL Logistics',
    'AE100123456',
    'freight_forwarder',
    'AED'
);

-- Branch office
INSERT INTO branches (id, company_id, code, name, address_line1, city, country_code, is_headquarters)
VALUES (
    'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'SHJ-HQ',
    'Sharjah Headquarters',
    'Al Majaz 3, Building 14',
    'Sharjah',
    'AE',
    true
);

-- Departments
INSERT INTO departments (id, branch_id, company_id, code, name)
VALUES
    ('d1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'OPS', 'Operations'),
    ('d1eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'CUSTOMS', 'Customs'),
    ('d1eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'WAREHOUSE', 'Warehouse'),
    ('d1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'TRANSPORT', 'Transport'),
    ('d1eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a22', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'FINANCE', 'Finance');

-- =============================================================================
-- SECTION 2: USERS AND ROLES
-- =============================================================================

INSERT INTO roles (id, company_id, code, name, description)
VALUES
    ('r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'ADMIN', 'Administrator', 'Full system access'),
    ('r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'OPS_MGR', 'Operations Manager', 'Manage shipments and tasks'),
    ('r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'CUSTOMS_OFF', 'Customs Officer', 'Handle customs declarations'),
    ('r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'WH_LEAD', 'Warehouse Lead', 'Warehouse operations'),
    ('r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'DRIVER', 'Driver', 'Execute transport tasks');

INSERT INTO users (id, company_id, username, email, password_hash, full_name, phone, status)
VALUES
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'admin', 'admin@gfl.ae', '$2b$10$hash', 'System Admin', '+971501234567', 'active'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'ahmed.ops', 'ahmed@gfl.ae', '$2b$10$hash', 'Ahmed Hassan', '+971501234568', 'active'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'fatima.customs', 'fatima@gfl.ae', '$2b$10$hash', 'Fatima Al-Rashid', '+971501234569', 'active'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'omar.wh', 'omar@gfl.ae', '$2b$10$hash', 'Omar Khalil', '+971501234570', 'active'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'driver.ali', 'ali@gfl.ae', '$2b$10$hash', 'Ali Mohammed', '+971501234571', 'active');

INSERT INTO user_roles (user_id, role_id)
VALUES
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04'),
    ('u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'r0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05');

-- =============================================================================
-- SECTION 3: PARTIES (CUSTOMERS)
-- =============================================================================

-- Seller in Sudan
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_id, party_type, country_code, city, address_line1, primary_contact_name, primary_contact_email, primary_contact_phone)
VALUES (
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'NVAE',
    'Nile Valley Agro Export Ltd',
    'Nile Valley Agro',
    'SD9876543',
    'seller',
    'SD',
    'Khartoum North',
    'Industrial Area Block 7',
    'Ibrahim Osman',
    'ibrahim@nilevalley.sd',
    '+249123456789'
);

-- Buyer in UAE
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_id, party_type, country_code, city, address_line1, primary_contact_name, primary_contact_email, primary_contact_phone)
VALUES (
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'EFI',
    'Emirates Food Industries PJSC',
    'Emirates Food',
    'AE200987654',
    'buyer',
    'AE',
    'Sharjah',
    'SAIF Zone, Plot 34',
    'Mohammed Al-Sayed',
    'mohammed@emiratesfood.ae',
    '+97165551234'
);

-- Shipping line
INSERT INTO parties (id, company_id, code, legal_name, trade_name, tax_id, party_type, country_code, city, address_line1, primary_contact_name, primary_contact_email, primary_contact_phone)
VALUES (
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'MSC',
    'Mediterranean Shipping Company SA',
    'MSC',
    'CH123456',
    'carrier',
    'CH',
    'Geneva',
    '12-14 Chemin Rieu',
    'Booking Dept',
    'bookings@msc.com',
    '+41229296000'
);

-- =============================================================================
-- SECTION 4: CONTRACT TYPES AND WORKFLOW TEMPLATES
-- =============================================================================

-- Contract type for door-to-door sea freight
INSERT INTO contract_types (id, company_id, code, name, origin_is_door, destination_is_door, is_international, involves_warehouse, default_mode)
VALUES (
    'ct0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'DOOR_DOOR_SEA',
    'Door-to-Door Sea Freight',
    true,
    true,
    true,
    true,
    'sea'
);

-- Workflow template for door-to-door
INSERT INTO workflow_templates (id, company_id, contract_type_id, code, name, description, version, is_active)
VALUES (
    'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'ct0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'D2D-SEA-V1',
    'Door-to-Door Sea Freight Workflow',
    'Complete workflow for international door-to-door movements via sea',
    1,
    true
);

-- Stage templates
INSERT INTO stage_templates (id, workflow_template_id, company_id, code, name, sequence_order, skip_if_no_warehouse, skip_if_domestic)
VALUES
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a10', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'PICKUP', 'Pickup from Seller', 10, false, false),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a20', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'LOADING', 'Loading & Stuffing', 20, false, false),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a30', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'EXPORT_CUSTOMS', 'Export Customs', 30, false, true),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a40', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'MAIN_LEG', 'Ocean Freight', 40, false, false),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a50', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'IMPORT_CUSTOMS', 'Import Customs', 50, false, true),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a60', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'WAREHOUSE', 'Bonded Warehousing', 60, true, false),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a70', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'FINAL_DELIVERY', 'Final Delivery', 70, false, false),
    ('st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a80', 'wt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'CLOSURE', 'Operational Closure', 80, false, false);

-- Task templates for PICKUP stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a101', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a10', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'PREP_VEHICLE', 'Prepare vehicle for collection', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'high', 0, 2, true),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a102', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a10', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'COLLECT_CARGO', 'Collect cargo from seller', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'high', 2, 4, true);

-- Task templates for LOADING stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_document_type)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a201', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a20', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'VERIFY_DOCS', 'Verify shipping documents', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'high', 0, 2, true, 'packing_list'),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a202', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a20', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'STUFF_CONTAINER', 'Stuff and seal container', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'high', 2, 6, true, NULL);

-- Task templates for EXPORT_CUSTOMS stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_document_type)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a301', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a30', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'FILE_EXPORT_DEC', 'File export declaration', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'high', 0, 4, true, 'customs_declaration'),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a302', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a30', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'OBTAIN_EXPORT_REL', 'Obtain export release', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'critical', 4, 8, true, NULL);

-- Task templates for MAIN_LEG (Ocean) stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_document_type)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a401', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a40', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'BOOK_VESSEL', 'Book vessel space', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'high', 0, 4, true, NULL),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a402', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a40', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'ISSUE_BL', 'Issue bill of lading', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'high', 4, 2, true, 'bill_of_lading'),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a403', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a40', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'MONITOR_TRANSIT', 'Monitor ocean transit', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'medium', 6, 168, false, NULL);

-- Task templates for IMPORT_CUSTOMS stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_document_type)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a501', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a50', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'FILE_IMPORT_DEC', 'File import declaration', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'high', 0, 4, true, 'customs_declaration'),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a502', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a50', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'SETTLE_DUTY', 'Settle duty and VAT', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'high', 4, 4, true, NULL),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a503', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a50', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'OBTAIN_IMPORT_REL', 'Obtain import release', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'critical', 8, 8, true, NULL);

-- Task templates for WAREHOUSE stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_photo)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a601', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a60', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'RECEIVE_INSPECT', 'Receive and inspect cargo', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'high', 0, 4, true, true),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a602', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a60', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'PUT_AWAY', 'Put away to storage', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'medium', 4, 2, false, false);

-- Task templates for FINAL_DELIVERY stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment, requires_signature, requires_photo)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a701', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a70', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'FINAL_LEG', 'Final leg delivery', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'high', 0, 4, true, false, false),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a702', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a70', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'UNLOAD_BUYER', 'Unload at buyer premises', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'high', 4, 3, true, false, true),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a703', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a70', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'CAPTURE_POD', 'Capture proof of delivery', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'critical', 7, 1, true, true, true);

-- Task templates for CLOSURE stage
INSERT INTO task_templates (id, stage_template_id, company_id, code, name, default_department_id, priority, offset_hours, expected_duration_hours, blocks_shipment)
VALUES
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a801', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a80', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'RECONCILE_COSTS', 'Reconcile all costs', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'high', 0, 4, true),
    ('tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a802', 'st0eebc99-9c0b-4ef8-bb6d-6bb9bd380a80', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'CLOSE_FILE', 'Close shipment file', 'd1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'medium', 4, 2, false);

-- Task template dependencies (finish-to-start)
INSERT INTO task_template_dependencies (id, task_template_id, depends_on_template_id, dependency_type)
VALUES
    -- Pickup dependencies
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a102', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a101', 'finish_to_start'),
    -- Loading depends on pickup complete
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a201', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a102', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a202', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a201', 'finish_to_start'),
    -- Export customs depends on loading
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a301', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a202', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a302', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a301', 'finish_to_start'),
    -- Ocean leg depends on export release
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a401', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a302', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a402', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a401', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a403', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a402', 'finish_to_start'),
    -- Import customs depends on transit complete
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a501', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a403', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a502', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a501', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a503', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a502', 'finish_to_start'),
    -- Warehouse depends on import release
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a601', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a503', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a602', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a601', 'finish_to_start'),
    -- Final delivery depends on warehouse
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a701', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a602', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a702', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a701', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a703', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a702', 'finish_to_start'),
    -- Closure depends on POD
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a801', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a703', 'finish_to_start'),
    (gen_random_uuid(), 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a802', 'tt0eebc99-9c0b-4ef8-bb6d-6bb9bd380a801', 'finish_to_start');

-- =============================================================================
-- SECTION 5: RESOURCES (VEHICLES, DRIVERS, WAREHOUSES)
-- =============================================================================

-- Warehouse
INSERT INTO warehouses (id, company_id, code, name, address_line1, city, country_code, warehouse_type, total_capacity_cbm, is_bonded)
VALUES (
    'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'SAIF-WH1',
    'SAIF Zone Bonded Warehouse',
    'SAIF Zone, Warehouse Block C',
    'Sharjah',
    'AE',
    'bonded',
    5000,
    true
);

-- Storage bins
INSERT INTO storage_bins (id, warehouse_id, company_id, code, bin_type, max_weight_kg)
VALUES
    ('sb0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'A-01-01', 'pallet', 2000),
    ('sb0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'A-01-02', 'pallet', 2000),
    ('sb0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'wh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'A-01-03', 'pallet', 2000);

-- Vehicles
INSERT INTO vehicles (id, company_id, plate_number, vehicle_type, capacity_kg, capacity_cbm, status)
VALUES
    ('ve0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'SHJ-12345', 'truck_20ft', 18000, 33, 'available'),
    ('ve0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'SHJ-67890', 'truck_40ft', 26000, 67, 'available');

-- Drivers
INSERT INTO drivers (id, company_id, user_id, license_number, license_expiry_date, status)
VALUES (
    'dr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05',
    'DL-UAE-2023-78901',
    '2026-06-30',
    'available'
);

-- =============================================================================
-- SECTION 6: CONTRACT AND SHIPMENT
-- =============================================================================

-- Contract for sesame seed shipment
INSERT INTO contracts (id, company_id, contract_number, contract_type_id, seller_party_id, buyer_party_id, incoterm, transport_mode, origin_country_code, origin_city, origin_address, destination_country_code, destination_city, destination_address, agreed_value, agreed_currency, exchange_rate_to_base, base_currency_value, status, approved_at, approved_by_user_id)
VALUES (
    'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'GFL-2024-00147',
    'ct0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',  -- Nile Valley (seller)
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02',  -- Emirates Food (buyer)
    'CIF',
    'sea',
    'SD',
    'Khartoum North',
    'Industrial Area Block 7, Nile Valley Agro Export',
    'AE',
    'Sharjah',
    'SAIF Zone, Plot 34, Emirates Food Industries',
    68500.00,
    'AED',
    1.0,
    68500.00,
    'approved',
    NOW() - INTERVAL '14 days',
    'u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
);

-- Contract cargo line
INSERT INTO contract_cargo_lines (id, contract_id, company_id, line_number, hs_code, description, quantity, unit_of_measure, unit_weight_kg, total_weight_kg, commodity_type)
VALUES (
    'ccl0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    1,
    '1207.40',
    'White sesame seed, 99/1 purity',
    520,
    'bags',
    50.0,
    26000.0,
    'agricultural'
);

-- Contract charges (agreed pricing)
INSERT INTO contract_charges (id, contract_id, company_id, charge_type, description, amount, currency)
VALUES
    ('cch0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'ocean_freight', 'Port Sudan to Jebel Ali - 1x20ft', 2800.00, 'USD'),
    ('cch0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'inland_transport', 'Khartoum to Port Sudan (830km)', 1200.00, 'USD'),
    ('cch0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'customs_clearance', 'Export + Import clearance', 650.00, 'USD'),
    ('cch0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'warehousing', 'SAIF Zone bonded storage (5 days)', 400.00, 'USD'),
    ('cch0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'final_delivery', 'SAIF Zone to buyer premises', 350.00, 'USD');

-- Shipment (instantiated from contract)
INSERT INTO shipments (id, company_id, contract_id, tracking_number, container_number, status, estimated_departure, estimated_arrival, origin_country_code, origin_city, destination_country_code, destination_city)
VALUES (
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'co0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'GFL2024147001',
    'MSCU7734190',
    'in_transit',
    NOW() - INTERVAL '10 days',
    NOW() + INTERVAL '2 days',
    'SD',
    'Khartoum North',
    'AE',
    'Sharjah'
);

-- Shipment cargo lines
INSERT INTO shipment_cargo_lines (id, shipment_id, contract_cargo_line_id, company_id, quantity_loaded, quantity_delivered, unit_of_measure, weight_loaded_kg)
VALUES (
    'scl0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'ccl0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    520,  -- All 520 bags loaded
    0,    -- Not yet delivered
    'bags',
    26000.0
);

-- =============================================================================
-- SECTION 7: INSTANTIATE WORKFLOW
-- =============================================================================

-- Call the workflow instantiation function
SELECT fn_instantiate_workflow('sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01');

-- =============================================================================
-- SECTION 8: PROGRESS THROUGH EARLY STAGES (Completed)
-- =============================================================================

-- Mark early tasks as completed to show progress
-- Note: This creates audit history via trigger

-- Complete PICKUP tasks
UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '12 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'PREP_VEHICLE';

UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '12 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'COLLECT_CARGO';

-- Complete LOADING tasks
UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '11 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'VERIFY_DOCS';

UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '11 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'STUFF_CONTAINER';

-- Complete EXPORT CUSTOMS tasks
UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '10 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'FILE_EXPORT_DEC';

UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '10 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'OBTAIN_EXPORT_REL';

-- Complete OCEAN LEG tasks
UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '9 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'BOOK_VESSEL';

UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '9 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'ISSUE_BL';

UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '2 days'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'MONITOR_TRANSIT';

-- =============================================================================
-- SECTION 9: IMPORT CUSTOMS - THE HOLD SCENARIO
-- =============================================================================

-- File import declaration (started)
UPDATE tasks SET status = 'completed', completed_at = NOW() - INTERVAL '1 day'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'FILE_IMPORT_DEC';

-- Settle duty (started, waiting on hold)
UPDATE tasks SET
    status = 'waiting',
    hold_reason = 'Awaiting customs release - declaration held pending phytosanitary verification'
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
  AND code = 'SETTLE_DUTY';

-- Create the customs declaration with held status
INSERT INTO customs_declarations (id, shipment_id, company_id, declaration_number, declaration_type, filing_date, status, port_code, hs_codes, declared_value, declared_currency, duty_amount, vat_amount, hold_reason)
VALUES (
    'cd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'JAFZA-2024-087421',
    'import',
    NOW() - INTERVAL '1 day',
    'held',
    'AEJEA',  -- Jebel Ali
    ARRAY['1207.40'],
    68500.00,
    'AED',
    342.50,   -- 0.5% duty on agricultural
    3425.00,  -- 5% VAT
    'Phytosanitary certificate verification required by MOCCAE'
);

-- Create the incident for the customs hold
INSERT INTO incidents (id, shipment_id, company_id, incident_number, incident_type, severity, title, description, reported_at, reported_by_user_id, status)
VALUES (
    'in0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'INC-2024-00089',
    'customs_hold',
    'critical',
    'Import declaration held at Jebel Ali',
    'MOCCAE has requested verification of the phytosanitary certificate issued by Sudan Plant Protection Directorate. Container MSCU7734190 is currently on terminal awaiting release. Demurrage will accrue from day 4.',
    NOW() - INTERVAL '20 hours',
    'u0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03',  -- Fatima (Customs)
    'open'
);

-- =============================================================================
-- SECTION 10: FINANCIAL RECORDS (Costs Incurred)
-- =============================================================================

-- Create shipment financial record
INSERT INTO shipment_financials (id, shipment_id, company_id, total_revenue, total_cost, gross_profit, currency)
VALUES (
    'sf0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    68500.00,
    0,  -- Will be calculated from cost records
    68500.00,
    'AED'
);

-- Cost records for expenses already incurred
INSERT INTO cost_records (id, shipment_id, company_id, cost_type, description, amount, currency, exchange_rate_to_base, base_currency_amount, incurred_date, status)
VALUES
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'inland_transport', 'Road freight Khartoum-Port Sudan', 1200.00, 'USD', 3.67, 4404.00, NOW() - INTERVAL '11 days', 'paid'),
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'ocean_freight', 'MSC - Port Sudan to Jebel Ali', 2800.00, 'USD', 3.67, 10276.00, NOW() - INTERVAL '9 days', 'paid'),
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'customs_clearance', 'Export clearance Port Sudan', 250.00, 'USD', 3.67, 917.50, NOW() - INTERVAL '10 days', 'paid'),
    ('cr0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'terminal_handling', 'Jebel Ali THC', 450.00, 'USD', 3.67, 1651.50, NOW() - INTERVAL '1 day', 'accrued');

-- Update total cost
UPDATE shipment_financials
SET total_cost = (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'),
    gross_profit = total_revenue - (SELECT COALESCE(SUM(base_currency_amount), 0) FROM cost_records WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01')
WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';

-- =============================================================================
-- SECTION 11: TRACKING EVENTS
-- =============================================================================

INSERT INTO tracking_events (id, shipment_id, company_id, event_type, event_timestamp, location_name, location_country_code, description)
VALUES
    ('te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'picked_up', NOW() - INTERVAL '12 days', 'Khartoum North', 'SD', 'Cargo collected from Nile Valley Agro Export'),
    ('te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'loaded', NOW() - INTERVAL '11 days', 'Port Sudan', 'SD', 'Loaded into container MSCU7734190'),
    ('te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'departed', NOW() - INTERVAL '9 days', 'Port Sudan', 'SD', 'Vessel MSC RAVENNA departed'),
    ('te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a04', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'arrived_port', NOW() - INTERVAL '2 days', 'Jebel Ali', 'AE', 'Vessel arrived Jebel Ali'),
    ('te0eebc99-9c0b-4ef8-bb6d-6bb9bd380a05', 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01', 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'customs_hold', NOW() - INTERVAL '20 hours', 'Jebel Ali', 'AE', 'Import declaration held - phytosanitary verification');

-- =============================================================================
-- SECTION 12: TRANSPORT ORDERS
-- =============================================================================

-- Origin transport order (completed)
INSERT INTO transport_orders (id, shipment_id, company_id, order_number, transport_mode, origin_address, destination_address, vehicle_id, driver_id, status, actual_departure, actual_arrival)
VALUES (
    'to0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'TO-2024-00291',
    'road',
    'Khartoum North, Industrial Area Block 7',
    'Port Sudan Container Terminal',
    NULL,  -- External vehicle in Sudan
    NULL,  -- External driver
    'completed',
    NOW() - INTERVAL '12 days',
    NOW() - INTERVAL '11 days'
);

-- Ocean transport order (completed)
INSERT INTO transport_orders (id, shipment_id, company_id, order_number, transport_mode, carrier_party_id, vessel_name, voyage_number, origin_address, destination_address, status, actual_departure, actual_arrival)
VALUES (
    'to0eebc99-9c0b-4ef8-bb6d-6bb9bd380a02',
    'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'TO-2024-00292',
    'sea',
    'p0eebc99-9c0b-4ef8-bb6d-6bb9bd380a03',  -- MSC
    'MSC RAVENNA',
    'AE425E',
    'Port Sudan',
    'Jebel Ali',
    'completed',
    NOW() - INTERVAL '9 days',
    NOW() - INTERVAL '2 days'
);

-- =============================================================================
-- SEED COMPLETE
-- The shipment is now held at Jebel Ali customs.
-- Run 03_demo_customs_hold.sql to walk through the resolution scenario.
-- =============================================================================

-- Summary
DO $$
DECLARE
    task_count INTEGER;
    completed_count INTEGER;
    blocked_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO task_count FROM tasks WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';
    SELECT COUNT(*) INTO completed_count FROM tasks WHERE shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01' AND status = 'completed';
    SELECT COUNT(*) INTO blocked_count FROM tasks t
        WHERE t.shipment_id = 'sh0eebc99-9c0b-4ef8-bb6d-6bb9bd380a01'
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
