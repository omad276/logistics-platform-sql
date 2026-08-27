-- =====================================================================
--  LOGISTICS OPERATIONS MANAGEMENT & TASK DISPATCH PLATFORM
--  Database schema  |  PostgreSQL 14+
--  Author: Esmail Salah
-- ---------------------------------------------------------------------
--  Door-to-door logistics execution: contract -> shipment -> workflow
--  -> stages -> tasks, with transport, customs, warehousing, handling,
--  documents, incidents and shipment-level profitability.
--
--  Conventions
--    * snake_case, plural table names, surrogate BIGSERIAL keys
--    * every tenant-owned row carries company_id (multi-tenant by design)
--    * money is NUMERIC(14,2) + ISO currency code -- never floating point
--    * lifecycle states are ENUMs; business taxonomies are lookup TABLES
--    * timestamps are TIMESTAMPTZ, stored UTC
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================================================
--  SECTION 0 :: ENUMERATED LIFECYCLE STATES
--  These are state machines, not configuration. They are deliberately
--  ENUMs so that invalid states cannot be inserted at all.
-- =====================================================================

CREATE TYPE transport_mode      AS ENUM ('sea','air','road','rail','multimodal');
CREATE TYPE contract_status     AS ENUM ('draft','pending_approval','approved','active','completed','cancelled');
CREATE TYPE shipment_status     AS ENUM ('created','planned','in_progress','on_hold','delivered','closed','cancelled');
CREATE TYPE stage_status        AS ENUM ('pending','active','completed','skipped','cancelled');

-- Task lifecycle per spec s.7: Created -> Assigned -> Scheduled ->
-- In Progress -> Waiting -> Completed -> Closed, plus Failed / Cancelled.
CREATE TYPE task_status         AS ENUM ('created','assigned','scheduled','in_progress','waiting','completed','closed','failed','cancelled');
CREATE TYPE priority_level      AS ENUM ('low','normal','high','urgent');

CREATE TYPE vehicle_status      AS ENUM ('available','on_mission','maintenance','unavailable');
CREATE TYPE transport_status    AS ENUM ('planned','assigned','dispatched','in_transit','arrived','completed','cancelled');

CREATE TYPE handling_type       AS ENUM ('loading','unloading','transloading','stuffing','destuffing');
CREATE TYPE cargo_condition     AS ENUM ('good','damaged','partially_damaged','wet','temperature_breach','tampered');

CREATE TYPE customs_status      AS ENUM ('not_started','documents_pending','submitted','under_inspection','held','cleared','rejected');
CREATE TYPE document_status     AS ENUM ('required','uploaded','verified','rejected','expired');

CREATE TYPE incident_severity   AS ENUM ('low','medium','high','critical');
CREATE TYPE incident_status     AS ENUM ('open','under_investigation','action_taken','resolved','closed');

CREATE TYPE movement_type       AS ENUM ('receipt','put_away','internal_move','pick','dispatch','adjustment');
CREATE TYPE cost_direction      AS ENUM ('cost','revenue');
CREATE TYPE entry_type          AS ENUM ('charge','credit','adjustment');
CREATE TYPE invoice_status      AS ENUM ('draft','issued','partially_paid','paid','overdue','cancelled');
CREATE TYPE invoice_direction   AS ENUM ('receivable','payable');
CREATE TYPE assignee_type       AS ENUM ('user','driver','worker','vendor','department');

-- =====================================================================
--  SECTION 1 :: COMPANY, BRANCH, DEPARTMENT
-- =====================================================================

CREATE TABLE companies (
    id                  BIGSERIAL PRIMARY KEY,
    legal_name          VARCHAR(200) NOT NULL,
    trade_name          VARCHAR(200),
    registration_no     VARCHAR(80),
    tax_no              VARCHAR(80),
    base_currency       CHAR(3)      NOT NULL DEFAULT 'AED',
    country_code        CHAR(2)      NOT NULL,
    timezone            VARCHAR(60)  NOT NULL DEFAULT 'Asia/Dubai',
    logo_url            TEXT,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE branches (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(20)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    country_code        CHAR(2),
    city                VARCHAR(100),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, code)
);

CREATE TABLE departments (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    branch_id           BIGINT       REFERENCES branches(id) ON DELETE SET NULL,
    parent_id           BIGINT       REFERENCES departments(id) ON DELETE SET NULL,
    code                VARCHAR(30)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, code),
    CONSTRAINT departments_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

-- =====================================================================
--  SECTION 2 :: USERS, ROLES, PERMISSIONS
-- =====================================================================

CREATE TABLE users (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    branch_id           BIGINT       REFERENCES branches(id) ON DELETE SET NULL,
    department_id       BIGINT       REFERENCES departments(id) ON DELETE SET NULL,
    employee_no         VARCHAR(40),
    full_name           VARCHAR(150) NOT NULL,
    email               VARCHAR(190) NOT NULL,
    phone               VARCHAR(30),
    password_hash       TEXT         NOT NULL,
    locale              VARCHAR(10)  NOT NULL DEFAULT 'en',
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    last_login_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, email)
);

CREATE TABLE roles (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(50)  NOT NULL,
    name                VARCHAR(120) NOT NULL,
    description         TEXT,
    is_system           BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (company_id, code)
);

CREATE TABLE permissions (
    id                  BIGSERIAL PRIMARY KEY,
    module              VARCHAR(60)  NOT NULL,
    action              VARCHAR(30)  NOT NULL,
    description         TEXT,
    UNIQUE (module, action)
);

CREATE TABLE role_permissions (
    role_id             BIGINT       NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id       BIGINT       NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id             BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id             BIGINT       NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    branch_id           BIGINT       REFERENCES branches(id) ON DELETE CASCADE,
    granted_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_users_company        ON users(company_id) WHERE is_active;
CREATE INDEX idx_departments_parent   ON departments(parent_id);

-- =====================================================================
--  SECTION 3 :: BUSINESS PARTIES
-- =====================================================================

CREATE TABLE parties (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(30)  NOT NULL,
    legal_name          VARCHAR(200) NOT NULL,
    trade_name          VARCHAR(200),
    tax_no              VARCHAR(80),
    country_code        CHAR(2)      NOT NULL,
    city                VARCHAR(100),
    address_line        TEXT,
    phone               VARCHAR(30),
    email               VARCHAR(190),
    is_customer         BOOLEAN      NOT NULL DEFAULT FALSE,
    is_seller           BOOLEAN      NOT NULL DEFAULT FALSE,
    is_buyer            BOOLEAN      NOT NULL DEFAULT FALSE,
    is_carrier          BOOLEAN      NOT NULL DEFAULT FALSE,
    is_customs_broker   BOOLEAN      NOT NULL DEFAULT FALSE,
    is_vendor           BOOLEAN      NOT NULL DEFAULT FALSE,
    credit_limit        NUMERIC(14,2),
    payment_terms_days  SMALLINT     NOT NULL DEFAULT 0,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, code),
    CONSTRAINT parties_has_a_role CHECK (
        is_customer OR is_seller OR is_buyer OR is_carrier OR is_customs_broker OR is_vendor
    )
);

