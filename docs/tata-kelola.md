# Tata kelola data

Dokumen ini memetakan rancangan platform ke fungsi manajemen data (kerangka DAMA): data governance di tengah, dikelilingi data architecture, data development, data operations, data security, reference dan master data, metadata, data quality, serta data warehousing dan BI. Fokusnya kebijakan, peran, dan kontrol, bukan teknologi.

## 1. Data governance

### Struktur peran

| Peran | Diisi oleh | Tanggung jawab di platform |
|---|---|---|
| Data Governance Council | Direktur keuangan, kepala audit internal, kepala IT, perwakilan operasi stasiun | Menyetujui kebijakan wajib unggah, klasifikasi data, aturan audit baru, dan penyelesaian isu lintas departemen |
| Executive data steward | Kepala audit internal | Sponsor platform; menunjuk steward per domain; memutus sengketa definisi data |
| Data owner (business data steward) | Kepala stasiun (rekap, refund), manajer finance (rekening koran, bukti transfer, BAK), manajer IT (export ticketing), manajer HR (pegawai, shift) | Menyetujui unggahan periodik, menjawab exception di domainnya, menjaga definisi kolom |
| Data custodian | Tim IT dan data engineering | Menjalankan portal di AWS, pipeline, keamanan teknis, backup; tidak memutus makna data |
| Konsumen | Auditor internal, manajemen | Membaca dashboard dan exception; menindaklanjuti temuan |

Data owner adalah orang bisnis, bukan IT. Contoh: definisi "refund tunai yang sah" ditetapkan manajer operasi stasiun bersama finance, lalu IT menerjemahkannya ke aturan R11.

### Kebijakan wajib unggah

Kebijakan internal baru yang diusulkan untuk disahkan Data Governance Council:

1. Setiap departemen sumber (stasiun, finance, IT) wajib mengunggah data audit per periode bulanan hanya lewat portal audit terpusat. Pengiriman lewat surel, pesan, atau berbagi file tidak diakui sebagai penyerahan.
2. Tenggat unggah tanggal 5 bulan berikutnya pukul 23.59.
3. File harus lolos validasi template portal. Revisi paling banyak tiga kali per periode; lebih dari itu menjadi catatan kepatuhan.
4. Unggahan yang lolos validasi wajib disetujui data owner departemen di portal. Persetujuan menandakan data owner menjamin kelengkapan dan kebenaran isi.
5. File yang sudah disetujui tidak boleh diubah. Koreksi dilakukan dengan revisi baru yang tercatat, bukan dengan menimpa file.
6. Kewajiban unggah per departemen disimpan sebagai tabel referensi (`ref_upload_obligation`), sehingga perubahan kebijakan cukup mengubah data, bukan kode.

### Indikator kepatuhan unggah

Dihitung per departemen per periode dari log unggah (`sql/04_upload_compliance.sql`, view `upload_compliance_kpi`) dan ditampilkan di dashboard:

| Indikator | Definisi |
|---|---|
| Tingkat penyerahan | Kewajiban yang punya minimal satu unggahan / seluruh kewajiban |
| Tepat waktu | Unggahan pertama yang lolos validasi sebelum tenggat / seluruh kewajiban |
| Diterima | Revisi terakhir lolos validasi, disetujui data owner, dan checksum di storage sama dengan checksum saat unggah |
| Rata-rata revisi | Jumlah revisi / kewajiban; tinggi berarti template atau pemahaman pengunggah bermasalah |

Pelanggaran per kewajiban dicatat sebagai exception U01-U06 (`aturan-audit.md`).

### Manajemen isu

Setiap exception punya pemilik (data owner domain sumbernya). Alurnya: exception muncul di dashboard, data owner memberi penjelasan atau koreksi lewat revisi unggahan, auditor menilai apakah exception menjadi temuan. Exception yang tidak bisa diselesaikan antar departemen dibawa ke Data Governance Council.

## 2. Data architecture

- Arsitektur hybrid dengan AWS sebagai sumber kebenaran tunggal tempat semua komponen aktif berjalan, termasuk portal unggah; kantor pusat hanya menerima salinan raw, curated, final, dan exception sebagai arsip serta DR (`arsitektur.md`).
- Zona data: landing (karantina), raw (tidak bisa diubah), curated (hasil integrasi), analitik (star schema), export (salinan ke kantor pusat).
- Model data konseptual dan dimensional di `model-data.md`; enterprise data model disusun bottom-up dari sumber yang ada (export ticketing, rekap stasiun, dokumen finance, HCM) lalu dilengkapi subject area audit.
- Standar arsitektur: transformasi hanya di satu lapisan, tidak ada salinan data yang bisa diubah di luar AWS, semua sumber masuk lewat portal atau integrasi sistem yang tercatat.

