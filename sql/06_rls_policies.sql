-- =============================================================================
-- Row-Level Security Policies
-- Multi-tenant isolation for all tenant-owned data
-- =============================================================================

-- Helper function: fail loud when session variable is unset
CREATE OR REPLACE FUNCTION current_company_id()
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v TEXT := NULLIF(current_setting('app.company_id', true), '');
BEGIN
    IF v IS NULL THEN
        RAISE EXCEPTION 'app.company_id is not set for this session'
            USING HINT = 'The application must SET app.company_id before querying tenant data.';
    END IF;
    RETURN v::BIGINT;
END;
$$;

COMMENT ON FUNCTION current_company_id() IS
'Returns the current tenant ID from session variable.
Raises clear exception if unset. Used by all RLS policies.';

-- =============================================================================
-- DIRECT TENANT TABLES (30 tables with required company_id)
-- Policy: company_id = current_company_id()
-- =============================================================================

-- Pattern: ALTER TABLE ... ENABLE/FORCE RLS, CREATE POLICY with USING + WITH CHECK

ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON shipments
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contracts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contracts
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tasks
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON users
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON branches
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON departments
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON roles
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE parties FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON parties
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON locations
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON products
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_categories FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON product_categories
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE contract_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_types FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contract_types
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE workflow_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON workflow_templates
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE warehouses ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON warehouses
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON vehicles
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON drivers
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON workers
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE transport_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE transport_orders FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON transport_orders
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE handling_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE handling_operations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON handling_operations
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE customs_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE customs_declarations FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON customs_declarations
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE deliveries FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON deliveries
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON documents
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_types FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON document_types
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON incidents
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoices
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON payments
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE shipment_financials ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_financials FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON shipment_financials
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE cost_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_categories FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON cost_categories
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_movements FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON inventory_movements
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit_log
    USING (company_id = current_company_id())
    WITH CHECK (company_id = current_company_id());

-- =============================================================================
-- CHILD TABLES (via parent FK join)
-- Policy: EXISTS (SELECT 1 FROM parent WHERE parent.id = child.parent_id AND parent.company_id = current_company_id())
-- =============================================================================

-- shipment children
ALTER TABLE shipment_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_stages FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON shipment_stages
    USING (EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_stages.shipment_id AND s.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_stages.shipment_id AND s.company_id = current_company_id()));

ALTER TABLE shipment_cargo_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipment_cargo_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON shipment_cargo_lines
    USING (EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_cargo_lines.shipment_id AND s.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM shipments s WHERE s.id = shipment_cargo_lines.shipment_id AND s.company_id = current_company_id()));

ALTER TABLE tracking_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_events FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tracking_events
    USING (EXISTS (SELECT 1 FROM shipments s WHERE s.id = tracking_events.shipment_id AND s.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM shipments s WHERE s.id = tracking_events.shipment_id AND s.company_id = current_company_id()));

-- task children
ALTER TABLE task_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_assignments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON task_assignments
    USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_assignments.task_id AND t.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_assignments.task_id AND t.company_id = current_company_id()));

ALTER TABLE task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_dependencies FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON task_dependencies
    USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_dependencies.task_id AND t.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_dependencies.task_id AND t.company_id = current_company_id()));

ALTER TABLE task_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_status_history FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON task_status_history
    USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_status_history.task_id AND t.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_status_history.task_id AND t.company_id = current_company_id()));

-- contract children
ALTER TABLE contract_cargo_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_cargo_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contract_cargo_lines
    USING (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_cargo_lines.contract_id AND c.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_cargo_lines.contract_id AND c.company_id = current_company_id()));

ALTER TABLE contract_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_charges FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contract_charges
    USING (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_charges.contract_id AND c.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_charges.contract_id AND c.company_id = current_company_id()));

ALTER TABLE contract_required_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE contract_required_documents FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON contract_required_documents
    USING (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_required_documents.contract_id AND c.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM contracts c WHERE c.id = contract_required_documents.contract_id AND c.company_id = current_company_id()));

-- other children
ALTER TABLE invoice_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON invoice_lines
    USING (EXISTS (SELECT 1 FROM invoices i WHERE i.id = invoice_lines.invoice_id AND i.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM invoices i WHERE i.id = invoice_lines.invoice_id AND i.company_id = current_company_id()));

ALTER TABLE party_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE party_contacts FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON party_contacts
    USING (EXISTS (SELECT 1 FROM parties p WHERE p.id = party_contacts.party_id AND p.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM parties p WHERE p.id = party_contacts.party_id AND p.company_id = current_company_id()));

ALTER TABLE storage_bins ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage_bins FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON storage_bins
    USING (EXISTS (SELECT 1 FROM warehouses w WHERE w.id = storage_bins.warehouse_id AND w.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM warehouses w WHERE w.id = storage_bins.warehouse_id AND w.company_id = current_company_id()));

ALTER TABLE handling_operation_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE handling_operation_lines FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON handling_operation_lines
    USING (EXISTS (SELECT 1 FROM handling_operations h WHERE h.id = handling_operation_lines.handling_operation_id AND h.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM handling_operations h WHERE h.id = handling_operation_lines.handling_operation_id AND h.company_id = current_company_id()));