CREATE TABLE party_contacts (
    id                  BIGSERIAL PRIMARY KEY,
    party_id            BIGINT       NOT NULL REFERENCES parties(id) ON DELETE CASCADE,
    full_name           VARCHAR(150) NOT NULL,
    job_title           VARCHAR(120),
    phone               VARCHAR(30),
    email               VARCHAR(190),
    is_primary          BOOLEAN      NOT NULL DEFAULT FALSE
);

-- =====================================================================
--  SECTION 4 :: LOCATIONS
-- =====================================================================

CREATE TABLE location_types (
    id                  SMALLSERIAL PRIMARY KEY,
    code                VARCHAR(30)  NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL
);

CREATE TABLE locations (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    location_type_id    SMALLINT     NOT NULL REFERENCES location_types(id),
    party_id            BIGINT       REFERENCES parties(id) ON DELETE SET NULL,
    code                VARCHAR(30),
    name                VARCHAR(180) NOT NULL,
    unlocode            CHAR(5),
    country_code        CHAR(2)      NOT NULL,
    city                VARCHAR(100),
    address_line        TEXT,
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    contact_name        VARCHAR(150),
    contact_phone       VARCHAR(30),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, code)
);

CREATE INDEX idx_locations_unlocode ON locations(unlocode);

-- =====================================================================
--  SECTION 5 :: PRODUCTS AND CARGO TYPES
-- =====================================================================

CREATE TABLE product_categories (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(30)  NOT NULL,
    name                VARCHAR(120) NOT NULL,
    requires_temp_control   BOOLEAN  NOT NULL DEFAULT FALSE,
    is_hazardous            BOOLEAN  NOT NULL DEFAULT FALSE,
    requires_phytosanitary  BOOLEAN  NOT NULL DEFAULT FALSE,
    requires_health_cert    BOOLEAN  NOT NULL DEFAULT FALSE,
    is_oversized            BOOLEAN  NOT NULL DEFAULT FALSE,
    UNIQUE (company_id, code)
);

CREATE TABLE products (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    category_id         BIGINT       NOT NULL REFERENCES product_categories(id),
    sku                 VARCHAR(60)  NOT NULL,
    name                VARCHAR(200) NOT NULL,
    hs_code             VARCHAR(20),
    uom                 VARCHAR(20)  NOT NULL DEFAULT 'KG',
    unit_weight_kg      NUMERIC(12,3),
    unit_volume_cbm     NUMERIC(12,4),
    min_temp_c          NUMERIC(5,2),
    max_temp_c          NUMERIC(5,2),
    shelf_life_days     INTEGER,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, sku),
    CONSTRAINT products_temp_range CHECK (
        min_temp_c IS NULL OR max_temp_c IS NULL OR min_temp_c <= max_temp_c
    )
);

-- =====================================================================
--  SECTION 6 :: DOCUMENT TYPES
-- =====================================================================

CREATE TABLE document_types (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    is_customs_document BOOLEAN      NOT NULL DEFAULT FALSE,
    has_expiry          BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (company_id, code)
);

-- =====================================================================
--  SECTION 7 :: CONTRACT TYPES
-- =====================================================================

CREATE TABLE contract_types (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    default_mode        transport_mode NOT NULL DEFAULT 'road',
    origin_is_door      BOOLEAN      NOT NULL DEFAULT TRUE,
    destination_is_door BOOLEAN      NOT NULL DEFAULT TRUE,
    is_international    BOOLEAN      NOT NULL DEFAULT FALSE,
    involves_customs    BOOLEAN      NOT NULL DEFAULT FALSE,
    involves_warehouse  BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, code)
);

-- =====================================================================
--  SECTION 8 :: CONTRACTS
-- =====================================================================

CREATE TABLE contracts (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    branch_id           BIGINT       REFERENCES branches(id) ON DELETE SET NULL,
    contract_no         VARCHAR(50)  NOT NULL,
    contract_type_id    BIGINT       NOT NULL REFERENCES contract_types(id),
    status              contract_status NOT NULL DEFAULT 'draft',

    customer_id         BIGINT       NOT NULL REFERENCES parties(id),
    seller_id           BIGINT       NOT NULL REFERENCES parties(id),
    buyer_id            BIGINT       NOT NULL REFERENCES parties(id),

    origin_location_id      BIGINT   NOT NULL REFERENCES locations(id),
    destination_location_id BIGINT   NOT NULL REFERENCES locations(id),
    primary_mode        transport_mode NOT NULL,

    incoterm            VARCHAR(11),
    responsibilities    TEXT,
    delivery_terms      TEXT,

    contract_value      NUMERIC(14,2) NOT NULL DEFAULT 0,
    currency            CHAR(3)       NOT NULL DEFAULT 'AED',
    insurance_required  BOOLEAN       NOT NULL DEFAULT FALSE,
    insurance_value     NUMERIC(14,2),
    payment_terms_days  SMALLINT      NOT NULL DEFAULT 0,
    payment_terms_note  TEXT,

    valid_from          DATE          NOT NULL,
    valid_to            DATE,
    execution_days      SMALLINT,

    notes               TEXT,
    approved_by         BIGINT        REFERENCES users(id),
    approved_at         TIMESTAMPTZ,
    created_by          BIGINT        REFERENCES users(id),
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),

    UNIQUE (company_id, contract_no),
    CONSTRAINT contracts_route_differs CHECK (origin_location_id <> destination_location_id),
    CONSTRAINT contracts_validity      CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT contracts_value_sign    CHECK (contract_value >= 0),
    CONSTRAINT contracts_approval_trail CHECK (
        status NOT IN ('approved','active','completed')
        OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
    )
);

CREATE INDEX idx_contracts_customer ON contracts(customer_id);
CREATE INDEX idx_contracts_status   ON contracts(company_id, status);

CREATE TABLE contract_cargo_lines (
    id                  BIGSERIAL PRIMARY KEY,
    contract_id         BIGINT       NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    line_no             SMALLINT     NOT NULL,
    product_id          BIGINT       NOT NULL REFERENCES products(id),
    description         TEXT,
    quantity            NUMERIC(14,3) NOT NULL,
    uom                 VARCHAR(20)   NOT NULL,
    gross_weight_kg     NUMERIC(14,3),
    net_weight_kg       NUMERIC(14,3),
    volume_cbm          NUMERIC(14,4),
    package_count       INTEGER,
    package_type        VARCHAR(40),
    declared_value      NUMERIC(14,2),
    UNIQUE (contract_id, line_no),
    CONSTRAINT contract_cargo_qty_positive CHECK (quantity > 0),
    CONSTRAINT contract_cargo_weight_order CHECK (
        net_weight_kg IS NULL OR gross_weight_kg IS NULL OR net_weight_kg <= gross_weight_kg
    )
);

CREATE TABLE contract_charges (
    id                  BIGSERIAL PRIMARY KEY,
    contract_id         BIGINT       NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    charge_code         VARCHAR(40)  NOT NULL,
    description         VARCHAR(200),
    amount              NUMERIC(14,2) NOT NULL,
    currency            CHAR(3)       NOT NULL,
    is_pass_through     BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT contract_charges_amount CHECK (amount >= 0)
);

CREATE TABLE contract_required_documents (
    contract_id         BIGINT       NOT NULL REFERENCES contracts(id) ON DELETE CASCADE,
    document_type_id    BIGINT       NOT NULL REFERENCES document_types(id),
    responsible_party   VARCHAR(20)  NOT NULL DEFAULT 'company',
    PRIMARY KEY (contract_id, document_type_id)
);

