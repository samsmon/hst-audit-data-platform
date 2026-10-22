-- 01_staging_ddl.sql
-- Tabel staging: satu tabel per sumber, tipe data sudah diseragamkan oleh ETL.
-- Staging = isi zona curated sebelum dimodelkan. Data pribadi mentah (id_number)
-- hanya ada di sini dan aksesnya dibatasi; lapisan dimensional memakai hash.
-- SQL standar; tipe BIGINT dipakai untuk nominal rupiah tanpa sen.

-- IT: export sistem ticketing (system of record)
CREATE TABLE stg_ticket_sales (
    seq_no                INTEGER,
    period                VARCHAR(7),      -- dari 'JAN-2025' menjadi '2025-01'
    passenger_name        VARCHAR(150),
    id_number             VARCHAR(30),     -- NIK atau paspor (data pribadi)
    customer_hash         VARCHAR(64),     -- SHA-256 id_number + salt, dibuat ETL
    bak_id                INTEGER,
    nationality           CHAR(3),
    order_no              VARCHAR(30),
    ticket_no             VARCHAR(20),
    ticketing_station     VARCHAR(10),     -- kode stasiun, atau ONLINE
    business_area         VARCHAR(10),     -- kolom sumber: bussiness_area
    office_no             VARCHAR(10),
    window_no             INTEGER,
    shift_no              INTEGER,
    operator_name         VARCHAR(150),
    ticketing_ts          TIMESTAMP,
    departure_date        DATE,
    train_no              VARCHAR(10),
    origin_name           VARCHAR(50),
    cars_number           INTEGER,
    seat_number           VARCHAR(5),
    origin_code           VARCHAR(10),
    purchase_date         DATE,
    purchase_time         TIME,
    departure_time        TIME,
    destination_name      VARCHAR(50),
    destination_code      VARCHAR(10),
    arrival_date          DATE,
    arrival_time          TIME,
    seat_class            VARCHAR(20),
    ticket_type           VARCHAR(10),
    original_ticket_price BIGINT,
    discount_type         VARCHAR(20),
    discount_rate         DECIMAL(5,2),
    before_tax_price      BIGINT,
    tax_rate              DECIMAL(4,2),
    after_tax_price       BIGINT,
    ticketing_channel     VARCHAR(10),
    payment_method        VARCHAR(20),
    trade_no              VARCHAR(30),
    plat_trade_no         VARCHAR(30),
    payment_gateway       VARCHAR(20),
    b2b_partner           VARCHAR(150),
    source_file           VARCHAR(200)
);

-- Stasiun: rekap penjualan dari tiga layout, diseragamkan ke satu bentuk.
-- recap_level ORDER (satu baris per order) atau SHIFT (agregat per tanggal dan shift).
CREATE TABLE stg_station_recap (
    station_code    VARCHAR(10),
    period          VARCHAR(7),
    recap_level     VARCHAR(10),
    sales_date      DATE,
    shift_no        INTEGER,
    window_no       INTEGER,
    order_no        VARCHAR(30),
    buyer_name      VARCHAR(150),
    ticket_count    INTEGER,
    payment_method  VARCHAR(20),
    cash_amount     BIGINT,
    noncash_amount  BIGINT,
    total_amount    BIGINT,
    source_file     VARCHAR(200),
    source_row      INTEGER
);

-- Stasiun: laporan refund (hasil ekstraksi dokumen scan + review manusia)
CREATE TABLE stg_refund (
    refund_id       VARCHAR(30),
    station_code    VARCHAR(10),
    refund_date     DATE,
    ticket_no       VARCHAR(20),
    order_no        VARCHAR(30),
    passenger_name  VARCHAR(150),
    nationality     CHAR(3),
    id_number       VARCHAR(30),
    refund_method   VARCHAR(10),
    bank_name       VARCHAR(50),
    bank_account    VARCHAR(30),
    account_holder  VARCHAR(150),
    account_holder_key VARCHAR(150),  -- nama dinormalisasi ETL: ASCII, huruf besar, spasi tunggal
    ticket_price    BIGINT,
    refund_amount   BIGINT,
    processed_by    VARCHAR(150),
    approved_by     VARCHAR(150),
    ocr_confidence  DECIMAL(4,3),
    a2i_status      VARCHAR(10),
    a2i_maker       VARCHAR(10),
    a2i_checker     VARCHAR(10),
    source_file     VARCHAR(200)
);

