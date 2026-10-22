-- 02_reference_data.sql
-- Data referensi yang dikelola sebagai master data: daftar aturan audit dan
-- kewajiban unggah per departemen (kebijakan internal dalam bentuk tabel).

CREATE TABLE ref_audit_rule (
    rule_code    VARCHAR(40) PRIMARY KEY,
    rule_name    VARCHAR(100),
    category     VARCHAR(30),   -- PEMBAYARAN, GROUP_ORDER, DISKON, KUALITAS_DATA, REKONSILIASI, REFUND, KEPATUHAN_UNGGAH
    severity     VARCHAR(10),   -- TINGGI, SEDANG, RENDAH
    sources      VARCHAR(100)
);

INSERT INTO ref_audit_rule VALUES
('R01_FAKE_TRANSFER_PROOF',     'Bukti transfer tanpa kredit di rekening koran', 'PEMBAYARAN',       'TINGGI', 'FINANCE'),
('R02_PROOF_AMOUNT_MISMATCH',   'Nominal bukti transfer berbeda dengan kredit',  'PEMBAYARAN',       'TINGGI', 'FINANCE'),
('R03_UNMATCHED_BANK_CREDIT',   'Kredit rekening tanpa sumber jelas',            'PEMBAYARAN',       'SEDANG', 'FINANCE, IT'),
('R04_BAK_TICKET_MISMATCH',     'Jumlah atau nilai tiket berbeda dengan BAK',    'GROUP_ORDER',      'TINGGI', 'FINANCE, IT'),
('R05_UNAUTHORIZED_DISCOUNT',   'Diskon group tanpa BAK',                        'DISKON',           'TINGGI', 'IT'),
('R06_DISCOUNT_NOT_PER_BAK',    'Diskon tiket berbeda dengan diskon BAK',        'DISKON',           'TINGGI', 'FINANCE, IT'),
('R07_OPERATOR_NOT_ON_SHIFT',   'Operator tidak terjadwal di shift',             'DISKON',           'SEDANG', 'IT, HCM'),
('R08_PRICE_CALC_ERROR',        'Perhitungan harga tidak konsisten',             'KUALITAS_DATA',    'RENDAH', 'IT'),
('R09_DUPLICATE_TICKET',        'Nomor tiket ganda',                             'KUALITAS_DATA',    'SEDANG', 'IT'),
('R10_RECAP_MISMATCH',          'Rekap stasiun berbeda dengan export',           'REKONSILIASI',     'SEDANG', 'STASIUN, IT'),
('R11_CASH_REFUND_POLICY',      'Refund tunai melanggar kebijakan',              'REFUND',           'TINGGI', 'STASIUN'),
('R12_REFUND_TICKET_NOT_FOUND', 'Refund untuk tiket yang tidak ada',             'REFUND',           'TINGGI', 'STASIUN, IT'),
('R13_REFUND_AMOUNT_EXCEEDS',   'Nominal refund melebihi batas',                 'REFUND',           'TINGGI', 'STASIUN, IT'),
('R14_REFUND_NO_BANK_DEBIT',    'Refund transfer tanpa debit di rekening',       'REFUND',           'SEDANG', 'STASIUN, FINANCE'),
('U01_LATE_UPLOAD',             'Unggahan melewati tenggat',                     'KEPATUHAN_UNGGAH', 'RENDAH', 'PORTAL'),
('U02_MISSING_UPLOAD',          'Kewajiban unggah tidak dipenuhi',               'KEPATUHAN_UNGGAH', 'SEDANG', 'PORTAL'),
('U03_VALIDATION_FAILED',       'Revisi terakhir gagal validasi',                'KEPATUHAN_UNGGAH', 'SEDANG', 'PORTAL'),
('U04_NOT_APPROVED',            'Belum disetujui data owner',                    'KEPATUHAN_UNGGAH', 'RENDAH', 'PORTAL'),
('U05_EXCESSIVE_REVISION',      'Revisi melebihi batas',                         'KEPATUHAN_UNGGAH', 'RENDAH', 'PORTAL'),
('U06_CHECKSUM_MISMATCH',       'Isi objek berubah setelah diunggah',            'KEPATUHAN_UNGGAH', 'TINGGI', 'PORTAL, STORAGE');

-- Kewajiban unggah per periode bulanan. station_code '-' untuk departemen non-stasiun.
CREATE TABLE ref_upload_obligation (
    department          VARCHAR(20),
    source_type         VARCHAR(30),
    station_code        VARCHAR(10),
    deadline_day        INTEGER,       -- tanggal tenggat di bulan berikutnya
    max_revision        INTEGER,
    data_owner_position VARCHAR(30),
    PRIMARY KEY (department, source_type, station_code)
);

INSERT INTO ref_upload_obligation VALUES
('STASIUN', 'REKAP_PENJUALAN',  'STA', 5, 3, 'KEPALA_STASIUN'),
('STASIUN', 'REKAP_PENJUALAN',  'STB', 5, 3, 'KEPALA_STASIUN'),
('STASIUN', 'REKAP_PENJUALAN',  'STC', 5, 3, 'KEPALA_STASIUN'),
('STASIUN', 'LAPORAN_REFUND',   'STA', 5, 3, 'KEPALA_STASIUN'),
('STASIUN', 'LAPORAN_REFUND',   'STB', 5, 3, 'KEPALA_STASIUN'),
('STASIUN', 'LAPORAN_REFUND',   'STC', 5, 3, 'KEPALA_STASIUN'),
('FINANCE', 'REKENING_KORAN',   '-',   5, 3, 'MANAGER_FINANCE'),
('FINANCE', 'BUKTI_TRANSFER',   '-',   5, 3, 'MANAGER_FINANCE'),
('FINANCE', 'BAK_GROUP_ORDER',  '-',   5, 3, 'MANAGER_FINANCE'),
('IT',      'EXPORT_TICKETING', '-',   5, 3, 'MANAGER_IT');

-- Kebijakan refund dan diskon sebagai parameter, bukan angka di dalam kueri
CREATE TABLE ref_policy (
    policy_key   VARCHAR(40) PRIMARY KEY,
    policy_value DECIMAL(15,2),
    description  VARCHAR(200)
);

INSERT INTO ref_policy VALUES
('REFUND_MAX_RATE',        0.75,   'Refund maksimal 75% dari harga tiket'),
('CASH_REFUND_MAX_AMOUNT', 300000, 'Refund tunai hanya untuk WNI dan maksimal Rp300.000'),
('MATCH_WINDOW_DAYS',      3,      'Selisih hari maksimal saat mencocokkan transaksi dengan mutasi'),
('PRICE_TOLERANCE',        1,      'Toleransi pembulatan harga (rupiah)');