-- =====================================================================
--  SECTION 9 :: WORKFLOW TEMPLATE ENGINE
-- =====================================================================

CREATE TABLE workflow_templates (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    contract_type_id    BIGINT       NOT NULL REFERENCES contract_types(id) ON DELETE CASCADE,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    version             SMALLINT     NOT NULL DEFAULT 1,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, code, version)
);

CREATE UNIQUE INDEX uq_workflow_active_per_type
    ON workflow_templates(contract_type_id) WHERE is_active;

CREATE TABLE stage_templates (
    id                  BIGSERIAL PRIMARY KEY,
    workflow_template_id BIGINT      NOT NULL REFERENCES workflow_templates(id) ON DELETE CASCADE,
    sequence_no         SMALLINT     NOT NULL,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    is_optional         BOOLEAN      NOT NULL DEFAULT FALSE,
    skip_if_no_warehouse BOOLEAN     NOT NULL DEFAULT FALSE,
    skip_if_domestic     BOOLEAN     NOT NULL DEFAULT FALSE,
    UNIQUE (workflow_template_id, sequence_no),
    UNIQUE (workflow_template_id, code)
);

CREATE TABLE task_templates (
    id                  BIGSERIAL PRIMARY KEY,
    stage_template_id   BIGINT       NOT NULL REFERENCES stage_templates(id) ON DELETE CASCADE,
    sequence_no         SMALLINT     NOT NULL,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(180) NOT NULL,
    description         TEXT,
    default_department_id BIGINT     REFERENCES departments(id) ON DELETE SET NULL,
    default_priority    priority_level NOT NULL DEFAULT 'normal',
    offset_hours        INTEGER      NOT NULL DEFAULT 0,
    duration_hours      INTEGER      NOT NULL DEFAULT 4,
    requires_document   BOOLEAN      NOT NULL DEFAULT FALSE,
    required_document_type_id BIGINT REFERENCES document_types(id) ON DELETE SET NULL,
    requires_signature  BOOLEAN      NOT NULL DEFAULT FALSE,
    requires_photo      BOOLEAN      NOT NULL DEFAULT FALSE,
    blocks_shipment_on_failure BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (stage_template_id, code),
    CONSTRAINT task_templates_duration CHECK (duration_hours > 0),
    CONSTRAINT task_templates_doc_rule CHECK (
        NOT requires_document OR required_document_type_id IS NOT NULL
    )
);

CREATE TABLE task_template_dependencies (
    task_template_id        BIGINT NOT NULL REFERENCES task_templates(id) ON DELETE CASCADE,
    depends_on_template_id  BIGINT NOT NULL REFERENCES task_templates(id) ON DELETE CASCADE,
    PRIMARY KEY (task_template_id, depends_on_template_id),
    CONSTRAINT task_template_dep_no_self CHECK (task_template_id <> depends_on_template_id)
);

-- =====================================================================
--  SECTION 10 :: SHIPMENTS
-- =====================================================================

CREATE TABLE shipments (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    contract_id         BIGINT       NOT NULL REFERENCES contracts(id),
    workflow_template_id BIGINT      REFERENCES workflow_templates(id),
    shipment_no         VARCHAR(50)  NOT NULL,
    tracking_no         VARCHAR(40)  NOT NULL,
    status              shipment_status NOT NULL DEFAULT 'created',
    priority            priority_level  NOT NULL DEFAULT 'normal',

    origin_location_id      BIGINT   NOT NULL REFERENCES locations(id),
    destination_location_id BIGINT   NOT NULL REFERENCES locations(id),
    current_location_id     BIGINT   REFERENCES locations(id),
    current_stage_id        BIGINT,

    total_gross_weight_kg NUMERIC(14,3),
    total_volume_cbm      NUMERIC(14,4),
    total_packages        INTEGER,
    container_no          VARCHAR(20),
    seal_no               VARCHAR(30),

    planned_pickup_at   TIMESTAMPTZ,
    actual_pickup_at    TIMESTAMPTZ,
    planned_delivery_at TIMESTAMPTZ,
    actual_delivery_at  TIMESTAMPTZ,
    closed_at           TIMESTAMPTZ,

    created_by          BIGINT       REFERENCES users(id),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (company_id, shipment_no),
    UNIQUE (tracking_no),
    CONSTRAINT shipments_route_differs CHECK (origin_location_id <> destination_location_id),
    CONSTRAINT shipments_delivery_after_pickup CHECK (
        actual_delivery_at IS NULL OR actual_pickup_at IS NULL
        OR actual_delivery_at >= actual_pickup_at
    ),
    CONSTRAINT shipments_closure_rule CHECK (
        status <> 'closed' OR (actual_delivery_at IS NOT NULL AND closed_at IS NOT NULL)
    )
);

CREATE INDEX idx_shipments_status   ON shipments(company_id, status);
CREATE INDEX idx_shipments_contract ON shipments(contract_id);
CREATE INDEX idx_shipments_open     ON shipments(company_id, planned_delivery_at)
    WHERE status IN ('created','planned','in_progress','on_hold');

CREATE TABLE shipment_cargo_lines (
    id                  BIGSERIAL PRIMARY KEY,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    contract_line_id    BIGINT       REFERENCES contract_cargo_lines(id),
    line_no             SMALLINT     NOT NULL,
    product_id          BIGINT       NOT NULL REFERENCES products(id),
    planned_quantity    NUMERIC(14,3) NOT NULL,
    loaded_quantity     NUMERIC(14,3) NOT NULL DEFAULT 0,
    delivered_quantity  NUMERIC(14,3) NOT NULL DEFAULT 0,
    damaged_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    missing_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    uom                 VARCHAR(20)   NOT NULL,
    gross_weight_kg     NUMERIC(14,3),
    package_count       INTEGER,
    batch_no            VARCHAR(60),
    condition           cargo_condition NOT NULL DEFAULT 'good',
    UNIQUE (shipment_id, line_no),
    CONSTRAINT shipment_cargo_quantities CHECK (
        planned_quantity   > 0
        AND loaded_quantity    >= 0
        AND delivered_quantity >= 0
        AND damaged_quantity   >= 0
        AND missing_quantity   >= 0
        AND delivered_quantity + damaged_quantity + missing_quantity <= loaded_quantity
    )
);

-- =====================================================================
--  SECTION 11 :: INSTANTIATED STAGES AND TASKS
-- =====================================================================

CREATE TABLE shipment_stages (
    id                  BIGSERIAL PRIMARY KEY,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    stage_template_id   BIGINT       REFERENCES stage_templates(id),
    sequence_no         SMALLINT     NOT NULL,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    status              stage_status NOT NULL DEFAULT 'pending',
    location_id         BIGINT       REFERENCES locations(id),
    planned_start_at    TIMESTAMPTZ,
    planned_end_at      TIMESTAMPTZ,
    actual_start_at     TIMESTAMPTZ,
    actual_end_at       TIMESTAMPTZ,
    UNIQUE (shipment_id, sequence_no)
);

ALTER TABLE shipments
    ADD CONSTRAINT shipments_current_stage_fk
    FOREIGN KEY (current_stage_id) REFERENCES shipment_stages(id) ON DELETE SET NULL;

