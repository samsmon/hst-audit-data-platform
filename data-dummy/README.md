# data-dummy

Generator data dummy untuk semua sumber data audit penjualan tiket group order dan refund, periode Januari sampai Maret 2025. Nama orang dan perusahaan dibuat dengan Faker (`id_ID`), seed tetap, sehingga setiap kali dijalankan isinya sama. Hasil ditulis ke `output/` dan tidak di-commit.

## Cara menjalankan

```bash
pip install -r data-dummy/requirements.txt
python data-dummy/generate.py
```

Opsi: `--out <folder>` untuk folder hasil, `--seed <angka>` untuk seed lain (kunci anomali ikut berubah).

## Isi output

| File | Departemen | Isi |
|---|---|---|
| `it/export_ticketing_YYYY-MM.csv` | IT | Export sistem ticketing (system of record), satu baris per tiket, kolom lengkap termasuk stasiun penjualan, loket, shift, operator, kanal, gateway, mitra B2B, harga asli, diskon, pajak, kereta, gerbong, kursi |
| `stasiun/rekap_STA_YYYY-MM.xlsx` | Stasiun A | Rekap per order, tanggal teks `dd/mm/yyyy`, baris TOTAL di bawah |
| `stasiun/rekap_STB_YYYY-MM.csv` | Stasiun B | Rekap per tanggal dan shift (Pagi/Siang), pemisah titik koma, nominal teks `Rp1.234.000` |
| `stasiun/rekap_STC_YYYY-MM.xlsx` | Stasiun C | Rekap per order dengan baris judul, header bahasa Inggris, tanggal sel Excel |
| `stasiun/refund_<stasiun>_YYYY-MM.csv` | Stasiun | Laporan refund (transfer dan tunai) sebagai hasil ekstraksi dokumen scan, dengan skor keyakinan OCR dan status review maker-checker |
| `finance/bak_group_order_YYYY-MM.csv` | Finance | Berita acara kesepakatan group order: pihak kedua, order, jumlah tiket, total, diskon yang disetujui |
| `finance/bukti_transfer_YYYY-MM.csv` | Finance | Metadata bukti transfer: pengirim, bank, tanggal, nominal, nomor referensi, checksum file |
| `finance/rekening_koran_YYYY-MM.csv` | Finance | Mutasi rekening tanpa nomor order: transfer masuk, setoran tunai stasiun, settlement gateway, debit refund, bunga, biaya |
| `hcm/employees.csv` | HCM | Pegawai stasiun, finance, IT, audit internal |
| `hcm/shift_roster.csv` | HCM | Jadwal shift per stasiun, tanggal, loket |
| `portal/upload_log.csv` | Portal | Log unggah per revisi: pengunggah, departemen, periode, waktu, tenggat, status validasi, checksum, persetujuan data owner |
| `anomalies_truth.csv` | - | Kunci jawaban: daftar anomali yang sengaja disisipkan |
| `decoys_truth.csv` | - | Daftar kasus pengecoh: transaksi sah yang mirip anomali dan tidak boleh ditandai |

Laporan refund Stasiun C untuk Maret 2025 sengaja tidak dibuat karena kewajiban unggahnya dianggap tidak dipenuhi (anomali U02).

## Anomali terkontrol

58 anomali disisipkan dengan kode aturan yang sama dengan kueri di `sql/03_audit_rules.sql` dan `sql/04_upload_compliance.sql`. Logika tiap aturan ada di `docs/aturan-audit.md`.

| Kode | Jumlah | Pola |
|---|---|---|
| R01 | 3 | Bukti transfer tanpa kredit di rekening koran |
| R02 | 2 | Nominal bukti transfer lebih besar dari kredit yang masuk |
| R03 | 4 | Kredit masuk tanpa bukti transfer, setoran, atau settlement |
| R04 | 2 | Jumlah atau nilai tiket di export berbeda dengan BAK |
| R05 | 6 | Diskon GROUP di loket tanpa BAK |
| R06 | 3 | Diskon tiket tidak sama dengan diskon BAK |
| R07 | 5 | Operator tidak ada di jadwal shift |
| R08 | 4 | Perhitungan harga sebelum pajak tidak konsisten |
| R09 | 2 | Nomor tiket ganda |
| R10 | 7 | Rekap stasiun berbeda dengan export (nominal, order hilang, order fiktif, total shift) |
| R11 | 4 | Refund tunai kepada WNA |
| R12 | 2 | Refund untuk nomor tiket yang tidak ada |
| R13 | 2 | Refund 100% padahal batas 75% |
| R14 | 3 | Refund transfer tanpa debit di rekening koran |
| U01-U06 | 9 | Kepatuhan unggah: terlambat, tidak diunggah, gagal validasi, belum disetujui, revisi berlebih, checksum berubah |

Kebijakan fiktif yang dipakai generator: refund maksimal 75% harga tiket, refund tunai hanya untuk WNI dengan nominal paling banyak Rp300.000, tenggat unggah tanggal 5 bulan berikutnya, revisi paling banyak 3 kali.

## Kasus pengecoh

15 transaksi sah dibuat mirip anomali untuk menguji false positive: transfer tanpa nomor referensi yang masuk H+3, setoran tunai yang disetor keesokan harinya, petugas pengganti dengan tukar shift tercatat, selisih pembulatan Rp1, refund tunai WNI tepat di batas, nama penerima bertanda hubung, dan unggahan yang lolos tepat di detik tenggat. Daftarnya di `decoys_truth.csv`, rinciannya di `docs/aturan-audit.md`.