-- Finance: berita acara kesepakatan (BAK) group order
CREATE TABLE stg_bak (
    bak_id              INTEGER,
    bak_no              VARCHAR(40),
    period              VARCHAR(7),
    document_date       DATE,
    counterparty_name   VARCHAR(150),
    order_no            VARCHAR(30),
    ticket_count        INTEGER,
    total_amount        BIGINT,
    discount_type       VARCHAR(20),
    discount_rate       DECIMAL(5,2),
    station_code        VARCHAR(10),
    approved_by         VARCHAR(10),
    transfer_proof_flag CHAR(1),
    manifest_flag       CHAR(1),
    status              VARCHAR(20),
    remarks             VARCHAR(500),
    source_file         VARCHAR(200)
);

-- Finance: metadata bukti transfer hasil ekstraksi dokumen
CREATE TABLE stg_transfer_proof (
    proof_id              VARCHAR(20),
    bak_no                VARCHAR(40),
    file_name             VARCHAR(200),
    file_sha256           VARCHAR(64),
    uploaded_at           TIMESTAMP,
    sender_name           VARCHAR(150),
    sender_bank           VARCHAR(50),
    sender_account_masked VARCHAR(20),
    transfer_date         DATE,
    amount                BIGINT,
    reference_no          VARCHAR(30),
    ocr_confidence        DECIMAL(4,3),
    a2i_status            VARCHAR(10),
    a2i_maker             VARCHAR(10),
    a2i_checker           VARCHAR(10),
    source_file           VARCHAR(200)
);

-- Finance: rekening koran. Tidak ada order_no; kunci pencocokan diturunkan ETL
-- dari kolom keterangan (txn_category, ref_no, key_station, key_date, key_gateway, counterparty).
CREATE TABLE stg_bank_statement (
    bank_ref      VARCHAR(20),
    account_no    VARCHAR(20),
    posting_date  DATE,
    value_date    DATE,
    description   VARCHAR(300),
    branch        VARCHAR(10),
    debit         BIGINT,
    credit        BIGINT,
    balance       BIGINT,
    txn_category  VARCHAR(20),   -- TRANSFER_IN, CASH_DEPOSIT, SETTLEMENT, TRANSFER_OUT, INTEREST, FEE, UNKNOWN
    ref_no        VARCHAR(30),
    key_station   VARCHAR(10),
    key_date      DATE,
    key_gateway   VARCHAR(20),
    counterparty  VARCHAR(150),     -- dinormalisasi seperti stg_refund.account_holder_key
    source_file   VARCHAR(200),
    source_row    INTEGER
);

-- HCM (dari ERP lewat integrasi sistem ke sistem)
CREATE TABLE stg_employee (
    employee_id       VARCHAR(10),
    employee_name     VARCHAR(150),
    department        VARCHAR(30),
    station_code      VARCHAR(10),
    position          VARCHAR(30),
    join_date         DATE,
    employment_status VARCHAR(10)
);

CREATE TABLE stg_shift_roster (
    roster_date   DATE,
    station_code  VARCHAR(10),
    shift_no      INTEGER,
    shift_start   TIME,
    shift_end     TIME,
    employee_id   VARCHAR(10),
    role          VARCHAR(30),
    window_no     INTEGER
);

-- Portal: log unggah per revisi
CREATE TABLE stg_upload_log (
    upload_id          VARCHAR(10),
    department         VARCHAR(20),
    source_type        VARCHAR(30),
    station_code       VARCHAR(10),
    period             VARCHAR(7),
    file_name          VARCHAR(200),
    object_key         VARCHAR(300),
    uploader_id        VARCHAR(10),
    uploaded_at        TIMESTAMP,
    deadline_at        TIMESTAMP,
    revision_no        INTEGER,
    validation_status  VARCHAR(10),
    validation_errors  VARCHAR(500),
    row_count          INTEGER,
    checksum_sha256    VARCHAR(64),
    approval_status    VARCHAR(12),
    approved_by        VARCHAR(10),
    approved_at        TIMESTAMP
);

-- Inventaris objek di storage (checksum yang dihitung ulang dari isi objek)
CREATE TABLE stg_object_inventory (
    file_name   VARCHAR(200),
    sha256      VARCHAR(64),
    size_bytes  BIGINT
);

-- Hasil semua aturan audit dan kepatuhan unggah
CREATE TABLE audit_exception (
    rule_code    VARCHAR(40)  NOT NULL,
    entity_type  VARCHAR(20)  NOT NULL,
    entity_id    VARCHAR(80)  NOT NULL,
    source_dept  VARCHAR(20),
    period       VARCHAR(7),
    detail       VARCHAR(500),
    PRIMARY KEY (rule_code, entity_id)
);