CREATE TABLE tasks (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    stage_id            BIGINT       NOT NULL REFERENCES shipment_stages(id) ON DELETE CASCADE,
    task_template_id    BIGINT       REFERENCES task_templates(id),
    task_no             VARCHAR(40)  NOT NULL,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(180) NOT NULL,
    description         TEXT,

    status              task_status    NOT NULL DEFAULT 'created',
    priority            priority_level NOT NULL DEFAULT 'normal',

    department_id       BIGINT       REFERENCES departments(id) ON DELETE SET NULL,
    assigned_to_user_id BIGINT       REFERENCES users(id) ON DELETE SET NULL,

    scheduled_start_at  TIMESTAMPTZ,
    scheduled_end_at    TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    closed_at           TIMESTAMPTZ,

    requires_document   BOOLEAN      NOT NULL DEFAULT FALSE,
    requires_signature  BOOLEAN      NOT NULL DEFAULT FALSE,
    requires_photo      BOOLEAN      NOT NULL DEFAULT FALSE,
    blocks_shipment_on_failure BOOLEAN NOT NULL DEFAULT FALSE,

    hold_reason         TEXT,
    notes               TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (company_id, task_no),
    CONSTRAINT tasks_schedule_order CHECK (
        scheduled_end_at IS NULL OR scheduled_start_at IS NULL
        OR scheduled_end_at >= scheduled_start_at
    ),
    CONSTRAINT tasks_completion_order CHECK (
        completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at
    ),
    CONSTRAINT tasks_assignment_rule CHECK (
        status IN ('created','cancelled')
        OR assigned_to_user_id IS NOT NULL
        OR department_id IS NOT NULL
    ),
    CONSTRAINT tasks_completed_stamp CHECK (
        status NOT IN ('completed','closed') OR completed_at IS NOT NULL
    ),
    CONSTRAINT tasks_hold_reason CHECK (
        status <> 'waiting' OR hold_reason IS NOT NULL
    )
);

CREATE INDEX idx_tasks_dispatch ON tasks(company_id, status, scheduled_start_at)
    WHERE status IN ('created','assigned','scheduled','in_progress','waiting');
CREATE INDEX idx_tasks_assignee ON tasks(assigned_to_user_id, status);
CREATE INDEX idx_tasks_shipment ON tasks(shipment_id);
CREATE INDEX idx_tasks_department ON tasks(department_id, status);

CREATE TABLE task_dependencies (
    task_id             BIGINT       NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on_task_id  BIGINT       NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, depends_on_task_id),
    CONSTRAINT task_dep_no_self CHECK (task_id <> depends_on_task_id)
);

CREATE INDEX idx_task_dependencies_reverse ON task_dependencies(depends_on_task_id);

CREATE TABLE task_status_history (
    id                  BIGSERIAL PRIMARY KEY,
    task_id             BIGINT       NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    from_status         task_status,
    to_status           task_status  NOT NULL,
    changed_by          BIGINT       REFERENCES users(id),
    changed_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    reason              TEXT,
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    CONSTRAINT task_status_history_changed CHECK (from_status IS DISTINCT FROM to_status)
);

CREATE INDEX idx_task_history_task ON task_status_history(task_id, changed_at DESC);

CREATE TABLE task_assignments (
    id                  BIGSERIAL PRIMARY KEY,
    task_id             BIGINT       NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    assignee_type       assignee_type NOT NULL,
    assignee_id         BIGINT       NOT NULL,
    is_primary          BOOLEAN      NOT NULL DEFAULT TRUE,
    assigned_by         BIGINT       REFERENCES users(id),
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    accepted_at         TIMESTAMPTZ
);

CREATE INDEX idx_task_assignments_lookup ON task_assignments(assignee_type, assignee_id);

-- =====================================================================
--  SECTION 12 :: FLEET, DRIVERS, WORKERS
-- =====================================================================

CREATE TABLE vehicles (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    branch_id           BIGINT       REFERENCES branches(id) ON DELETE SET NULL,
    owner_party_id      BIGINT       REFERENCES parties(id),
    plate_no            VARCHAR(30)  NOT NULL,
    vehicle_type        VARCHAR(40)  NOT NULL,
    make_model          VARCHAR(120),
    year_of_manufacture SMALLINT,
    capacity_kg         NUMERIC(12,2),
    capacity_cbm        NUMERIC(12,3),
    has_temp_control    BOOLEAN      NOT NULL DEFAULT FALSE,
    status              vehicle_status NOT NULL DEFAULT 'available',
    registration_expiry DATE,
    insurance_expiry    DATE,
    last_service_at     DATE,
    odometer_km         INTEGER,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, plate_no)
);

CREATE INDEX idx_vehicles_available ON vehicles(company_id, status) WHERE is_active;

CREATE TABLE drivers (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id             BIGINT       REFERENCES users(id) ON DELETE SET NULL,
    employee_no         VARCHAR(40),
    full_name           VARCHAR(150) NOT NULL,
    phone               VARCHAR(30)  NOT NULL,
    national_id         VARCHAR(40),
    licence_no          VARCHAR(40)  NOT NULL,
    licence_class       VARCHAR(20),
    licence_expiry      DATE         NOT NULL,
    has_hazmat_permit   BOOLEAN      NOT NULL DEFAULT FALSE,
    vendor_party_id     BIGINT       REFERENCES parties(id),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, licence_no)
);

CREATE TABLE workers (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    full_name           VARCHAR(150) NOT NULL,
    phone               VARCHAR(30),
    role_label          VARCHAR(60),
    is_daily_wage       BOOLEAN      NOT NULL DEFAULT FALSE,
    vendor_party_id     BIGINT       REFERENCES parties(id),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE
);

-- =====================================================================
--  SECTION 13 :: TRANSPORT ORDERS
-- =====================================================================

CREATE TABLE transport_orders (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    stage_id            BIGINT       REFERENCES shipment_stages(id) ON DELETE SET NULL,
    order_no            VARCHAR(40)  NOT NULL,
    leg_no              SMALLINT     NOT NULL DEFAULT 1,
    mode                transport_mode NOT NULL,
    status              transport_status NOT NULL DEFAULT 'planned',

    origin_location_id      BIGINT   NOT NULL REFERENCES locations(id),
    destination_location_id BIGINT   NOT NULL REFERENCES locations(id),

    vehicle_id          BIGINT       REFERENCES vehicles(id),
    driver_id           BIGINT       REFERENCES drivers(id),
    carrier_party_id    BIGINT       REFERENCES parties(id),
    vessel_or_flight_no VARCHAR(60),
    bill_of_lading_no   VARCHAR(60),
    container_no        VARCHAR(20),

    cargo_description   TEXT,
    distance_km         NUMERIC(10,2),
    scheduled_departure TIMESTAMPTZ,
    scheduled_arrival   TIMESTAMPTZ,
    actual_departure    TIMESTAMPTZ,
    actual_arrival      TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (company_id, order_no),
    UNIQUE (shipment_id, leg_no),
    CONSTRAINT transport_route_differs CHECK (origin_location_id <> destination_location_id),
    CONSTRAINT transport_arrival_order CHECK (
        actual_arrival IS NULL OR actual_departure IS NULL OR actual_arrival >= actual_departure
    ),
    CONSTRAINT transport_resource_rule CHECK (
        status IN ('planned','cancelled')
        OR (mode IN ('road','rail') AND vehicle_id IS NOT NULL AND driver_id IS NOT NULL)
        OR (mode IN ('sea','air','multimodal') AND carrier_party_id IS NOT NULL)
    )
);

