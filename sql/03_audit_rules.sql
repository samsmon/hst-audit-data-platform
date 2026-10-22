-- 03_audit_rules.sql
-- Aturan deteksi anomali lintas sumber. Setiap aturan menulis ke audit_exception
-- dengan satu baris per entitas. Logika dan alasan tiap aturan: docs/aturan-audit.md.
-- Jendela pencocokan tanggal ditulis sebagai INTERVAL '3' DAY (ref_policy.MATCH_WINDOW_DAYS).

-- Tiket unik: export bisa memuat baris ganda (lihat R09); aturan lain memakai baris pertama.
CREATE VIEW cur_ticket AS
SELECT *
FROM (
    SELECT t.*,
           ROW_NUMBER() OVER (PARTITION BY ticket_no ORDER BY period, seq_no) AS rn
    FROM stg_ticket_sales t
) x
WHERE rn = 1;

-- R01 Bukti transfer palsu: referensi tidak ada di rekening koran dan tidak ada
-- kredit transfer dengan nominal sama dalam jendela tanggal.
INSERT INTO audit_exception
SELECT 'R01_FAKE_TRANSFER_PROOF', 'proof', p.proof_id, 'FINANCE',
       CAST(EXTRACT(YEAR FROM p.transfer_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM p.transfer_date) AS VARCHAR), 2, '0'),
       'Ref ' || p.reference_no || ' senilai ' || CAST(p.amount AS VARCHAR) || ' tidak ditemukan di rekening koran'
FROM stg_transfer_proof p
WHERE NOT EXISTS (SELECT 1 FROM stg_bank_statement b
                  WHERE b.txn_category = 'TRANSFER_IN' AND b.ref_no = p.reference_no)
  AND NOT EXISTS (SELECT 1 FROM stg_bank_statement b
                  WHERE b.txn_category = 'TRANSFER_IN'
                    AND b.credit = p.amount
                    AND b.posting_date BETWEEN p.transfer_date AND p.transfer_date + INTERVAL '3' DAY);

-- R02 Nominal bukti transfer berbeda dengan kredit yang masuk (referensi cocok).
INSERT INTO audit_exception
SELECT 'R02_PROOF_AMOUNT_MISMATCH', 'proof', p.proof_id, 'FINANCE',
       CAST(EXTRACT(YEAR FROM p.transfer_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM p.transfer_date) AS VARCHAR), 2, '0'),
       'Bukti ' || CAST(p.amount AS VARCHAR) || ', kredit ' || CAST(b.credit AS VARCHAR) || ' (' || b.bank_ref || ')'
FROM stg_transfer_proof p
JOIN stg_bank_statement b
  ON b.txn_category = 'TRANSFER_IN' AND b.ref_no = p.reference_no
WHERE b.credit <> p.amount;

-- R03 Kredit tanpa sumber jelas: transfer masuk yang referensinya tidak ada di bukti
-- transfer, setoran tunai tanpa penjualan tunai di stasiun dan tanggal itu,
-- settlement tanpa transaksi gateway sehari sebelumnya, atau keterangan tak dikenali.
INSERT INTO audit_exception
SELECT 'R03_UNMATCHED_BANK_CREDIT', 'bank_mutation', b.bank_ref, 'FINANCE',
       CAST(EXTRACT(YEAR FROM b.posting_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM b.posting_date) AS VARCHAR), 2, '0'),
       b.txn_category || ': ' || b.description
FROM stg_bank_statement b
WHERE b.credit > 0
  AND (
       (b.txn_category = 'TRANSFER_IN'
        AND NOT EXISTS (SELECT 1 FROM stg_transfer_proof p WHERE p.reference_no = b.ref_no)
        AND NOT EXISTS (SELECT 1 FROM stg_transfer_proof p
                        WHERE p.amount = b.credit
                          AND b.posting_date BETWEEN p.transfer_date AND p.transfer_date + INTERVAL '3' DAY))
    OR (b.txn_category = 'CASH_DEPOSIT'
        AND NOT EXISTS (SELECT 1 FROM cur_ticket t
                        WHERE t.payment_method = 'CASH'
                          AND t.ticketing_station = b.key_station
                          AND t.purchase_date = b.key_date))
    OR (b.txn_category = 'SETTLEMENT'
        AND NOT EXISTS (SELECT 1 FROM cur_ticket t
                        WHERE t.payment_gateway = b.key_gateway
                          AND t.purchase_date = b.key_date))
    OR b.txn_category = 'UNKNOWN'
  );