ALTER TABLE handling_operation_workers ENABLE ROW LEVEL SECURITY;
ALTER TABLE handling_operation_workers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON handling_operation_workers
    USING (EXISTS (SELECT 1 FROM handling_operations h WHERE h.id = handling_operation_workers.handling_operation_id AND h.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM handling_operations h WHERE h.id = handling_operation_workers.handling_operation_id AND h.company_id = current_company_id()));

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON user_roles
    USING (EXISTS (SELECT 1 FROM users u WHERE u.id = user_roles.user_id AND u.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM users u WHERE u.id = user_roles.user_id AND u.company_id = current_company_id()));

ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON role_permissions
    USING (EXISTS (SELECT 1 FROM roles r WHERE r.id = role_permissions.role_id AND r.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM roles r WHERE r.id = role_permissions.role_id AND r.company_id = current_company_id()));

-- workflow template hierarchy
ALTER TABLE stage_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE stage_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON stage_templates
    USING (EXISTS (SELECT 1 FROM workflow_templates w WHERE w.id = stage_templates.workflow_template_id AND w.company_id = current_company_id()))
    WITH CHECK (EXISTS (SELECT 1 FROM workflow_templates w WHERE w.id = stage_templates.workflow_template_id AND w.company_id = current_company_id()));

ALTER TABLE task_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_templates FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON task_templates
    USING (EXISTS (
        SELECT 1 FROM stage_templates st
        JOIN workflow_templates w ON w.id = st.workflow_template_id
        WHERE st.id = task_templates.stage_template_id AND w.company_id = current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM stage_templates st
        JOIN workflow_templates w ON w.id = st.workflow_template_id
        WHERE st.id = task_templates.stage_template_id AND w.company_id = current_company_id()
    ));

ALTER TABLE task_template_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_template_dependencies FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON task_template_dependencies
    USING (EXISTS (
        SELECT 1 FROM task_templates tt
        JOIN stage_templates st ON st.id = tt.stage_template_id
        JOIN workflow_templates w ON w.id = st.workflow_template_id
        WHERE tt.id = task_template_dependencies.task_template_id AND w.company_id = current_company_id()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM task_templates tt
        JOIN stage_templates st ON st.id = tt.stage_template_id
        JOIN workflow_templates w ON w.id = st.workflow_template_id
        WHERE tt.id = task_template_dependencies.task_template_id AND w.company_id = current_company_id()
    ));

-- =============================================================================
-- INDEXES FOR RLS POLICY JOIN COLUMNS
-- Child tables need indexes on FK columns used in policy EXISTS subqueries
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_contract_charges_contract_id ON contract_charges(contract_id);
CREATE INDEX IF NOT EXISTS idx_handling_operation_lines_op_id ON handling_operation_lines(handling_operation_id);
CREATE INDEX IF NOT EXISTS idx_party_contacts_party_id ON party_contacts(party_id);
CREATE INDEX IF NOT EXISTS idx_task_assignments_task_id ON task_assignments(task_id);

-- =============================================================================
-- COMPANIES TABLE
-- Users can only see their own company
-- =============================================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE companies FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON companies
    USING (id = current_company_id())
    WITH CHECK (id = current_company_id());

-- =============================================================================
-- REFERENCE TABLES (no RLS, SELECT-only grants)
-- These are global data that all tenants can read but not write
-- =============================================================================

-- Revoke write permissions from application role
REVOKE INSERT, UPDATE, DELETE ON countries FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON currencies FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON customs_unions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON country_customs_unions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON incident_types FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON location_types FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON permissions FROM authenticated;

-- Ensure read access
GRANT SELECT ON countries TO authenticated;
GRANT SELECT ON currencies TO authenticated;
GRANT SELECT ON customs_unions TO authenticated;
GRANT SELECT ON country_customs_unions TO authenticated;
GRANT SELECT ON incident_types TO authenticated;
GRANT SELECT ON location_types TO authenticated;
GRANT SELECT ON permissions TO authenticated;

-- =============================================================================
-- USAGE NOTES
-- =============================================================================
--
-- APPLICATION MUST SET TENANT BEFORE QUERIES:
--   SET app.company_id = '123';
--   -- or --
--   SELECT set_config('app.company_id', '123', FALSE);
--
-- ROLE BEHAVIOR:
--   - authenticated: Subject to all RLS policies (use for user-facing queries)
--   - anon: Subject to all RLS policies
--   - service_role: BYPASSES RLS (use only for admin/migration tasks)
--   - postgres: BYPASSES RLS (superuser)
--
-- CRITICAL: Never use service_role key for user-facing API calls.
-- The Supabase client defaults to anon key, which is correct.
-- service_role should only be used server-side for:
--   - Database migrations
--   - Admin operations
--   - Background jobs that need cross-tenant access
--
-- BACKGROUND JOBS should either:
--   1. Set app.company_id explicitly (runs as single tenant)
--   2. Connect as service_role (bypasses RLS for cross-tenant work)
--
-- =============================================================================