CREATE INDEX idx_transport_shipment ON transport_orders(shipment_id);
CREATE INDEX idx_transport_vehicle  ON transport_orders(vehicle_id, status);

-- =====================================================================
--  SECTION 14 :: LOADING & UNLOADING
-- =====================================================================

CREATE TABLE handling_operations (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE SET NULL,
    transport_order_id  BIGINT       REFERENCES transport_orders(id) ON DELETE SET NULL,
    operation_no        VARCHAR(40)  NOT NULL,
    handling_type       handling_type NOT NULL,
    location_id         BIGINT       NOT NULL REFERENCES locations(id),
    vehicle_id          BIGINT       REFERENCES vehicles(id),
    driver_id           BIGINT       REFERENCES drivers(id),
    supervisor_user_id  BIGINT       REFERENCES users(id),

    arrived_at          TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    total_quantity      NUMERIC(14,3),
    total_weight_kg     NUMERIC(14,3),
    damaged_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    missing_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    cargo_condition     cargo_condition NOT NULL DEFAULT 'good',
    remarks             TEXT,
    signatory_name      VARCHAR(150),
    signature_url       TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),

    UNIQUE (company_id, operation_no),
    CONSTRAINT handling_time_order CHECK (
        (started_at   IS NULL OR arrived_at IS NULL OR started_at   >= arrived_at) AND
        (completed_at IS NULL OR started_at IS NULL OR completed_at >= started_at)
    ),
    CONSTRAINT handling_discrepancy_needs_remark CHECK (
        (damaged_quantity = 0 AND missing_quantity = 0) OR remarks IS NOT NULL
    )
);

CREATE INDEX idx_handling_shipment ON handling_operations(shipment_id, handling_type);

CREATE TABLE handling_operation_lines (
    id                  BIGSERIAL PRIMARY KEY,
    handling_operation_id BIGINT     NOT NULL REFERENCES handling_operations(id) ON DELETE CASCADE,
    shipment_cargo_line_id BIGINT    NOT NULL REFERENCES shipment_cargo_lines(id),
    expected_quantity   NUMERIC(14,3) NOT NULL,
    actual_quantity     NUMERIC(14,3) NOT NULL,
    damaged_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    missing_quantity    NUMERIC(14,3) NOT NULL DEFAULT 0,
    condition           cargo_condition NOT NULL DEFAULT 'good',
    remarks             TEXT,
    CONSTRAINT handling_line_quantities CHECK (
        expected_quantity >= 0 AND actual_quantity >= 0
        AND damaged_quantity >= 0 AND missing_quantity >= 0
    )
);

CREATE TABLE handling_operation_workers (
    handling_operation_id BIGINT     NOT NULL REFERENCES handling_operations(id) ON DELETE CASCADE,
    worker_id           BIGINT       NOT NULL REFERENCES workers(id),
    hours_worked        NUMERIC(5,2),
    PRIMARY KEY (handling_operation_id, worker_id)
);

-- =====================================================================
--  SECTION 15 :: WAREHOUSING
-- =====================================================================

CREATE TABLE warehouses (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    location_id         BIGINT       NOT NULL REFERENCES locations(id),
    code                VARCHAR(30)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    is_bonded           BOOLEAN      NOT NULL DEFAULT FALSE,
    has_temp_control    BOOLEAN      NOT NULL DEFAULT FALSE,
    capacity_cbm        NUMERIC(12,2),
    manager_user_id     BIGINT       REFERENCES users(id),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, code)
);

CREATE TABLE storage_bins (
    id                  BIGSERIAL PRIMARY KEY,
    warehouse_id        BIGINT       NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
    code                VARCHAR(40)  NOT NULL,
    zone                VARCHAR(30),
    capacity_cbm        NUMERIC(10,3),
    is_blocked          BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (warehouse_id, code)
);

CREATE TABLE inventory_movements (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    warehouse_id        BIGINT       NOT NULL REFERENCES warehouses(id),
    shipment_id         BIGINT       REFERENCES shipments(id) ON DELETE SET NULL,
    shipment_cargo_line_id BIGINT    REFERENCES shipment_cargo_lines(id) ON DELETE SET NULL,
    product_id          BIGINT       NOT NULL REFERENCES products(id),
    movement_type       movement_type NOT NULL,
    from_bin_id         BIGINT       REFERENCES storage_bins(id),
    to_bin_id           BIGINT       REFERENCES storage_bins(id),
    quantity            NUMERIC(14,3) NOT NULL,
    uom                 VARCHAR(20)   NOT NULL,
    batch_no            VARCHAR(60),
    condition           cargo_condition NOT NULL DEFAULT 'good',
    moved_by            BIGINT       REFERENCES users(id),
    moved_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    reference_no        VARCHAR(60),
    remarks             TEXT,
    CONSTRAINT inventory_quantity_nonzero CHECK (quantity <> 0),
    CONSTRAINT inventory_direction_rule CHECK (
        (movement_type = 'receipt'   AND quantity > 0) OR
        (movement_type = 'dispatch'  AND quantity < 0) OR
        (movement_type IN ('put_away','internal_move','pick','adjustment'))
    )
);

CREATE INDEX idx_inventory_stock ON inventory_movements(warehouse_id, product_id, batch_no);
CREATE INDEX idx_inventory_shipment ON inventory_movements(shipment_id);

-- =====================================================================
--  SECTION 16 :: CUSTOMS
-- =====================================================================

CREATE TABLE customs_declarations (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    stage_id            BIGINT       REFERENCES shipment_stages(id) ON DELETE SET NULL,
    declaration_no      VARCHAR(60),
    direction           VARCHAR(10)  NOT NULL,
    status              customs_status NOT NULL DEFAULT 'not_started',
    customs_office      VARCHAR(150),
    country_code        CHAR(2)      NOT NULL,
    broker_party_id     BIGINT       REFERENCES parties(id),
    officer_user_id     BIGINT       REFERENCES users(id),
    declared_value      NUMERIC(14,2),
    currency            CHAR(3),
    duty_amount         NUMERIC(14,2) NOT NULL DEFAULT 0,
    vat_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
    other_fees          NUMERIC(14,2) NOT NULL DEFAULT 0,
    submitted_at        TIMESTAMPTZ,
    cleared_at          TIMESTAMPTZ,
    inspection_required BOOLEAN      NOT NULL DEFAULT FALSE,
    hold_reason         TEXT,
    remarks             TEXT,
    CONSTRAINT customs_direction_values CHECK (direction IN ('export','import','transit')),
    CONSTRAINT customs_cleared_stamp CHECK (status <> 'cleared' OR cleared_at IS NOT NULL),
    CONSTRAINT customs_held_reason   CHECK (status <> 'held'    OR hold_reason IS NOT NULL),
    CONSTRAINT customs_amounts       CHECK (duty_amount >= 0 AND vat_amount >= 0 AND other_fees >= 0)
);

CREATE INDEX idx_customs_shipment ON customs_declarations(shipment_id);

-- =====================================================================
--  SECTION 17 :: DOCUMENT CENTRE
-- =====================================================================