-- R04 Group order: jumlah tiket atau total nilai di export berbeda dengan BAK.
INSERT INTO audit_exception
SELECT 'R04_BAK_TICKET_MISMATCH', 'bak', k.bak_no, 'FINANCE', k.period,
       'BAK ' || CAST(k.ticket_count AS VARCHAR) || ' tiket / ' || CAST(k.total_amount AS VARCHAR) ||
       ', export ' || CAST(COALESCE(t.n, 0) AS VARCHAR) || ' tiket / ' || CAST(COALESCE(t.total, 0) AS VARCHAR)
FROM stg_bak k
LEFT JOIN (SELECT bak_id, COUNT(*) AS n, SUM(after_tax_price) AS total
           FROM cur_ticket WHERE bak_id IS NOT NULL GROUP BY bak_id) t
  ON t.bak_id = k.bak_id
WHERE COALESCE(t.n, 0) <> k.ticket_count
   OR COALESCE(t.total, 0) <> k.total_amount;

-- R05 Diskon group tanpa BAK (pola diskon titipan).
INSERT INTO audit_exception
SELECT 'R05_UNAUTHORIZED_DISCOUNT', 'ticket', t.ticket_no, 'IT', t.period,
       'Diskon ' || t.discount_type || ' ' || CAST(t.discount_rate AS VARCHAR) || '% oleh ' || t.operator_name ||
       ' di ' || t.ticketing_station
FROM cur_ticket t
WHERE t.discount_type = 'GROUP'
  AND (t.bak_id IS NULL OR NOT EXISTS (SELECT 1 FROM stg_bak k WHERE k.bak_id = t.bak_id));

-- R06 Diskon tiket tidak sama dengan diskon yang disetujui di BAK.
INSERT INTO audit_exception
SELECT 'R06_DISCOUNT_NOT_PER_BAK', 'ticket', t.ticket_no, 'IT', t.period,
       'Tiket ' || CAST(t.discount_rate AS VARCHAR) || '%, BAK ' || k.bak_no || ' ' || CAST(k.discount_rate AS VARCHAR) || '%'
FROM cur_ticket t
JOIN stg_bak k ON k.bak_id = t.bak_id
WHERE t.discount_rate <> k.discount_rate;

-- R07 Transaksi loket/B2B oleh operator yang tidak terjadwal di stasiun, tanggal,
-- dan shift itu menurut HCM (segregation of duties).
INSERT INTO audit_exception
SELECT 'R07_OPERATOR_NOT_ON_SHIFT', 'ticket', t.ticket_no, 'IT', t.period,
       t.operator_name || ' tidak terjadwal di ' || t.ticketing_station || ' shift ' || CAST(t.shift_no AS VARCHAR) ||
       ' tanggal ' || CAST(t.purchase_date AS VARCHAR)
FROM cur_ticket t
WHERE t.ticketing_channel IN ('COUNTER', 'B2B')
  AND NOT EXISTS (
      SELECT 1
      FROM stg_shift_roster r
      JOIN stg_employee e ON e.employee_id = r.employee_id
      WHERE UPPER(TRIM(e.employee_name)) = UPPER(TRIM(t.operator_name))
        AND r.roster_date = t.purchase_date
        AND r.station_code = t.ticketing_station
        AND r.shift_no = t.shift_no);

