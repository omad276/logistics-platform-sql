-- =============================================================================
-- Countries, Currencies, and Customs Unions
-- Multi-market support with temporal customs union membership
-- =============================================================================

-- Required for EXCLUDE constraint with non-GiST types
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- -----------------------------------------------------------------------------
-- Currencies (ISO 4217)
-- -----------------------------------------------------------------------------
CREATE TABLE currencies (
    code            CHAR(3)      PRIMARY KEY,
    numeric_code    CHAR(3),
    name            VARCHAR(100) NOT NULL,
    symbol          VARCHAR(10),
    decimal_places  SMALLINT     NOT NULL DEFAULT 2,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE currencies IS 'ISO 4217 currency codes. Not tenant-specific.';

-- -----------------------------------------------------------------------------
-- Countries (ISO 3166-1)
-- -----------------------------------------------------------------------------
CREATE TABLE countries (
    alpha2              CHAR(2)      PRIMARY KEY,
    alpha3              CHAR(3)      NOT NULL UNIQUE,
    numeric_code        CHAR(3),
    name                VARCHAR(100) NOT NULL,
    official_name       VARCHAR(200),
    default_currency    CHAR(3)      REFERENCES currencies(code),
    phone_prefix        VARCHAR(10),
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE countries IS 'ISO 3166-1 country codes. Not tenant-specific.';

-- -----------------------------------------------------------------------------
-- Customs Unions and Trade Blocs
-- -----------------------------------------------------------------------------
CREATE TABLE customs_unions (
    code                VARCHAR(10)  PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE customs_unions IS 'Trade blocs with shared customs regimes (EU, GCC, EAC, etc.)';

-- -----------------------------------------------------------------------------
-- Country membership in customs unions (temporal)
-- -----------------------------------------------------------------------------
CREATE TABLE country_customs_unions (
    id                   BIGSERIAL    PRIMARY KEY,
    country_code         CHAR(2)      NOT NULL REFERENCES countries(alpha2),
    union_code           VARCHAR(10)  NOT NULL REFERENCES customs_unions(code),
    valid_from           DATE         NOT NULL,
    valid_to             DATE,
    requires_declaration BOOLEAN      NOT NULL DEFAULT FALSE,
    coverage_note        TEXT,
    source               VARCHAR(200),
    last_verified        DATE,

    CONSTRAINT ccu_valid_period CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ccu_no_overlapping_membership EXCLUDE USING gist (
        country_code WITH =,
        union_code WITH =,
        daterange(valid_from, valid_to, '[]') WITH &&
    )
);

CREATE INDEX idx_ccu_country ON country_customs_unions(country_code);
CREATE INDEX idx_ccu_union ON country_customs_unions(union_code);
CREATE INDEX idx_ccu_active ON country_customs_unions(country_code, union_code)
    WHERE valid_to IS NULL;

COMMENT ON TABLE country_customs_unions IS 'Temporal membership of countries in customs unions';
COMMENT ON COLUMN country_customs_unions.requires_declaration IS 'Whether goods crossing this border require customs declaration (FALSE for intra-EU, TRUE for non-EU)';
COMMENT ON COLUMN country_customs_unions.source IS 'Legal instrument or URL for membership (e.g., "Treaty of Accession 2004")';
COMMENT ON COLUMN country_customs_unions.last_verified IS 'Date this record was last verified against official sources';

-- -----------------------------------------------------------------------------
-- Function: Determine if customs declaration is required
-- Returns separate flags for export and import declarations
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_requires_customs_declaration(
    p_origin_country      CHAR(2),
    p_destination_country CHAR(2),
    p_movement_date       DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    requires_export_declaration BOOLEAN,
    requires_import_declaration BOOLEAN,
    shared_union_code           VARCHAR(10),
    origin_unions               TEXT[],
    destination_unions          TEXT[]
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_origin_unions      TEXT[];
    v_destination_unions TEXT[];
    v_shared_union       RECORD;
BEGIN
    -- Same country = no customs
    IF p_origin_country = p_destination_country THEN
        RETURN QUERY SELECT
            FALSE::BOOLEAN,
            FALSE::BOOLEAN,
            NULL::VARCHAR(10),
            ARRAY[]::TEXT[],
            ARRAY[]::TEXT[];
        RETURN;
    END IF;

    -- Get all active unions for origin
    SELECT array_agg(union_code)
    INTO v_origin_unions
    FROM country_customs_unions
    WHERE country_code = p_origin_country
      AND valid_from <= p_movement_date
      AND (valid_to IS NULL OR valid_to >= p_movement_date);

    -- Get all active unions for destination
    SELECT array_agg(union_code)
    INTO v_destination_unions
    FROM country_customs_unions
    WHERE country_code = p_destination_country
      AND valid_from <= p_movement_date
      AND (valid_to IS NULL OR valid_to >= p_movement_date);

    -- Check for shared union membership
    -- ORDER BY: prefer unions where declaration is NOT required (FALSE < TRUE)
    SELECT
        ccu1.union_code,
        ccu1.requires_declaration AS origin_requires,
        ccu2.requires_declaration AS dest_requires
    INTO v_shared_union
    FROM country_customs_unions ccu1
    JOIN country_customs_unions ccu2
        ON ccu1.union_code = ccu2.union_code
    WHERE ccu1.country_code = p_origin_country
      AND ccu2.country_code = p_destination_country
      AND ccu1.valid_from <= p_movement_date
      AND (ccu1.valid_to IS NULL OR ccu1.valid_to >= p_movement_date)
      AND ccu2.valid_from <= p_movement_date
      AND (ccu2.valid_to IS NULL OR ccu2.valid_to >= p_movement_date)
    ORDER BY (ccu1.requires_declaration OR ccu2.requires_declaration) ASC, ccu1.union_code ASC
    LIMIT 1;

    IF v_shared_union IS NOT NULL THEN
        -- Shared union found - use union-specific rules
        RETURN QUERY SELECT
            v_shared_union.origin_requires,
            v_shared_union.dest_requires,
            v_shared_union.union_code,
            COALESCE(v_origin_unions, ARRAY[]::TEXT[]),
            COALESCE(v_destination_unions, ARRAY[]::TEXT[]);
    ELSE
        -- No shared union - full customs both ways
        RETURN QUERY SELECT
            TRUE::BOOLEAN,
            TRUE::BOOLEAN,
            NULL::VARCHAR(10),
            COALESCE(v_origin_unions, ARRAY[]::TEXT[]),
            COALESCE(v_destination_unions, ARRAY[]::TEXT[]);
    END IF;
END;
$$;

COMMENT ON FUNCTION fn_requires_customs_declaration IS
'Determines if customs declarations are required for a cross-border movement.
Returns separate flags for export and import, plus the shared union code if any.
For intra-EU: both FALSE. For EU→UK post-Brexit: both TRUE. For transit regimes: caller must handle T1 separately.';

-- =============================================================================
-- Seed Data: Core reference data
-- =============================================================================

-- Currencies
INSERT INTO currencies (code, numeric_code, name, symbol, decimal_places) VALUES
('USD', '840', 'United States Dollar', '$', 2),
('EUR', '978', 'Euro', '€', 2),
('GBP', '826', 'British Pound Sterling', '£', 2),
('AED', '784', 'United Arab Emirates Dirham', 'د.إ', 2),
('SAR', '682', 'Saudi Riyal', '﷼', 2),
('QAR', '634', 'Qatari Riyal', '﷼', 2),
('KWD', '414', 'Kuwaiti Dinar', 'د.ك', 3),
('BHD', '048', 'Bahraini Dinar', '.د.ب', 3),
('OMR', '512', 'Omani Rial', '﷼', 3),
('SDG', '938', 'Sudanese Pound', 'ج.س', 2),
('EGP', '818', 'Egyptian Pound', '£', 2),
('KES', '404', 'Kenyan Shilling', 'KSh', 2),
('TZS', '834', 'Tanzanian Shilling', 'TSh', 2),
('UGX', '800', 'Ugandan Shilling', 'USh', 0),
('PLN', '985', 'Polish Zloty', 'zł', 2),
('CHF', '756', 'Swiss Franc', 'Fr', 2),
('NOK', '578', 'Norwegian Krone', 'kr', 2),
('CAD', '124', 'Canadian Dollar', '$', 2),
('MXN', '484', 'Mexican Peso', '$', 2),
('BRL', '986', 'Brazilian Real', 'R$', 2),
('CNY', '156', 'Chinese Yuan', '¥', 2),
('JPY', '392', 'Japanese Yen', '¥', 0),
('SGD', '702', 'Singapore Dollar', '$', 2),
('INR', '356', 'Indian Rupee', '₹', 2);

-- Customs unions
INSERT INTO customs_unions (code, name, description) VALUES
('EU', 'European Union', 'EU customs territory with single market'),
('GCC', 'Gulf Cooperation Council', 'GCC common market'),
('EAC', 'East African Community', 'EAC customs union'),
('SACU', 'Southern African Customs Union', 'SACU common external tariff'),
('MERCOSUR', 'Southern Common Market', 'South American trade bloc'),
('USMCA', 'United States-Mexico-Canada Agreement', 'Successor to NAFTA');

-- Countries (subset for demo - real deployment would load all 249)
INSERT INTO countries (alpha2, alpha3, numeric_code, name, official_name, default_currency, phone_prefix) VALUES
-- EU members
('DE', 'DEU', '276', 'Germany', 'Federal Republic of Germany', 'EUR', '+49'),
('FR', 'FRA', '250', 'France', 'French Republic', 'EUR', '+33'),
('NL', 'NLD', '528', 'Netherlands', 'Kingdom of the Netherlands', 'EUR', '+31'),
('BE', 'BEL', '056', 'Belgium', 'Kingdom of Belgium', 'EUR', '+32'),
('PL', 'POL', '616', 'Poland', 'Republic of Poland', 'PLN', '+48'),
('ES', 'ESP', '724', 'Spain', 'Kingdom of Spain', 'EUR', '+34'),
('IT', 'ITA', '380', 'Italy', 'Italian Republic', 'EUR', '+39'),

-- Non-EU Europe
('GB', 'GBR', '826', 'United Kingdom', 'United Kingdom of Great Britain and Northern Ireland', 'GBP', '+44'),
('CH', 'CHE', '756', 'Switzerland', 'Swiss Confederation', 'CHF', '+41'),
('NO', 'NOR', '578', 'Norway', 'Kingdom of Norway', 'NOK', '+47'),

-- GCC
('AE', 'ARE', '784', 'United Arab Emirates', 'United Arab Emirates', 'AED', '+971'),
('SA', 'SAU', '682', 'Saudi Arabia', 'Kingdom of Saudi Arabia', 'SAR', '+966'),
('QA', 'QAT', '634', 'Qatar', 'State of Qatar', 'QAR', '+974'),
('KW', 'KWT', '414', 'Kuwait', 'State of Kuwait', 'KWD', '+965'),
('BH', 'BHR', '048', 'Bahrain', 'Kingdom of Bahrain', 'BHD', '+973'),
('OM', 'OMN', '512', 'Oman', 'Sultanate of Oman', 'OMR', '+968'),

-- Africa (for Sudan scenario)
('SD', 'SDN', '729', 'Sudan', 'Republic of the Sudan', 'SDG', '+249'),
('EG', 'EGY', '818', 'Egypt', 'Arab Republic of Egypt', 'EGP', '+20'),
('KE', 'KEN', '404', 'Kenya', 'Republic of Kenya', 'KES', '+254'),
('TZ', 'TZA', '834', 'Tanzania', 'United Republic of Tanzania', 'TZS', '+255'),
('UG', 'UGA', '800', 'Uganda', 'Republic of Uganda', 'UGX', '+256'),

-- Americas
('US', 'USA', '840', 'United States', 'United States of America', 'USD', '+1'),
('CA', 'CAN', '124', 'Canada', 'Canada', 'CAD', '+1'),
('MX', 'MEX', '484', 'Mexico', 'United Mexican States', 'MXN', '+52'),
('BR', 'BRA', '076', 'Brazil', 'Federative Republic of Brazil', 'BRL', '+55'),

-- Asia
('CN', 'CHN', '156', 'China', 'People''s Republic of China', 'CNY', '+86'),
('JP', 'JPN', '392', 'Japan', 'Japan', 'JPY', '+81'),
('SG', 'SGP', '702', 'Singapore', 'Republic of Singapore', 'SGD', '+65'),
('IN', 'IND', '356', 'India', 'Republic of India', 'INR', '+91');

-- EU memberships (all current members, no declaration required within EU)
INSERT INTO country_customs_unions (country_code, union_code, valid_from, valid_to, requires_declaration, source, last_verified) VALUES
('DE', 'EU', '1958-01-01', NULL, FALSE, 'Founding member - Treaty of Rome 1957', '2024-01-15'),
('FR', 'EU', '1958-01-01', NULL, FALSE, 'Founding member - Treaty of Rome 1957', '2024-01-15'),
('NL', 'EU', '1958-01-01', NULL, FALSE, 'Founding member - Treaty of Rome 1957', '2024-01-15'),
('BE', 'EU', '1958-01-01', NULL, FALSE, 'Founding member - Treaty of Rome 1957', '2024-01-15'),
('IT', 'EU', '1958-01-01', NULL, FALSE, 'Founding member - Treaty of Rome 1957', '2024-01-15'),
('ES', 'EU', '1986-01-01', NULL, FALSE, 'Accession 1986', '2024-01-15'),
('PL', 'EU', '2004-05-01', NULL, FALSE, 'Treaty of Accession 2003', '2024-01-15'),
-- UK membership: 1973-01-01 to 2020-12-31 (Brexit)
('GB', 'EU', '1973-01-01', '2020-12-31', FALSE, 'Accession 1973, Withdrawal Agreement 2020', '2024-01-15');

-- GCC memberships
INSERT INTO country_customs_unions (country_code, union_code, valid_from, valid_to, requires_declaration, source, last_verified) VALUES
('AE', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15'),
('SA', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15'),
('QA', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15'),
('KW', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15'),
('BH', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15'),
('OM', 'GCC', '2003-01-01', NULL, FALSE, 'GCC Customs Union 2003', '2024-01-15');

-- EAC memberships
INSERT INTO country_customs_unions (country_code, union_code, valid_from, valid_to, requires_declaration, source, last_verified) VALUES
('KE', 'EAC', '2005-01-01', NULL, FALSE, 'EAC Customs Union Protocol 2004', '2024-01-15'),
('TZ', 'EAC', '2005-01-01', NULL, FALSE, 'EAC Customs Union Protocol 2004', '2024-01-15'),
('UG', 'EAC', '2005-01-01', NULL, FALSE, 'EAC Customs Union Protocol 2004', '2024-01-15');

-- USMCA memberships
INSERT INTO country_customs_unions (country_code, union_code, valid_from, valid_to, requires_declaration, source, last_verified) VALUES
('US', 'USMCA', '2020-07-01', NULL, TRUE, 'USMCA entered into force July 1, 2020', '2024-01-15'),
('CA', 'USMCA', '2020-07-01', NULL, TRUE, 'USMCA entered into force July 1, 2020', '2024-01-15'),
('MX', 'USMCA', '2020-07-01', NULL, TRUE, 'USMCA entered into force July 1, 2020', '2024-01-15');

-- =============================================================================
-- Test queries
-- =============================================================================

-- Intra-EU (Germany → France): no customs
-- SELECT * FROM fn_requires_customs_declaration('DE', 'FR', '2024-06-01');
-- Expected: (FALSE, FALSE, 'EU', ...)

-- UK → Germany pre-Brexit (Dec 2020): no customs
-- SELECT * FROM fn_requires_customs_declaration('GB', 'DE', '2020-12-01');
-- Expected: (FALSE, FALSE, 'EU', ...)

-- UK → Germany post-Brexit (Jan 2021): full customs
-- SELECT * FROM fn_requires_customs_declaration('GB', 'DE', '2021-01-15');
-- Expected: (TRUE, TRUE, NULL, ...)

-- Sudan → UAE: no shared union, full customs
-- SELECT * FROM fn_requires_customs_declaration('SD', 'AE', '2024-06-01');
-- Expected: (TRUE, TRUE, NULL, ...)

-- UAE → Saudi (intra-GCC): no customs
-- SELECT * FROM fn_requires_customs_declaration('AE', 'SA', '2024-06-01');
-- Expected: (FALSE, FALSE, 'GCC', ...)