CREATE TABLE documents (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    document_type_id    BIGINT       NOT NULL REFERENCES document_types(id),
    status              document_status NOT NULL DEFAULT 'uploaded',

    contract_id         BIGINT       REFERENCES contracts(id) ON DELETE CASCADE,
    shipment_id         BIGINT       REFERENCES shipments(id) ON DELETE CASCADE,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE CASCADE,
    transport_order_id  BIGINT       REFERENCES transport_orders(id) ON DELETE CASCADE,
    handling_operation_id BIGINT     REFERENCES handling_operations(id) ON DELETE CASCADE,
    customs_declaration_id BIGINT    REFERENCES customs_declarations(id) ON DELETE CASCADE,

    reference_no        VARCHAR(80),
    file_name           VARCHAR(255) NOT NULL,
    file_url            TEXT         NOT NULL,
    mime_type           VARCHAR(100),
    file_size_bytes     BIGINT,
    checksum_sha256     CHAR(64),
    issued_on           DATE,
    expires_on          DATE,
    uploaded_by         BIGINT       REFERENCES users(id),
    uploaded_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    verified_by         BIGINT       REFERENCES users(id),
    verified_at         TIMESTAMPTZ,
    rejection_reason    TEXT,

    CONSTRAINT documents_single_owner CHECK (
        num_nonnulls(contract_id, shipment_id, task_id, transport_order_id,
                     handling_operation_id, customs_declaration_id) = 1
    ),
    CONSTRAINT documents_verified_trail CHECK (
        status <> 'verified' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL)
    ),
    CONSTRAINT documents_rejected_reason CHECK (
        status <> 'rejected' OR rejection_reason IS NOT NULL
    ),
    CONSTRAINT documents_expiry_order CHECK (
        expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on
    )
);

CREATE INDEX idx_documents_shipment ON documents(shipment_id);
CREATE INDEX idx_documents_expiring ON documents(company_id, expires_on)
    WHERE expires_on IS NOT NULL AND status = 'verified';

-- =====================================================================
--  SECTION 18 :: DELIVERY AND PROOF OF DELIVERY
-- =====================================================================

CREATE TABLE deliveries (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE SET NULL,
    delivery_no         VARCHAR(40)  NOT NULL,
    location_id         BIGINT       NOT NULL REFERENCES locations(id),
    delivered_at        TIMESTAMPTZ  NOT NULL,
    driver_id           BIGINT       REFERENCES drivers(id),
    vehicle_id          BIGINT       REFERENCES vehicles(id),
    receiver_name       VARCHAR(150) NOT NULL,
    receiver_id_no      VARCHAR(60),
    receiver_phone      VARCHAR(30),
    signature_url       TEXT,
    photo_url           TEXT,
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    delivered_quantity  NUMERIC(14,3),
    accepted_in_full    BOOLEAN      NOT NULL DEFAULT TRUE,
    discrepancy_note    TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, delivery_no),
    CONSTRAINT deliveries_discrepancy_note CHECK (
        accepted_in_full OR discrepancy_note IS NOT NULL
    )
);

-- =====================================================================
--  SECTION 19 :: INCIDENTS AND EXCEPTIONS
-- =====================================================================

CREATE TABLE incident_types (
    id                  SMALLSERIAL PRIMARY KEY,
    code                VARCHAR(40)  NOT NULL UNIQUE,
    name                VARCHAR(150) NOT NULL,
    default_severity    incident_severity NOT NULL DEFAULT 'medium'
);

CREATE TABLE incidents (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE SET NULL,
    incident_no         VARCHAR(40)  NOT NULL,
    incident_type_id    SMALLINT     NOT NULL REFERENCES incident_types(id),
    severity            incident_severity NOT NULL DEFAULT 'medium',
    status              incident_status   NOT NULL DEFAULT 'open',
    description         TEXT         NOT NULL,
    occurred_at         TIMESTAMPTZ  NOT NULL,
    reported_by         BIGINT       REFERENCES users(id),
    reported_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    responsible_party_id BIGINT      REFERENCES parties(id),
    responsible_user_id  BIGINT      REFERENCES users(id),
    impact_description  TEXT,
    delay_hours         NUMERIC(8,2),
    cost_impact         NUMERIC(14,2),
    action_taken        TEXT,
    resolved_at         TIMESTAMPTZ,
    resolved_by         BIGINT       REFERENCES users(id),
    UNIQUE (company_id, incident_no),
    CONSTRAINT incidents_resolution_trail CHECK (
        status NOT IN ('resolved','closed')
        OR (resolved_at IS NOT NULL AND action_taken IS NOT NULL)
    ),
    CONSTRAINT incidents_resolution_order CHECK (
        resolved_at IS NULL OR resolved_at >= occurred_at
    )
);

CREATE INDEX idx_incidents_open ON incidents(company_id, status, severity)
    WHERE status IN ('open','under_investigation','action_taken');

-- =====================================================================
--  SECTION 20 :: TRACKING TIMELINE
-- =====================================================================

CREATE TABLE tracking_events (
    id                  BIGSERIAL PRIMARY KEY,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    stage_id            BIGINT       REFERENCES shipment_stages(id) ON DELETE SET NULL,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE SET NULL,
    event_code          VARCHAR(40)  NOT NULL,
    title               VARCHAR(180) NOT NULL,
    description         TEXT,
    location_id         BIGINT       REFERENCES locations(id),
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    occurred_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    recorded_by         BIGINT       REFERENCES users(id),
    is_customer_visible BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_tracking_timeline ON tracking_events(shipment_id, occurred_at);

-- =====================================================================
--  SECTION 21 :: FINANCE
-- =====================================================================

CREATE TABLE cost_categories (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    code                VARCHAR(40)  NOT NULL,
    name                VARCHAR(150) NOT NULL,
    direction           cost_direction NOT NULL DEFAULT 'cost',
    is_billable         BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (company_id, code)
);

CREATE TABLE shipment_financials (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    shipment_id         BIGINT       NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
    cost_category_id    BIGINT       NOT NULL REFERENCES cost_categories(id),
    direction           cost_direction NOT NULL,
    task_id             BIGINT       REFERENCES tasks(id) ON DELETE SET NULL,
    transport_order_id  BIGINT       REFERENCES transport_orders(id) ON DELETE SET NULL,
    customs_declaration_id BIGINT    REFERENCES customs_declarations(id) ON DELETE SET NULL,
    vendor_party_id     BIGINT       REFERENCES parties(id),
    description         VARCHAR(255),
    amount              NUMERIC(14,2) NOT NULL,
    currency            CHAR(3)       NOT NULL,
    fx_rate             NUMERIC(14,6) NOT NULL DEFAULT 1,
    base_amount         NUMERIC(14,2) NOT NULL,
    is_estimated        BOOLEAN       NOT NULL DEFAULT FALSE,
    entry_type          entry_type    NOT NULL DEFAULT 'charge',
    incurred_on         DATE          NOT NULL DEFAULT CURRENT_DATE,
    recorded_by         BIGINT        REFERENCES users(id),
    recorded_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT financials_fx_positive     CHECK (fx_rate > 0),
    CONSTRAINT financials_amount_sign     CHECK (
        (entry_type = 'credit' AND amount <= 0 AND base_amount <= 0) OR
        (entry_type IN ('charge','adjustment') AND amount >= 0 AND base_amount >= 0)
    )
);

CREATE INDEX idx_financials_shipment ON shipment_financials(shipment_id, direction);

CREATE TABLE invoices (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    invoice_no          VARCHAR(50)  NOT NULL,
    direction           invoice_direction NOT NULL,
    status              invoice_status    NOT NULL DEFAULT 'draft',
    party_id            BIGINT       NOT NULL REFERENCES parties(id),
    contract_id         BIGINT       REFERENCES contracts(id) ON DELETE SET NULL,
    shipment_id         BIGINT       REFERENCES shipments(id) ON DELETE SET NULL,
    issue_date          DATE         NOT NULL DEFAULT CURRENT_DATE,
    due_date            DATE         NOT NULL,
    currency            CHAR(3)      NOT NULL,
    subtotal            NUMERIC(14,2) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(14,2) NOT NULL DEFAULT 0,
    paid_amount         NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes               TEXT,
    created_by          BIGINT       REFERENCES users(id),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, invoice_no),
    CONSTRAINT invoices_due_after_issue CHECK (due_date >= issue_date),
    CONSTRAINT invoices_totals CHECK (
        subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0
        AND paid_amount >= 0 AND paid_amount <= total_amount
    )
);

