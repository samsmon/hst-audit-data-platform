# Source-to-target mapping

Pemetaan dari file sumber ke tabel staging dan dari staging ke model dimensional. Logika ditulis sebagai aturan transformasi yang bisa diterapkan di alat ETL apa pun; implementasi acuan ada di `etl/load_staging.py` (staging) dan `sql/06_dw_load.sql` (dimensional).

Konvensi: `trim` = buang spasi di awal dan akhir; `upper` = huruf besar; `rupiah` = buang `Rp`, titik ribuan, dan bagian desimal setelah koma lalu jadikan bilangan bulat.

## 1. Sumber ke staging

### Export ticketing (IT) → `stg_ticket_sales`

File: `export_ticketing_YYYY-MM.csv`, satu baris per tiket.

| Kolom sumber | Kolom target | Transformasi |
|---|---|---|
| `seq_no` | `seq_no` | Langsung |
| `periode` (`JAN-2025`) | `period` (`2025-01`) | Pisah di `-`, bulan singkatan Indonesia/Inggris ke angka |
| `passenger_name` | `passenger_name` | Langsung (data pribadi) |
| `nik_passport_no` | `id_number` | Baca sebagai teks agar nol di depan tidak hilang |
| `nik_passport_no` | `customer_hash` | SHA-256 dari salt + nilai; salt di secret manager |
| `bak` | `bak_id` | Integer, kosong = NULL |
| `nationality`, `order_no`, `ticket_no` | sama | Langsung |
| `ticketing_station` | `ticketing_station` | Langsung; `ONLINE` untuk kanal aplikasi dan web |
| `bussiness_area` | `business_area` | Perbaikan ejaan nama kolom |
| `office_no`, `window_no`, `shift_no` | sama | `window_no`, `shift_no` integer |
| `operator_name` | `operator_name` | `trim`; `SYSTEM` untuk kanal tanpa petugas |
| `ticketing_time` | `ticketing_ts` | Timestamp |
| `departure_date`, `purchase_date`, `arrival_date` | sama | Date |
| `purchase_time`, `departure_time`, `arrival_time` | sama | Time |
| `origin`, `destination` | `origin_name`, `destination_name` | Langsung |
| `origin_code`, `destination_code`, `train_no`, `cars_number`, `seat_number`, `seat_class`, `ticket_type` | sama | Langsung |
| `original_ticket_price`, `before_tax_price`, `after_tax_price` | sama | Bilangan bulat rupiah |
| `discount_type`, `discount_rate`, `tax_rate` | sama | Decimal |
| `ticketing_channel`, `payment_method`, `payment_gateway`, `trade_no`, `plat_trade_no`, `b2b_partner` | sama | Teks; `trade_no` dibaca sebagai teks |
| (nama file) | `source_file` | Lineage |

Baris ganda tidak dibuang di staging supaya bisa dideteksi (R09). Deduplikasi dilakukan di view `cur_ticket` (baris pertama per `ticket_no`).

### Rekap stasiun → `stg_station_recap`

Tiga layout berbeda diseragamkan ke satu tabel. Selama masa transisi ke template baku, ETL mengenali layout dari kode stasiun di nama file.

| Target | Stasiun A (`.xlsx`) | Stasiun B (`.csv` `;`) | Stasiun C (`.xlsx`) |
|---|---|---|---|
| Baris header | Baris 1 | Baris 1 | Baris 4 (baris 1-3 judul dan kosong) |
| Baris yang dibuang | Baris `TOTAL` (kolom `No` kosong) | - | - |
| `recap_level` | `ORDER` | `SHIFT` | `ORDER` |
| `sales_date` | `Tanggal` teks `dd/mm/yyyy` | `Tgl` teks `dd-mm-yyyy` | `Sales Date` sel tanggal Excel |
| `shift_no` | `Shift` | `Shift`: Pagi = 1, Siang = 2 | NULL |
| `window_no` | NULL | NULL | `Window` |
| `order_no` | `No. Order`, `trim` | NULL | `Order Number`, `trim` |
| `buyer_name` | `Nama Pemesan` | NULL | NULL |
| `ticket_count` | `Jml Tiket` | `Jml Tiket` | `Pax` |
| `payment_method` | `Metode Bayar` | NULL | `Payment` |
| `cash_amount` | NULL | `rupiah(Tunai)` | NULL |
| `noncash_amount` | NULL | `rupiah(Non Tunai)` | NULL |
| `total_amount` | `Total (Rp)` | `rupiah(Total)` | `Amount` |
| `station_code`, `period` | Dari nama file `rekap_<stasiun>_<periode>` | sama | sama |
| `source_file`, `source_row` | Nama file, nomor baris Excel | Nama file, nomor baris | Nama file, nomor baris Excel |

Cakupan rekap: transaksi kanal loket (`COUNTER`) dan group order (`B2B`) di stasiun itu. Penjualan mesin tiket dan online tidak masuk rekap stasiun.

### Laporan refund (stasiun, hasil ekstraksi dokumen) → `stg_refund`

Kolom hasil ekstraksi dipetakan langsung (`refund_id`, `station_code`, `refund_date`, `ticket_no`, `order_no`, `passenger_name`, `nationality`, `id_number`, `refund_method`, `bank_name`, `bank_account`, `account_holder`, `ticket_price`, `refund_amount`, `processed_by`, `approved_by`, `ocr_confidence`, `a2i_status`, `a2i_maker`, `a2i_checker`). `refund_date` menjadi date; `id_number` dan `bank_account` dibaca sebagai teks. `account_holder_key` = nama pemilik rekening dinormalisasi (huruf besar, huruf khusus diubah ke ASCII seperti `ß` menjadi `SS` dan `é` menjadi `E`, spasi tunggal) karena bank menulis nama tanpa huruf khusus.

