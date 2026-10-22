# Aturan audit

Setiap aturan menjawab satu pertanyaan audit, memakai sumber tertentu, dan mencocokkan dengan kunci tertentu. Hasilnya satu baris per entitas di `audit_exception`. Kueri ada di `sql/03_audit_rules.sql` (R01-R14) dan `sql/04_upload_compliance.sql` (U01-U06); parameter kebijakan di `ref_policy`.

Exception bukan temuan. Exception adalah daftar yang perlu diperiksa; auditor yang menilai apakah suatu exception menjadi temuan setelah meminta penjelasan data owner.

## Ringkasan

| Kode | Pertanyaan | Sumber | Kunci | Risiko |
|---|---|---|---|---|
| R01 | Apakah bukti transfer group order benar-benar diikuti dana masuk? | Bukti transfer, rekening koran | Nomor referensi; cadangan nominal + 3 hari | Tinggi |
| R02 | Apakah nominal di bukti transfer sama dengan dana yang masuk? | Bukti transfer, rekening koran | Nomor referensi | Tinggi |
| R03 | Apakah setiap dana masuk punya sumber yang jelas? | Rekening koran, bukti transfer, export | Referensi; stasiun + tanggal; gateway + tanggal | Sedang |
| R04 | Apakah tiket group order sesuai BAK? | BAK, export | `bak_id` | Tinggi |
| R05 | Apakah ada diskon group tanpa BAK? | Export, BAK | `bak_id` | Tinggi |
| R06 | Apakah diskon tiket sama dengan yang disetujui BAK? | Export, BAK | `bak_id` | Tinggi |
| R07 | Apakah transaksi loket dilakukan oleh petugas yang sedang bertugas? | Export, HCM | Nama + stasiun + tanggal + shift | Sedang |
| R08 | Apakah harga tiket dihitung benar? | Export | Per baris | Rendah |
| R09 | Apakah nomor tiket unik? | Export | `ticket_no` | Sedang |
| R10 | Apakah rekap stasiun sama dengan sistem? | Rekap stasiun, export | Stasiun + order, atau stasiun + tanggal + shift | Sedang |
| R11 | Apakah refund tunai sesuai kebijakan? | Laporan refund | Per baris | Tinggi |
| R12 | Apakah refund berasal dari tiket yang ada? | Laporan refund, export | `ticket_no` | Tinggi |
| R13 | Apakah nilai refund sesuai batas? | Laporan refund, export | `ticket_no` | Tinggi |
| R14 | Apakah refund transfer benar-benar dibayarkan? | Laporan refund, rekening koran | Nama + nominal + 3 hari | Sedang |
| U01-U06 | Apakah departemen memenuhi kewajiban unggah? | Log unggah, kewajiban, inventaris objek | Departemen + sumber + stasiun + periode | Rendah-Tinggi |

## Aturan pembayaran group order

### R01 Bukti transfer tanpa dana masuk

- **Pola yang dicari**: bukti transfer palsu atau hasil suntingan; group order diproses padahal dana tidak pernah diterima.
- **Logika**: bukti transfer ditandai bila tidak ada kredit `TRANSFER_IN` dengan nomor referensi yang sama, dan juga tidak ada kredit `TRANSFER_IN` dengan nominal sama dalam 3 hari sejak tanggal transfer di bukti.
- **Kenapa ada cadangan nominal**: keterangan transfer kadang terpotong atau nomor referensi salah ketik saat OCR. Kalau nominal dan tanggal cocok, bukti tidak langsung dianggap palsu.
- **Tindak lanjut**: minta finance menunjukkan mutasi yang sesuai; bila tidak ada, telusuri siapa yang menerima bukti dan memproses order.

### R02 Nominal bukti berbeda dengan kredit

- **Pola**: bukti transfer diubah supaya nominal tampak penuh, padahal yang ditransfer kurang.
- **Logika**: bukti dan kredit cocok di nomor referensi, tetapi `credit <> amount`.

### R03 Kredit tanpa sumber jelas

- **Pola**: dana masuk yang tidak bisa dijelaskan, misalnya pembayaran di luar sistem atau dana titipan.
- **Logika**: kredit ditandai bila
  - `TRANSFER_IN` dan referensinya tidak ada di bukti transfer serta tidak cocok nominal + tanggal dengan bukti mana pun; atau
  - `CASH_DEPOSIT` untuk stasiun dan tanggal yang tidak punya penjualan tunai; atau
  - `SETTLEMENT` untuk gateway dan tanggal yang tidak punya transaksi gateway; atau
  - keterangan tidak dikenali (`UNKNOWN`).
- Bunga (`INTEREST`) dikecualikan.

### R04 Tiket group order tidak sesuai BAK

- **Pola**: tiket ditambahkan di sistem melebihi kesepakatan, atau nilai tiket berubah setelah BAK ditandatangani.
- **Logika**: jumlah tiket atau total `after_tax_price` di export untuk `bak_id` berbeda dengan `ticket_count` atau `total_amount` di BAK.