CREATE INDEX idx_invoices_outstanding ON invoices(company_id, due_date)
    WHERE status IN ('issued','partially_paid','overdue');

CREATE TABLE invoice_lines (
    id                  BIGSERIAL PRIMARY KEY,
    invoice_id          BIGINT       NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    line_no             SMALLINT     NOT NULL,
    cost_category_id    BIGINT       REFERENCES cost_categories(id),
    description         VARCHAR(255) NOT NULL,
    quantity            NUMERIC(12,3) NOT NULL DEFAULT 1,
    unit_price          NUMERIC(14,2) NOT NULL,
    line_total          NUMERIC(14,2) NOT NULL,
    tax_rate            NUMERIC(5,2)  NOT NULL DEFAULT 0,
    entry_type          entry_type    NOT NULL DEFAULT 'charge',
    UNIQUE (invoice_id, line_no),
    CONSTRAINT invoice_lines_amounts CHECK (
        quantity > 0 AND (
            (entry_type = 'credit' AND unit_price <= 0 AND line_total <= 0) OR
            (entry_type IN ('charge','adjustment') AND unit_price >= 0 AND line_total >= 0)
        )
    )
);

CREATE TABLE payments (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    invoice_id          BIGINT       NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    payment_no          VARCHAR(40)  NOT NULL,
    paid_on             DATE         NOT NULL DEFAULT CURRENT_DATE,
    amount              NUMERIC(14,2) NOT NULL,
    currency            CHAR(3)      NOT NULL,
    method              VARCHAR(30)  NOT NULL,
    reference_no        VARCHAR(80),
    recorded_by         BIGINT       REFERENCES users(id),
    recorded_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (company_id, payment_no),
    CONSTRAINT payments_amount_positive CHECK (amount > 0)
);

-- =====================================================================
--  SECTION 22 :: SYSTEM AUDIT LOG
-- =====================================================================

CREATE TABLE audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    company_id          BIGINT       NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id             BIGINT       REFERENCES users(id) ON DELETE SET NULL,
    table_name          VARCHAR(60)  NOT NULL,
    record_id           BIGINT       NOT NULL,
    action              VARCHAR(20)  NOT NULL,
    old_values          JSONB,
    new_values          JSONB,
    ip_address          INET,
    user_agent          TEXT,
    occurred_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_record ON audit_log(table_name, record_id, occurred_at DESC);
CREATE INDEX idx_audit_user   ON audit_log(user_id, occurred_at DESC);

-- =====================================================================
--  SECTION 23 :: TRIGGERS
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_touch_updated_at() RETURNS TRIGGER AS $fn$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_companies_touch BEFORE UPDATE ON companies
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE TRIGGER trg_users_touch     BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE TRIGGER trg_contracts_touch BEFORE UPDATE ON contracts
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE TRIGGER trg_shipments_touch BEFORE UPDATE ON shipments
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();
CREATE TRIGGER trg_tasks_touch     BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at();

CREATE OR REPLACE FUNCTION fn_log_task_status() RETURNS TRIGGER AS $fn$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO task_status_history (task_id, from_status, to_status, changed_by, reason)
        VALUES (NEW.id, OLD.status, NEW.status,
                current_setting('app.current_user_id', TRUE)::BIGINT,
                NEW.hold_reason);
    END IF;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_status_history AFTER UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION fn_log_task_status();

CREATE OR REPLACE FUNCTION fn_apply_payment() RETURNS TRIGGER AS $fn$
DECLARE
    v_paid  NUMERIC(14,2);
    v_total NUMERIC(14,2);
BEGIN
    SELECT COALESCE(SUM(amount),0) INTO v_paid
      FROM payments WHERE invoice_id = NEW.invoice_id;
    SELECT total_amount INTO v_total
      FROM invoices WHERE id = NEW.invoice_id;

    UPDATE invoices
       SET paid_amount = v_paid,
           status = CASE
                        WHEN v_paid >= v_total THEN 'paid'::invoice_status
                        WHEN v_paid > 0        THEN 'partially_paid'::invoice_status
                        ELSE status
                    END
     WHERE id = NEW.invoice_id;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payments_apply AFTER INSERT ON payments
    FOR EACH ROW EXECUTE FUNCTION fn_apply_payment();

-- =====================================================================
--  SECTION 24 :: WORKFLOW INSTANTIATION
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_instantiate_workflow(p_shipment_id BIGINT)
RETURNS INTEGER AS $fn$
DECLARE
    v_company_id     BIGINT;
    v_template_id    BIGINT;
    v_type           RECORD;
    v_stage          RECORD;
    v_task           RECORD;
    v_new_stage_id   BIGINT;
    v_cursor_at      TIMESTAMPTZ;
    v_task_count     INTEGER := 0;
    v_map            JSONB := '{}'::JSONB;