## 3. Data development

| Aktivitas | Artefak di repo |
|---|---|
| Analisis kebutuhan informasi | Pertanyaan audit di `aturan-audit.md` (kebutuhan R01-R14, U01-U06) |
| Model konseptual dan logis | `model-data.md` |
| Model fisik dan DDL | `sql/01_staging_ddl.sql`, `sql/05_dw_ddl.sql` |
| Desain integrasi data (source-to-target) | `source-to-target.md` |
| Data uji | `data-dummy/` (data buatan dengan identitas fiktif, tidak memakai data asli) |
| Validasi kebutuhan | `etl/run_pipeline.py` membandingkan hasil aturan dengan kunci anomali |

Standar penamaan: tabel staging `stg_`, referensi `ref_`, dimensi `dim_`, fakta `fact_`; kolom memakai bahasa Inggris snake_case, nama kolom sumber yang salah eja (misalnya `bussiness_area`) diperbaiki di staging dan dicatat di S2T.

## 4. Data operations

| Aspek | Rancangan |
|---|---|
| Ketersediaan | Portal di ECS Fargate multi-AZ di belakang Application Load Balancer multi-AZ; layanan regional AWS multi-AZ; Redshift Multi-AZ; VPN dua tunnel; DR di kantor pusat. Gangguan di kantor pusat tidak menghentikan unggahan |
| Backup dan pemulihan | S3 Versioning dan Object Lock untuk raw; snapshot otomatis Redshift; salinan raw, curated, dan hasil UNLOAD ke kantor pusat lewat DataSync |
| Retensi | Raw disimpan sesuai masa retensi dokumen keuangan dan audit perusahaan (ditetapkan council bersama bagian hukum); curated dan analitik mengikuti siklus audit; data identitas mentah dihapus setelah tujuan audit selesai |
| Kinerja | Format Parquet dan partisi per periode di curated; star schema di Redshift untuk dashboard |
| Perubahan infrastruktur | AWS CDK, change set CloudFormation, drift detection |
| Data uji | Hanya data dummy; data produksi tidak boleh disalin ke lingkungan pengembangan |

## 5. Data security

### Klasifikasi data

| Kelas | Contoh | Kontrol |
|---|---|---|
| Rahasia (data pribadi) | NIK, nomor paspor, nama penumpang, nomor rekening penerima refund | Hanya di staging dengan akses terbatas; lapisan analitik memakai hash; dipindai Macie; kolom disaring Lake Formation |
| Rahasia (keuangan) | Rekening koran, bukti transfer, nominal BAK | Bucket finance dengan kunci KMS sendiri; akses baca hanya finance dan auditor |
| Internal | Rekap stasiun, export ticketing tanpa identitas, jadwal shift | Akses per departemen dan auditor |
| Internal terbatas | Hasil exception dan temuan audit | Auditor dan data owner terkait saja |

### Kontrol akses (CRUDE ringkas)

| Peran | Create | Read | Update | Delete | Execute |
|---|---|---|---|---|---|
| Pengunggah departemen | Unggahan departemennya | Unggahan departemennya | Revisi baru, bukan menimpa | Tidak | Tidak |
| Data owner | Tidak | Data domainnya, exception domainnya | Persetujuan unggahan | Tidak | Tidak |
| Auditor internal | Catatan temuan | Curated dan analitik semua domain, identitas mentah hanya dengan alasan tercatat | Status temuan | Tidak | Kueri Athena, dashboard |
| Data engineer | Objek pipeline | Metadata, sampel tanpa identitas | Kode pipeline lewat review | Tidak di raw | Job Glue |
| Administrator platform | Infrastruktur lewat CDK | Log | Lewat change set | Tidak di raw (Object Lock) | Deploy |

### Kontrol teknis