-- R08 Harga tidak konsisten: harga asli -> diskon -> sebelum pajak -> setelah pajak.
INSERT INTO audit_exception
SELECT 'R08_PRICE_CALC_ERROR', 'ticket', t.ticket_no, 'IT', t.period,
       'original ' || CAST(t.original_ticket_price AS VARCHAR) || ', diskon ' || CAST(t.discount_rate AS VARCHAR) ||
       '%, before ' || CAST(t.before_tax_price AS VARCHAR) || ', after ' || CAST(t.after_tax_price AS VARCHAR)
FROM cur_ticket t
WHERE ABS(t.before_tax_price - ROUND(t.original_ticket_price * (100 - t.discount_rate) / 100, 0))
        > (SELECT policy_value FROM ref_policy WHERE policy_key = 'PRICE_TOLERANCE')
   OR ABS(t.after_tax_price - ROUND(t.before_tax_price * (1 + t.tax_rate), 0))
        > (SELECT policy_value FROM ref_policy WHERE policy_key = 'PRICE_TOLERANCE');

-- R09 Nomor tiket ganda di export.
INSERT INTO audit_exception
SELECT 'R09_DUPLICATE_TICKET', 'ticket', ticket_no, 'IT', MIN(period),
       CAST(COUNT(*) AS VARCHAR) || ' baris dengan ticket_no sama'
FROM stg_ticket_sales
GROUP BY ticket_no
HAVING COUNT(*) > 1;

-- R10a Rekap stasiun level order dibandingkan dengan export (loket + B2B di stasiun itu).
INSERT INTO audit_exception
SELECT 'R10_RECAP_MISMATCH', 'recap',
       COALESCE(r.station_code, i.station_code) || '|' || COALESCE(r.order_no, i.order_no),
       'STASIUN', COALESCE(r.period, i.period),
       CASE WHEN r.order_no IS NULL THEN 'Order ada di export, tidak ada di rekap'
            WHEN i.order_no IS NULL THEN 'Order ada di rekap, tidak ada di export'
            ELSE 'Rekap ' || CAST(r.total_amount AS VARCHAR) || ' / ' || CAST(r.ticket_count AS VARCHAR) ||
                 ' tiket, export ' || CAST(i.total_amount AS VARCHAR) || ' / ' || CAST(i.ticket_count AS VARCHAR) || ' tiket'
       END
FROM (SELECT * FROM stg_station_recap WHERE recap_level = 'ORDER') r
FULL OUTER JOIN (
    SELECT ticketing_station AS station_code, period, order_no,
           COUNT(*) AS ticket_count, SUM(after_tax_price) AS total_amount
    FROM cur_ticket
    WHERE ticketing_channel IN ('COUNTER', 'B2B')
      AND ticketing_station IN (SELECT DISTINCT station_code FROM stg_station_recap WHERE recap_level = 'ORDER')
    GROUP BY ticketing_station, period, order_no
) i
  ON i.station_code = r.station_code AND i.order_no = r.order_no
WHERE r.order_no IS NULL OR i.order_no IS NULL
   OR r.total_amount <> i.total_amount OR r.ticket_count <> i.ticket_count;

-- R10b Rekap stasiun level shift dibandingkan dengan agregat export per tanggal dan shift.
INSERT INTO audit_exception
SELECT 'R10_RECAP_MISMATCH', 'recap',
       COALESCE(r.station_code, i.station_code) || '|' || CAST(COALESCE(r.sales_date, i.sales_date) AS VARCHAR) ||
       '|' || CAST(COALESCE(r.shift_no, i.shift_no) AS VARCHAR),
       'STASIUN', COALESCE(r.period, i.period),
       'Rekap ' || CAST(COALESCE(r.total_amount, 0) AS VARCHAR) || ', export ' || CAST(COALESCE(i.total_amount, 0) AS VARCHAR)
