# sql

Skrip SQL standar untuk staging, aturan audit, kepatuhan unggah, dan model dimensional. Diuji dengan DuckDB lewat `etl/run_pipeline.py`.

| File | Isi |
|---|---|
| `01_staging_ddl.sql` | Tabel staging per sumber, inventaris objek, dan `audit_exception` |
| `02_reference_data.sql` | Master data referensi: daftar aturan audit, kewajiban unggah per departemen, parameter kebijakan |
| `03_audit_rules.sql` | Aturan R01-R14 (pembayaran, group order, diskon, kualitas data, rekonsiliasi rekap, refund) |
| `04_upload_compliance.sql` | View `upload_submission`, aturan U01-U06, view indikator `upload_compliance_kpi` |
| `05_dw_ddl.sql` | Dimensi dan fakta star schema |
| `06_dw_load.sql` | Pengisian dimensi dan fakta dari staging |

## Catatan portabilitas

Skrip memakai SQL standar: `CREATE TABLE`, `ROW_NUMBER() OVER`, `FULL OUTER JOIN`, `EXTRACT`, `CASE`, `COALESCE`, `||`. Bagian yang mungkin perlu disesuaikan saat pindah engine:

- Aritmetika tanggal `tanggal + INTERVAL '3' DAY`. MySQL memakai `DATE_ADD(tanggal, INTERVAL 3 DAY)`.
- Operator `||` untuk menggabung teks. MySQL memakai `CONCAT()` kecuali mode `PIPES_AS_CONCAT` aktif.
- `FULL OUTER JOIN` tidak ada di MySQL; ganti dengan `LEFT JOIN` yang digabung `UNION` dengan `RIGHT JOIN`.
- Beberapa engine kolumnar tidak menegakkan `PRIMARY KEY` dan `REFERENCES`; batasan tetap ditulis sebagai dokumentasi model.
- Satu file berisi banyak pernyataan dipisah `;`. Alat yang hanya menerima satu pernyataan per eksekusi perlu memecahnya.