- **Lake Formation**: izin tabel, kolom, dan baris per departemen; auditor bisa membaca semua domain, data owner hanya domainnya.
- **KMS**: satu kunci per bucket departemen; pencabutan akses satu departemen cukup di kebijakan kuncinya.
- **CloudTrail data events**: setiap baca, tulis, dan hapus objek S3 tercatat. CloudTrail tidak mencatat perubahan baris di dalam database, karena itu Redshift audit logging (koneksi, pengguna, aktivitas kueri) diaktifkan, dan basis data portal mencatat aktivitasnya (bila memakai RDS: Database Activity Streams). Access log Application Load Balancer mencatat setiap permintaan ke portal.
- **Akses portal**: presigned URL berumur pendek, hanya untuk satu object key di bucket landing departemen pengguna. Pilihan ALB internal lewat VPN atau ALB publik dengan AWS WAF, serta login SSO lewat IAM Identity Center atau Cognito, belum diputuskan (`arsitektur.md`).
- **Integritas**: checksum SHA-256 saat unggah dibandingkan dengan checksum objek di storage (aturan U06); Object Lock mode compliance di raw.
- **Macie**: menemukan data pribadi yang muncul di file yang tidak semestinya, misalnya NIK di rekap stasiun.
- **Audit Manager**: mengumpulkan bukti kontrol (konfigurasi, log, persetujuan) per periode audit.
- **Artifact**: laporan kepatuhan AWS (misalnya ISO 27001, SOC) dilampirkan pada pengajuan rencana infrastruktur data.

### Regulasi

- **UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi**: dasar pemrosesan data penumpang untuk audit, minimisasi data (lapisan analitik tanpa identitas mentah), pembatasan akses, catatan pemrosesan, dan retensi. Transfer data pribadi ke luar negeri perlu kajian tersendiri.
- **PP No. 71 Tahun 2019 tentang Penyelenggaraan Sistem dan Transaksi Elektronik**: kewajiban penempatan dan pemulihan data; menjadi alasan memilih region Jakarta dan DR di dalam negeri.

## 6. Reference dan master data

| Data | Jenis | Sumber kebenaran | Pemakaian |
|---|---|---|---|
| Stasiun (kode, nama, business area) | Master | Export ticketing dan ERP | `dim_station`, kunci rekap |
| Pegawai | Master | HCM | `dim_employee`, aturan R07 |
| Jadwal shift | Transaksional pendukung | HCM | Aturan R07 |
| Mitra group order (pihak kedua BAK) | Master | CRM / BAK | `dim_group_order` |
| Kanal, metode bayar, gateway, tipe diskon | Referensi | Export ticketing | Dimensi kanal, pembayaran, diskon |
| Daftar aturan audit | Referensi | Data Governance Council | `ref_audit_rule`, `dim_audit_rule` |
| Kewajiban unggah | Referensi | Data Governance Council | `ref_upload_obligation` |
| Parameter kebijakan (batas refund, jendela pencocokan) | Referensi | Data owner terkait | `ref_policy` |

Masalah master data yang paling terasa: operator di export ticketing dicatat sebagai nama, bukan ID pegawai. Selama sistem ticketing belum menyimpan ID pegawai, pencocokan ke HCM memakai nama yang dinormalisasi (huruf besar, spasi dirapikan). Usulan perbaikan di sumber: sistem ticketing menyimpan `employee_id` operator.

## 7. Metadata

- **Teknis**: Glue Data Catalog (skema, partisi, lokasi), tercatat otomatis oleh crawler dan job.
- **Bisnis**: glosarium istilah audit (group order, BAK, refund, settlement, setoran tunai) dan definisi aturan di `aturan-audit.md`.
- **Operasional**: log unggah (siapa, kapan, periode, revisi, checksum, persetujuan), log job Glue, kolom `source_file` dan `source_row` di staging untuk menelusuri tiap baris ke file asal.
- **Lineage**: sumber, transformasi, dan target per kolom di `source-to-target.md`.

## 8. Data quality

| Dimensi | Pemeriksaan | Lokasi |
|---|---|---|
| Kelengkapan | Kolom wajib template; kewajiban unggah terpenuhi | Portal, U02 |
| Validitas | Format tanggal, kode stasiun, kode periode, domain nilai metode bayar | Portal, staging |
| Keunikan | `ticket_no` tunggal | R09 |
| Konsistensi | Harga asli, diskon, pajak, dan harga akhir saling cocok | R08 |
| Akurasi lintas sumber | Rekap stasiun vs export, BAK vs export, bukti transfer vs rekening koran | R01-R04, R10 |
| Ketepatan waktu | Unggahan sebelum tenggat | U01 |
| Integritas | Checksum unggah sama dengan checksum objek | U06 |

Perbedaan antara masalah kualitas data dan temuan audit: R08 dan R09 menandakan data sumber tidak sehat dan diserahkan ke data owner IT; R01-R07 dan R10-R14 menandakan kemungkinan penyimpangan transaksi dan diserahkan ke auditor.

## 9. Data warehousing dan BI

Star schema di `model-data.md`; dashboard Quick Sight menampilkan exception per aturan, stasiun, dan periode, tren nilai penjualan per kanal, refund per metode, dan indikator kepatuhan unggah. Rancangan dimensional ditulis netral alat supaya bisa dibangun di engine lain bila diperlukan.