## Aturan diskon

### R05 Diskon group tanpa BAK

- **Pola**: diskon titipan. Petugas memberi diskon group pada transaksi loket biasa tanpa kesepakatan resmi.
- **Logika**: `discount_type = 'GROUP'` dan `bak_id` kosong atau tidak ada di BAK.

### R06 Diskon tidak sesuai BAK

- **Pola**: sebagian tiket dalam group order diberi diskon lebih besar dari yang disetujui.
- **Logika**: `discount_rate` tiket berbeda dengan `discount_rate` BAK yang ditautkan. Biasanya muncul bersama R04 karena total nilai ikut berubah.

### R07 Operator tidak terjadwal

- **Pola**: transaksi dibuat dengan akun petugas yang tidak sedang bertugas (akun dipinjam atau dipakai orang lain). Ini kontrol segregation of duties dengan data HCM.
- **Logika**: untuk kanal `COUNTER` dan `B2B`, tidak ada baris jadwal shift dengan nama pegawai (dinormalisasi `upper` + `trim`) yang sama, di stasiun, tanggal, dan shift yang sama.
- **Keterbatasan**: export menyimpan nama operator, bukan ID pegawai. Nama ganda atau salah ketik bisa membuat false positive; perbaikan jangka panjang ada di sistem ticketing (lihat `tata-kelola.md`, master data).

## Aturan kualitas data

### R08 Perhitungan harga tidak konsisten

- **Logika**: `before_tax_price` berbeda lebih dari Rp1 dari `round(original_ticket_price × (100 - discount_rate) / 100)`, atau `after_tax_price` berbeda lebih dari Rp1 dari `round(before_tax_price × (1 + tax_rate))`.
- Toleransi Rp1 menampung perbedaan cara pembulatan antar sistem.

### R09 Nomor tiket ganda

- **Logika**: `ticket_no` muncul lebih dari satu kali di export. Aturan lain memakai baris pertama saja supaya nilai tidak terhitung dua kali.

## Aturan rekonsiliasi rekap

### R10 Rekap stasiun berbeda dengan export

- **Pola**: rekap manual tidak sama dengan sistem, karena salah input atau karena ada transaksi yang disembunyikan atau ditambahkan.
- **Logika untuk rekap per order** (Stasiun A, C): `FULL OUTER JOIN` rekap dengan agregat export per stasiun dan `order_no` (kanal loket dan B2B). Ditandai bila order hanya ada di satu sisi, atau jumlah tiket atau nominal berbeda.
- **Logika untuk rekap per shift** (Stasiun B): sama, dengan kunci stasiun + tanggal + shift.
- **ID entitas**: `stasiun|order_no` atau `stasiun|tanggal|shift`.

## Aturan refund

### R11 Refund tunai melanggar kebijakan

- **Pola**: refund dibayar tunai kepada WNA, sehingga penerima sulit ditelusuri dan dana mudah diselewengkan.
- **Kebijakan acuan** (`ref_policy`): refund tunai hanya untuk WNI dengan nominal paling banyak Rp300.000; selebihnya wajib transfer ke rekening atas nama pemesan.
- **Logika**: `refund_method = 'CASH'` dan (`nationality <> 'IDN'` atau `refund_amount > 300000`).

### R12 Refund untuk tiket yang tidak ada

- **Logika**: `ticket_no` di laporan refund tidak ada di export.
- Bisa berarti refund fiktif atau salah baca OCR; karena itu dokumen dengan confidence rendah sudah melewati review A2I sebelum masuk aturan.

### R13 Nilai refund melebihi batas

- **Logika**: `refund_amount > round(after_tax_price × 0.75) + 1`, dengan harga diambil dari export, bukan dari laporan refund. Harga di laporan refund bisa saja ikut diubah.

### R14 Refund transfer tanpa debit

- **Pola**: refund dicatat sudah dibayar, padahal dana tidak keluar, atau dana keluar ke rekening lain.
- **Logika**: refund `TRANSFER` tanpa debit `TRANSFER_OUT` dengan nama penerima sama, nominal sama, dalam 3 hari sejak tanggal refund.
- **Normalisasi nama**: kedua sisi dibandingkan dalam bentuk ASCII huruf besar. Tanda baca juga dibuang, karena bank menulis nama tanpa tanda baca. Uji awal menemukan false positive untuk penerima bernama `Gieß`, yang di rekening koran tertulis `GIESS`; `UPPER` di SQL tidak mengubah `ß`, jadi normalisasi dipindah ke ETL. Uji dengan kasus pengecoh kemudian menemukan nama bertanda hubung (`Andi-Pratama`) yang di bank tertulis `ANDI PRATAMA`.

## Aturan kepatuhan unggah