### BAK group order (finance) → `stg_bak`

| Kolom sumber | Kolom target |
|---|---|
| `bak_id` | `bak_id` |
| `no_dokumen` | `bak_no` |
| `periode` | `period` |
| `tanggal_dokumen` | `document_date` (date) |
| `nama_pihak_kedua` | `counterparty_name` |
| `order_no` | `order_no` |
| `jumlah_tiket` | `ticket_count` |
| `total_nominal` | `total_amount` |
| `discount_type`, `discount_rate` | sama |
| `stasiun` | `station_code` |
| `disetujui_oleh` | `approved_by` (ID pegawai) |
| `bukti_transfer`, `manifest` | `transfer_proof_flag`, `manifest_flag` |
| `status`, `keterangan` | `status`, `remarks` |

### Bukti transfer (finance, hasil ekstraksi dokumen) → `stg_transfer_proof`

Kolom langsung; `uploaded_at` timestamp, `transfer_date` date. `reference_no` adalah kunci utama pencocokan ke rekening koran.

### Rekening koran (finance) → `stg_bank_statement`

| Kolom sumber | Kolom target | Transformasi |
|---|---|---|
| `No Ref Bank` | `bank_ref` | Langsung |
| `Tanggal`, `Tgl Valuta` | `posting_date`, `value_date` | `dd/mm/yyyy` ke date |
| `Keterangan` | `description` | `trim` |
| `Cabang` | `branch` | Teks |
| `Debet`, `Kredit`, `Saldo` | `debit`, `credit`, `balance` | Format `1.234.000,00` → `rupiah` |
| (konstanta) | `account_no` | Nomor rekening penampung |

Kunci pencocokan diturunkan dari `Keterangan` dengan pola berikut, dicoba berurutan:

| Pola keterangan | `txn_category` | Kolom yang diisi |
|---|---|---|
| `TRF FT<ref> <nama>` | `TRANSFER_IN` | `ref_no` = `FT<ref>`, `counterparty` = nama |
| `SETORAN TUNAI <stasiun> <dd/mm/yy>` | `CASH_DEPOSIT` | `key_station`, `key_date` |
| `STLM <gateway> <ddmmyy>` | `SETTLEMENT` | `key_gateway`, `key_date` (tanggal transaksi, settlement masuk H+1) |
| `TRF KE <nama> BANK <nama bank>` | `TRANSFER_OUT` | `counterparty` = nama penerima, dinormalisasi seperti `account_holder_key` |
| `BUNGA ...` | `INTEREST` | - |
| `BIAYA ...` | `FEE` | - |
| lainnya | `UNKNOWN` | - |

Pola ini bergantung pada format bank. Bila bank atau format berubah, pola diperbarui di satu tempat dan kredit `UNKNOWN` otomatis muncul sebagai exception R03, sehingga perubahan format tidak lolos diam-diam.

### HCM → `stg_employee`, `stg_shift_roster`

Kolom langsung; tanggal ke date, jam shift ke time. Data datang dari integrasi sistem (AppFlow), bukan portal.

### Portal → `stg_upload_log`, `stg_object_inventory`

`stg_upload_log` dipetakan langsung dari log portal (timestamp untuk `uploaded_at`, `deadline_at`, `approved_at`). `stg_object_inventory` berisi checksum SHA-256 yang dihitung ulang dari isi objek di storage (di AWS: checksum objek S3 atau S3 Inventory), dipakai untuk aturan U06.

## 2. Staging ke dimensional

| Target | Sumber | Aturan |
|---|---|---|
| `dim_date` | Gabungan tanggal beli, berangkat, posting, refund | `date_key` = YYYYMMDD |
| `dim_station` | `stg_ticket_sales` (kode dan nama asal) + baris `ONLINE` | Surrogate key urut kode |
| `dim_employee` | `stg_employee` | SCD tipe 1 |
| `dim_channel` | Distinct `ticketing_channel` | COUNTER → LOKET, TVM → MESIN, B2B → B2B, lainnya ONLINE |
| `dim_payment_method` | Distinct metode + gateway | `is_cash` = Y bila CASH |
| `dim_discount` | Distinct tipe + persentase | |
| `dim_customer` | Distinct `customer_hash` | Tanpa nama dan nomor identitas |
| `dim_group_order` | `stg_bak` | Nilai yang disetujui di BAK |
| `dim_source_dept` | Departemen di kewajiban unggah dan exception | |
| `dim_audit_rule` | `ref_audit_rule` | |
| `fact_ticket_sale` | `cur_ticket` | `discount_amount` = harga asli - sebelum pajak; `tax_amount` = setelah pajak - sebelum pajak; operator dicocokkan ke `dim_employee` lewat nama (NULL untuk SYSTEM) |
| `fact_bank_mutation` | `stg_bank_statement` | |
| `fact_refund` | `stg_refund` + `fact_ticket_sale` | `customer_key` dari tiket; NULL bila tiket tidak ditemukan (R12) |
| `fact_audit_exception` | `audit_exception` | Satu baris per aturan × entitas |
| `fact_upload_submission` | View `upload_submission` | Flag 0/1 tepat waktu, valid, disetujui, checksum cocok |

## 3. Urutan eksekusi

1. `01_staging_ddl.sql`, `02_reference_data.sql`
2. Muat staging (semua sumber)
3. `03_audit_rules.sql`, `04_upload_compliance.sql`
4. `05_dw_ddl.sql`, `06_dw_load.sql`

Aturan audit dijalankan sebelum model dimensional karena `fact_audit_exception` membaca hasilnya.
