-- 05_dw_ddl.sql
-- Model dimensional netral alat (star schema). Rancangan dan grain: docs/model-data.md.
-- Surrogate key berupa INTEGER yang diisi saat load (ROW_NUMBER), tanpa fitur
-- identity khusus vendor supaya mudah dipindah ke engine lain.

CREATE TABLE dim_date (
    date_key     INTEGER PRIMARY KEY,   -- YYYYMMDD
    full_date    DATE NOT NULL,
    year_no      INTEGER,
    quarter_no   INTEGER,
    month_no     INTEGER,
    day_no       INTEGER,
    period       VARCHAR(7)
);

CREATE TABLE dim_station (
    station_key    INTEGER PRIMARY KEY,
    station_code   VARCHAR(10) NOT NULL,
    station_name   VARCHAR(50),
    business_area  VARCHAR(10),
    is_physical    CHAR(1)               -- 'N' untuk kanal ONLINE
);

CREATE TABLE dim_employee (
    employee_key   INTEGER PRIMARY KEY,
    employee_id    VARCHAR(10) NOT NULL,
    employee_name  VARCHAR(150),
    department     VARCHAR(30),
    station_code   VARCHAR(10),
    position       VARCHAR(30)
);

CREATE TABLE dim_channel (
    channel_key    INTEGER PRIMARY KEY,
    channel_code   VARCHAR(10) NOT NULL,
    channel_group  VARCHAR(20)            -- LOKET, MESIN, ONLINE, B2B
);

CREATE TABLE dim_payment_method (
    payment_key      INTEGER PRIMARY KEY,
    payment_method   VARCHAR(20) NOT NULL,
    payment_gateway  VARCHAR(20),
    is_cash          CHAR(1)
);

CREATE TABLE dim_discount (
    discount_key   INTEGER PRIMARY KEY,
    discount_type  VARCHAR(20) NOT NULL,
    discount_rate  DECIMAL(5,2) NOT NULL
);

-- Pembeli dipseudonimkan: hanya hash identitas dan kewarganegaraan.
CREATE TABLE dim_customer (
    customer_key   INTEGER PRIMARY KEY,
    customer_hash  VARCHAR(64) NOT NULL,
    nationality    CHAR(3),
    is_foreign     CHAR(1)
);

CREATE TABLE dim_group_order (
    group_order_key        INTEGER PRIMARY KEY,
    bak_id                 INTEGER NOT NULL,
    bak_no                 VARCHAR(40),
    order_no               VARCHAR(30),
    counterparty_name      VARCHAR(150),
    approved_discount_rate DECIMAL(5,2),
    approved_ticket_count  INTEGER,
    approved_total_amount  BIGINT
);

CREATE TABLE dim_source_dept (
    dept_key     INTEGER PRIMARY KEY,
    department   VARCHAR(20) NOT NULL
);

CREATE TABLE dim_audit_rule (
    rule_key     INTEGER PRIMARY KEY,
    rule_code    VARCHAR(40) NOT NULL,
    rule_name    VARCHAR(100),
    category     VARCHAR(30),
    severity     VARCHAR(10)
);

-- Grain: satu baris per tiket (setelah deduplikasi ticket_no).
CREATE TABLE fact_ticket_sale (
    ticket_no             VARCHAR(20) PRIMARY KEY,   -- degenerate dimension
    order_no              VARCHAR(30),               -- degenerate dimension
    purchase_date_key     INTEGER REFERENCES dim_date (date_key),
    departure_date_key    INTEGER REFERENCES dim_date (date_key),
    sales_station_key     INTEGER REFERENCES dim_station (station_key),
    origin_station_key    INTEGER REFERENCES dim_station (station_key),
    destination_station_key INTEGER REFERENCES dim_station (station_key),
    channel_key           INTEGER REFERENCES dim_channel (channel_key),
    payment_key           INTEGER REFERENCES dim_payment_method (payment_key),
    discount_key          INTEGER REFERENCES dim_discount (discount_key),
    operator_key          INTEGER REFERENCES dim_employee (employee_key),   -- NULL untuk kanal SYSTEM
    customer_key          INTEGER REFERENCES dim_customer (customer_key),
    group_order_key       INTEGER REFERENCES dim_group_order (group_order_key),
    shift_no              INTEGER,
    seat_class            VARCHAR(20),
    original_price        BIGINT,
    discount_amount       BIGINT,
    before_tax_amount     BIGINT,
    tax_amount            BIGINT,
    after_tax_amount      BIGINT
);

-- Grain: satu baris per mutasi rekening koran.
CREATE TABLE fact_bank_mutation (
    bank_ref       VARCHAR(20) PRIMARY KEY,
    posting_date_key INTEGER REFERENCES dim_date (date_key),
    txn_category   VARCHAR(20),
    debit_amount   BIGINT,
    credit_amount  BIGINT
);

-- Grain: satu baris per refund.
CREATE TABLE fact_refund (
    refund_id       VARCHAR(30) PRIMARY KEY,
    ticket_no       VARCHAR(20),
    refund_date_key INTEGER REFERENCES dim_date (date_key),
    station_key     INTEGER REFERENCES dim_station (station_key),
    customer_key    INTEGER REFERENCES dim_customer (customer_key),
    refund_method   VARCHAR(10),
    ticket_price    BIGINT,
    refund_amount   BIGINT
);

-- Grain: satu baris per temuan aturan audit atau kepatuhan unggah.
CREATE TABLE fact_audit_exception (
    rule_key     INTEGER REFERENCES dim_audit_rule (rule_key),
    dept_key     INTEGER REFERENCES dim_source_dept (dept_key),
    period       VARCHAR(7),
    entity_type  VARCHAR(20),
    entity_id    VARCHAR(80),
    exception_count INTEGER,
    PRIMARY KEY (rule_key, entity_id)
);

-- Grain: satu baris per kewajiban unggah (departemen, sumber, stasiun, periode).
CREATE TABLE fact_upload_submission (
    dept_key        INTEGER REFERENCES dim_source_dept (dept_key),
    source_type     VARCHAR(30),
    station_code    VARCHAR(10),
    period          VARCHAR(7),
    revisions       INTEGER,
    is_submitted    INTEGER,
    is_on_time      INTEGER,
    is_valid        INTEGER,
    is_approved     INTEGER,
    is_checksum_ok  INTEGER,
    PRIMARY KEY (dept_key, source_type, station_code, period)
);