FROM (SELECT * FROM stg_station_recap WHERE recap_level = 'SHIFT') r
FULL OUTER JOIN (
    SELECT ticketing_station AS station_code, period, purchase_date AS sales_date, shift_no,
           COUNT(*) AS ticket_count, SUM(after_tax_price) AS total_amount
    FROM cur_ticket
    WHERE ticketing_channel IN ('COUNTER', 'B2B')
      AND ticketing_station IN (SELECT DISTINCT station_code FROM stg_station_recap WHERE recap_level = 'SHIFT')
    GROUP BY ticketing_station, period, purchase_date, shift_no
) i
  ON i.station_code = r.station_code AND i.sales_date = r.sales_date AND i.shift_no = r.shift_no
WHERE r.station_code IS NULL OR i.station_code IS NULL
   OR r.total_amount <> i.total_amount OR r.ticket_count <> i.ticket_count;

-- R11 Refund tunai melanggar kebijakan: penerima WNA atau nominal di atas batas.
INSERT INTO audit_exception
SELECT 'R11_CASH_REFUND_POLICY', 'refund', f.refund_id, 'STASIUN',
       CAST(EXTRACT(YEAR FROM f.refund_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM f.refund_date) AS VARCHAR), 2, '0'),
       'Refund tunai ' || CAST(f.refund_amount AS VARCHAR) || ' kepada ' || f.nationality
FROM stg_refund f
WHERE f.refund_method = 'CASH'
  AND (f.nationality <> 'IDN'
       OR f.refund_amount > (SELECT policy_value FROM ref_policy WHERE policy_key = 'CASH_REFUND_MAX_AMOUNT'));

-- R12 Refund untuk tiket yang tidak ada di export.
INSERT INTO audit_exception
SELECT 'R12_REFUND_TICKET_NOT_FOUND', 'refund', f.refund_id, 'STASIUN',
       CAST(EXTRACT(YEAR FROM f.refund_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM f.refund_date) AS VARCHAR), 2, '0'),
       'Tiket ' || f.ticket_no || ' tidak ada di export'
FROM stg_refund f
WHERE NOT EXISTS (SELECT 1 FROM cur_ticket t WHERE t.ticket_no = f.ticket_no);

-- R13 Nominal refund melebihi batas kebijakan, dihitung dari harga di export (bukan di laporan refund).
INSERT INTO audit_exception
SELECT 'R13_REFUND_AMOUNT_EXCEEDS', 'refund', f.refund_id, 'STASIUN',
       CAST(EXTRACT(YEAR FROM f.refund_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM f.refund_date) AS VARCHAR), 2, '0'),
       'Refund ' || CAST(f.refund_amount AS VARCHAR) || ' dari harga ' || CAST(t.after_tax_price AS VARCHAR)
FROM stg_refund f
JOIN cur_ticket t ON t.ticket_no = f.ticket_no
WHERE f.refund_amount > ROUND(t.after_tax_price * (SELECT policy_value FROM ref_policy WHERE policy_key = 'REFUND_MAX_RATE'), 0)
                        + (SELECT policy_value FROM ref_policy WHERE policy_key = 'PRICE_TOLERANCE');

-- R14 Refund transfer tanpa debit yang cocok (nama penerima, nominal, jendela tanggal).
-- Nama dibandingkan dalam bentuk ternormalisasi ETL karena bank menulis nama tanpa huruf khusus.
INSERT INTO audit_exception
SELECT 'R14_REFUND_NO_BANK_DEBIT', 'refund', f.refund_id, 'STASIUN',
       CAST(EXTRACT(YEAR FROM f.refund_date) AS VARCHAR) || '-' ||
       LPAD(CAST(EXTRACT(MONTH FROM f.refund_date) AS VARCHAR), 2, '0'),
       'Refund ' || CAST(f.refund_amount AS VARCHAR) || ' ke ' || f.account_holder || ' tidak ada di mutasi debit'
FROM stg_refund f
WHERE f.refund_method = 'TRANSFER'
  AND NOT EXISTS (SELECT 1 FROM stg_bank_statement b
                  WHERE b.txn_category = 'TRANSFER_OUT'
                    AND b.debit = f.refund_amount
                    AND b.counterparty = f.account_holder_key
                    AND b.posting_date BETWEEN f.refund_date AND f.refund_date + INTERVAL '3' DAY);