BEGIN
    SELECT s.company_id,
           COALESCE(s.workflow_template_id, wt.id),
           COALESCE(s.planned_pickup_at, now())
      INTO v_company_id, v_template_id, v_cursor_at
      FROM shipments s
      JOIN contracts c            ON c.id = s.contract_id
      JOIN workflow_templates wt  ON wt.contract_type_id = c.contract_type_id
                                 AND wt.is_active
     WHERE s.id = p_shipment_id;

    IF v_template_id IS NULL THEN
        RAISE EXCEPTION 'No active workflow template for shipment %', p_shipment_id;
    END IF;

    SELECT ct.involves_warehouse, ct.is_international
      INTO v_type
      FROM shipments s
      JOIN contracts c      ON c.id = s.contract_id
      JOIN contract_types ct ON ct.id = c.contract_type_id
     WHERE s.id = p_shipment_id;

    FOR v_stage IN
        SELECT * FROM stage_templates
         WHERE workflow_template_id = v_template_id
         ORDER BY sequence_no
    LOOP
        CONTINUE WHEN v_stage.skip_if_no_warehouse AND NOT v_type.involves_warehouse;
        CONTINUE WHEN v_stage.skip_if_domestic     AND NOT v_type.is_international;

        INSERT INTO shipment_stages
            (shipment_id, stage_template_id, sequence_no, code, name,
             status, planned_start_at)
        VALUES
            (p_shipment_id, v_stage.id, v_stage.sequence_no, v_stage.code,
             v_stage.name, 'pending', v_cursor_at)
        RETURNING id INTO v_new_stage_id;

        FOR v_task IN
            SELECT * FROM task_templates
             WHERE stage_template_id = v_stage.id
             ORDER BY sequence_no
        LOOP
            INSERT INTO tasks
                (company_id, shipment_id, stage_id, task_template_id, task_no,
                 code, name, description, status, priority, department_id,
                 scheduled_start_at, scheduled_end_at,
                 requires_document, requires_signature, requires_photo,
                 blocks_shipment_on_failure)
            VALUES
                (v_company_id, p_shipment_id, v_new_stage_id, v_task.id,
                 'TSK-' || p_shipment_id || '-' || nextval('tasks_id_seq'),
                 v_task.code, v_task.name, v_task.description,
                 'created', v_task.default_priority, v_task.default_department_id,
                 v_cursor_at + (v_task.offset_hours || ' hours')::INTERVAL,
                 v_cursor_at + ((v_task.offset_hours + v_task.duration_hours) || ' hours')::INTERVAL,
                 v_task.requires_document, v_task.requires_signature,
                 v_task.requires_photo, v_task.blocks_shipment_on_failure);

            v_map := v_map || jsonb_build_object(v_task.id::TEXT, currval('tasks_id_seq'));
            v_task_count := v_task_count + 1;
        END LOOP;

        SELECT COALESCE(MAX(scheduled_end_at), v_cursor_at) INTO v_cursor_at
          FROM tasks WHERE stage_id = v_new_stage_id;

        UPDATE shipment_stages SET planned_end_at = v_cursor_at WHERE id = v_new_stage_id;
    END LOOP;

    INSERT INTO task_dependencies (task_id, depends_on_task_id)
    SELECT (v_map ->> d.task_template_id::TEXT)::BIGINT,
           (v_map ->> d.depends_on_template_id::TEXT)::BIGINT
      FROM task_template_dependencies d
     WHERE v_map ? d.task_template_id::TEXT
       AND v_map ? d.depends_on_template_id::TEXT;

    UPDATE shipments
       SET workflow_template_id = v_template_id,
           status = 'planned',
           current_stage_id = (SELECT id FROM shipment_stages
                                WHERE shipment_id = p_shipment_id
                                ORDER BY sequence_no LIMIT 1)
     WHERE id = p_shipment_id;

    RETURN v_task_count;
END;
$fn$ LANGUAGE plpgsql;

-- =====================================================================
--  SECTION 25 :: OPERATIONAL VIEWS
-- =====================================================================

CREATE VIEW v_ready_tasks AS
SELECT t.id,
       t.company_id,
       t.task_no,
       t.name              AS task_name,
       t.status,
       t.priority,
       t.scheduled_start_at,
       s.tracking_no,
       st.name             AS stage_name,
       d.name              AS department_name,
       u.full_name         AS assignee,
       (t.scheduled_end_at < now() AND t.status NOT IN ('completed','closed')) AS is_overdue
  FROM tasks t
  JOIN shipments s        ON s.id  = t.shipment_id
  JOIN shipment_stages st ON st.id = t.stage_id
  LEFT JOIN departments d ON d.id  = t.department_id
  LEFT JOIN users u       ON u.id  = t.assigned_to_user_id
 WHERE t.status IN ('created','assigned','scheduled')
   AND NOT EXISTS (
        SELECT 1
          FROM task_dependencies td
          JOIN tasks p ON p.id = td.depends_on_task_id
         WHERE td.task_id = t.id
           AND p.status NOT IN ('completed','closed')
   );

CREATE VIEW v_shipment_profitability AS
SELECT s.id                AS shipment_id,
       s.company_id,
       s.tracking_no,
       c.contract_no,
       cu.legal_name       AS customer_name,
       s.status,
       COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'revenue'), 0) AS total_revenue,
       COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'cost'),    0) AS total_cost,
       COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'revenue'), 0)
     - COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'cost'),    0) AS gross_profit,
       CASE
         WHEN COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'revenue'), 0) = 0 THEN NULL
         ELSE ROUND(
              (COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'revenue'), 0)
             - COALESCE(SUM(f.base_amount) FILTER (WHERE f.direction = 'cost'),    0))
             / SUM(f.base_amount) FILTER (WHERE f.direction = 'revenue') * 100, 2)
       END AS margin_percent
  FROM shipments s
  JOIN contracts c  ON c.id  = s.contract_id
  JOIN parties  cu  ON cu.id = c.customer_id
  LEFT JOIN shipment_financials f ON f.shipment_id = s.id
 GROUP BY s.id, s.company_id, s.tracking_no, c.contract_no, cu.legal_name, s.status;

CREATE VIEW v_shipment_tracking AS
SELECT s.tracking_no,
       s.status               AS shipment_status,
       st.name                AS current_stage,
       l.name                 AS current_location,
       s.planned_delivery_at,
       s.actual_delivery_at,
       (SELECT COUNT(*) FROM tasks t
         WHERE t.shipment_id = s.id AND t.status IN ('completed','closed'))   AS tasks_completed,
       (SELECT COUNT(*) FROM tasks t WHERE t.shipment_id = s.id)              AS tasks_total,
       (SELECT COUNT(*) FROM incidents i
         WHERE i.shipment_id = s.id
           AND i.status IN ('open','under_investigation'))                    AS open_incidents,
       (SELECT MIN(t.name) FROM tasks t
         WHERE t.shipment_id = s.id
           AND t.status IN ('created','assigned','scheduled','in_progress'))  AS next_action
  FROM shipments s
  LEFT JOIN shipment_stages st ON st.id = s.current_stage_id
  LEFT JOIN locations l        ON l.id  = s.current_location_id;

CREATE VIEW v_stock_on_hand AS
SELECT im.warehouse_id,
       w.name              AS warehouse_name,
       im.product_id,
       p.sku,
       p.name              AS product_name,
       im.batch_no,
       SUM(im.quantity)    AS quantity_on_hand,
       im.uom,
       MIN(im.moved_at)    AS first_received_at,
       EXTRACT(DAY FROM now() - MIN(im.moved_at))::INTEGER AS days_in_storage
  FROM inventory_movements im
  JOIN warehouses w ON w.id = im.warehouse_id
  JOIN products   p ON p.id = im.product_id
 GROUP BY im.warehouse_id, w.name, im.product_id, p.sku, p.name, im.batch_no, im.uom
HAVING SUM(im.quantity) <> 0;

CREATE VIEW v_fleet_status AS
SELECT v.company_id,
       v.id                AS vehicle_id,
       v.plate_no,
       v.vehicle_type,
       v.status,
       t.order_no          AS current_transport_order,
       d.full_name         AS current_driver,
       (v.registration_expiry < CURRENT_DATE + 30) AS registration_expiring_soon,
       (v.insurance_expiry   < CURRENT_DATE + 30) AS insurance_expiring_soon
  FROM vehicles v
  LEFT JOIN transport_orders t ON t.vehicle_id = v.id
                             AND t.status IN ('dispatched','in_transit')
  LEFT JOIN drivers d          ON d.id = t.driver_id
 WHERE v.is_active;

COMMIT;

-- =====================================================================
--  END OF SCHEMA
-- =====================================================================