Dihitung dari view `upload_submission`: satu baris per kewajiban (departemen, sumber, stasiun, periode) dari `ref_upload_obligation`, digabung dengan log unggah dan inventaris objek. ID entitas: `departemen|sumber|stasiun|periode`.

| Kode | Logika | Risiko |
|---|---|---|
| U01 Terlambat | Unggahan pertama yang lolos validasi setelah `deadline_at` | Rendah |
| U02 Tidak diunggah | Tidak ada satu pun unggahan untuk kewajiban itu | Sedang |
| U03 Gagal validasi | Revisi terakhir berstatus `FAILED` | Sedang |
| U04 Belum disetujui | Revisi terakhir `PASSED` tetapi persetujuan data owner bukan `APPROVED` | Rendah |
| U05 Revisi berlebih | Jumlah revisi melebihi `max_revision` (3) | Rendah |
| U06 Checksum berubah | Checksum revisi terakhir di log berbeda dengan checksum objek di storage | Tinggi |

U06 berarti isi file berubah setelah diunggah dan disetujui. Dengan Object Lock di raw, hal ini seharusnya tidak mungkin terjadi di AWS; aturan ini menjaga titik lemah sebelum objek terkunci dan membuktikan kontrolnya berjalan.

## Hasil uji dengan data dummy

Data dummy berisi 58 anomali terkontrol (`data-dummy/output/anomalies_truth.csv`). Hasil `etl/run_pipeline.py` dengan DuckDB:

| Kode | Disisipkan | Terdeteksi | Cocok | False positive | False negative |
|---|---|---|---|---|---|
| R01 | 3 | 3 | 3 | 0 | 0 |
| R02 | 2 | 2 | 2 | 0 | 0 |
| R03 | 4 | 4 | 4 | 0 | 0 |
| R04 | 2 | 2 | 2 | 0 | 0 |
| R05 | 6 | 6 | 6 | 0 | 0 |
| R06 | 3 | 3 | 3 | 0 | 0 |
| R07 | 5 | 5 | 5 | 0 | 0 |
| R08 | 4 | 4 | 4 | 0 | 0 |
| R09 | 2 | 2 | 2 | 0 | 0 |
| R10 | 7 | 7 | 7 | 0 | 0 |
| R11 | 4 | 4 | 4 | 0 | 0 |
| R12 | 2 | 2 | 2 | 0 | 0 |
| R13 | 2 | 2 | 2 | 0 | 0 |
| R14 | 3 | 3 | 3 | 0 | 0 |
| U01-U06 | 9 | 9 | 9 | 0 | 0 |
| Total | 58 | 58 | 58 | 0 | 0 |

### Kasus pengecoh

Selain anomali, data dummy berisi 15 kasus pengecoh (`data-dummy/output/decoys_truth.csv`): transaksi sah yang sengaja dibuat mirip anomali. Tidak satu pun boleh muncul di `audit_exception`.

| Aturan sasaran | Pengecoh | Pola sah |
|---|---|---|
| R01, R03 | 2 bukti transfer + 2 kredit | Bank tidak mencantumkan nomor referensi pengirim, kredit masuk H+3 (batas jendela) |
| R03 | 2 setoran tunai | Penjualan tunai suatu hari baru disetor keesokan harinya |
| R07 | 2 tiket | Petugas pengganti dengan tukar shift yang tercatat di HCM; satu nama ditulis huruf kecil dengan spasi berlebih |
| R08 | 2 tiket | Selisih pembulatan Rp1, masih dalam toleransi |
| R11 | 2 refund | Refund tunai WNI tepat Rp300.000 |
| R14 | 2 refund | Nama bertanda hubung, bank menulis tanpa tanda baca, debit H+3 |
| U01 | 1 kewajiban unggah | Lolos validasi tepat pada detik tenggat |

Putaran pertama menandai 6 pengecoh sebagai anomali. Empat berasal dari mutasi transfer tanpa nomor referensi: parser ETL hanya mengenali format `TRF FT...`, sehingga mutasi `TRF DR ...` jatuh ke kategori tidak dikenal dan ditandai R03, lalu bukti transfernya ikut ditandai R01. Dua lainnya berasal dari nama bertanda hubung pada R14. Parser kemudian mengenali format transfer tanpa referensi sehingga pencocokan memakai nominal dan tanggal, dan normalisasi nama membuang tanda baca. Putaran kedua: 58 dari 58 anomali terdeteksi dan 0 dari 15 pengecoh ditandai.

Hasil sempurna ini menunjukkan kueri menjalankan logika yang dimaksud pada data dengan pola yang diketahui. Hasil ini tidak mengukur ketepatan pada data nyata: generator dan aturan dirancang bersama, sementara data nyata punya variasi format, salah ketik, dan kasus batas yang belum tercakup. Uji berikutnya sebaiknya memakai sampel data nyata yang sudah disamarkan dan dinilai auditor.
