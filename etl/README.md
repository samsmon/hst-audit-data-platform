# etl

Pipeline lokal sederhana untuk menguji rancangan tanpa layanan cloud: memuat file dummy ke tabel staging DuckDB, menjalankan aturan audit dan kepatuhan unggah, mengisi model dimensional, lalu membandingkan hasil deteksi dengan `anomalies_truth.csv` dan memastikan kasus pengecoh di `decoys_truth.csv` tidak ikut ditandai.

Skrip ini bukan job ETL produksi. Logika penyeragaman tiap sumber dicatat di `docs/source-to-target.md` supaya bisa dipindah ke alat ETL apa pun.

## Cara menjalankan

Dari root repo, setelah data dummy dibuat:

```bash
pip install -r etl/requirements.txt
python etl/run_pipeline.py
```

Hasil:

- `data-dummy/output/audit.duckdb`: database berisi staging, `audit_exception`, dimensi, dan fakta.
- `data-dummy/output/evaluation.csv`: perbandingan deteksi dengan kunci anomali per aturan.

## Isi

| File | Fungsi |
|---|---|
| `load_staging.py` | Membaca tiap sumber, menyeragamkan kolom, tipe, tanggal, dan nominal, mengurai keterangan rekening koran menjadi kunci pencocokan, menghitung hash pembeli dan checksum objek |
| `run_pipeline.py` | Menjalankan `sql/01` sampai `sql/06` berurutan dan mencetak evaluasi |

## Hasil uji terakhir

58 anomali disisipkan, 58 terdeteksi, tanpa false positive maupun false negative. Angka ini membuktikan logika kueri sesuai dengan pola yang disisipkan; belum mengukur ketepatan pada data nyata, karena generator dan aturan dirancang bersama.
