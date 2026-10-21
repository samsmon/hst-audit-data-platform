# hst-audit-data-platform

Rancangan platform data hybrid untuk audit internal penjualan tiket group order dan refund pada HST, operator kereta cepat fiktif. Repo ini berisi desain, skrip SQL, ETL, dan data dummy untuk studi kasus data warehouse dan manajemen data enterprise.

Status: perencanaan. Belum ada yang di-deploy.

## Masalah

Data yang dibutuhkan audit internal datang dari tiga departemen dengan bentuk yang berbeda:

| Departemen | Data | Bentuk |
|---|---|---|
| Stasiun (A, B, C) | Rekap penjualan tiket per periode, laporan refund | Excel dan Google Sheet dengan layout berbeda tiap stasiun, laporan refund kertas |
| Finance | Rekening koran, bukti transfer, identitas pembeli, berita acara group order | PDF, scan, gambar |
| IT | Export sistem ticketing | Tabel |

Ketiga sumber tidak punya kunci bersama. Auditor harus mencocokkan order, group order, bukti transfer, dan mutasi rekening secara manual. Selisih seperti bukti transfer palsu, transfer tanpa order yang jelas, diskon tanpa persetujuan, dan refund tanpa bukti hanya bisa ditemukan dengan tangan.

## Rancangan

Server on-premise kantor pusat tetap dipakai, sedangkan pemrosesan dan analitik berjalan di AWS region Jakarta.

1. Stasiun dan finance mengunggah data lewat portal web self-hosted dengan template baku. Export sistem ticketing dan data ERP, HCM, serta CRM ikut dikirim ke AWS.
2. Data masuk ke bucket S3 landing per departemen, dipindai Amazon Macie untuk data pribadi, lalu dipindah ke zona raw yang dikunci S3 Object Lock.
3. Dokumen scan dipilah dengan Amazon Comprehend, diekstrak dengan Amazon Textract, dan hasil yang meragukan diperiksa manusia lewat Amazon A2I.
4. AWS Glue membersihkan, menyamakan skema, mencocokkan antar sumber, dan menandai anomali ke bucket curated.
5. Amazon Athena untuk kueri ad-hoc, Amazon Redshift untuk star schema, dan Amazon Quick Sight untuk dashboard audit.
6. Hasil akhir disalin kembali ke server kantor pusat sebagai arsip read-only dan cadangan bila region bermasalah.

AWS menjadi sumber kebenaran tunggal. Layanan berjalan Multi-AZ di region Jakarta. Kepatuhan dibantu AWS Audit Manager, AWS CloudTrail, Lake Formation, dan KMS.

## Struktur

| Folder | Isi |
|---|---|
| `docs/` | Dokumen desain: arsitektur, star schema, tata kelola data |
| `diagrams/` | Spesifikasi diagram arsitektur |
| `sql/` | DDL data warehouse, kueri analitik, aturan deteksi anomali |
| `etl/` | Skrip ETL |
| `data-dummy/` | Generator data dummy |

## Catatan data

Semua data di repo ini dummy. Nama operator, stasiun, pegawai, dan penumpang fiktif. Tidak ada data perusahaan yang sebenarnya.
