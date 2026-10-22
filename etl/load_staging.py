"""Memuat file sumber dari data-dummy/output ke tabel staging DuckDB.

Setiap fungsi load_* membaca satu jenis sumber, menyeragamkan nama kolom, tipe,
format tanggal, dan nominal, lalu menyisipkan ke tabel staging. Aturan pemetaan
kolom tercatat di docs/source-to-target.md.
"""
from __future__ import annotations

import hashlib
import os
import re
import unicodedata
from pathlib import Path

import duckdb
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
MONTHS = {"JAN": "01", "FEB": "02", "MAR": "03", "APR": "04", "MEI": "05", "MAY": "05", "JUN": "06",
          "JUL": "07", "AGU": "08", "AUG": "08", "SEP": "09", "OKT": "10", "OCT": "10", "NOV": "11",
          "DES": "12", "DEC": "12"}
# Di lingkungan nyata salt disimpan di secret manager, bukan di kode.
HASH_SALT = os.environ.get("HST_HASH_SALT", "demo-salt-ganti-di-produksi")


def insert(con: duckdb.DuckDBPyConnection, table: str, df: pd.DataFrame) -> int:
    """Susun ulang kolom sesuai urutan DDL lalu sisipkan."""
    cols = [c[0] for c in con.execute(f"SELECT * FROM {table} LIMIT 0").description]
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise ValueError(f"{table}: kolom tidak ada di sumber: {missing}")
    frame = df[cols]
    con.register("frame", frame)
    con.execute(f"INSERT INTO {table} SELECT * FROM frame")
    con.unregister("frame")
    return len(frame)


def name_key(value) -> str | None:
    """Kunci nama untuk pencocokan lintas sumber: ASCII, huruf besar, tanpa tanda baca, spasi tunggal
    ('Gieß' -> 'GIESS', 'Andi-Pratama' -> 'ANDI PRATAMA'), karena bank menulis nama tanpa huruf khusus dan tanda baca."""
    if value is None or pd.isna(value):
        return None
    s = unicodedata.normalize("NFKD", str(value).upper()).encode("ascii", "ignore").decode()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    return " ".join(s.split())


def parse_rupiah(value) -> int:
    """'Rp1.234.000', '1.234.000,00', 1234000 -> 1234000"""
    if pd.isna(value):
        return 0
    if isinstance(value, (int, float)):
        return int(value)
    s = str(value).replace("Rp", "").replace(" ", "")
    if "," in s:
        s = s.split(",")[0]
    return int(s.replace(".", "") or 0)


def load_ticket_sales(con, src: Path) -> int:
    n = 0
    for f in sorted((src / "it").glob("export_ticketing_*.csv")):
        df = pd.read_csv(f, dtype={"nik_passport_no": str, "trade_no": str, "plat_trade_no": str})
        mon, year = df["periode"].str.split("-", expand=True).iloc[:, 0], df["periode"].str.split("-", expand=True).iloc[:, 1]
        df["period"] = year + "-" + mon.str.upper().map(MONTHS)
        df = df.rename(columns={"nik_passport_no": "id_number", "bak": "bak_id", "bussiness_area": "business_area",
                                "origin": "origin_name", "destination": "destination_name"})
        df["customer_hash"] = [hashlib.sha256((HASH_SALT + str(x)).encode()).hexdigest() for x in df["id_number"]]
        df["ticketing_ts"] = pd.to_datetime(df["ticketing_time"])
        for c in ("departure_date", "purchase_date", "arrival_date"):
            df[c] = pd.to_datetime(df[c]).dt.date
        for c in ("purchase_time", "departure_time", "arrival_time"):
            df[c] = pd.to_datetime(df[c], format="mixed").dt.time
        for c in ("bak_id", "window_no", "shift_no"):
            df[c] = df[c].astype("Int64")
        df["operator_name"] = df["operator_name"].str.strip()
        df["source_file"] = f.name
        n += insert(con, "stg_ticket_sales", df)
    return n


def load_station_recaps(con, src: Path) -> int:
    rows = []
    for f in sorted((src / "stasiun").glob("rekap_*")):
        station, period = f.stem.split("_")[1], f.stem.split("_")[2]
        if station == "STA":
            # Layout A: header di baris 1, tanggal teks dd/mm/yyyy, baris TOTAL di akhir
            df = pd.read_excel(f, sheet_name=0)
            df = df[df["No"].notna()]
            for i, r in df.iterrows():
                rows.append({"station_code": station, "period": period, "recap_level": "ORDER",
                             "sales_date": pd.to_datetime(r["Tanggal"], format="%d/%m/%Y").date(),
                             "shift_no": int(r["Shift"]), "window_no": None, "order_no": str(r["No. Order"]).strip(),
                             "buyer_name": r["Nama Pemesan"], "ticket_count": int(r["Jml Tiket"]),
                             "payment_method": r["Metode Bayar"], "cash_amount": None, "noncash_amount": None,
                             "total_amount": parse_rupiah(r["Total (Rp)"]), "source_file": f.name, "source_row": i + 2})
        elif station == "STB":
            # Layout B: csv titik koma, agregat per tanggal dan shift, nominal teks Rp
            df = pd.read_csv(f, sep=";", dtype=str)
            for i, r in df.iterrows():
                rows.append({"station_code": station, "period": period, "recap_level": "SHIFT",
                             "sales_date": pd.to_datetime(r["Tgl"], format="%d-%m-%Y").date(),
                             "shift_no": {"PAGI": 1, "SIANG": 2}[r["Shift"].strip().upper()], "window_no": None,
                             "order_no": None, "buyer_name": None, "ticket_count": int(r["Jml Tiket"]),
                             "payment_method": None, "cash_amount": parse_rupiah(r["Tunai"]),
                             "noncash_amount": parse_rupiah(r["Non Tunai"]), "total_amount": parse_rupiah(r["Total"]),
                             "source_file": f.name, "source_row": i + 2})
        else:
            # Layout C: dua baris judul + satu baris kosong, header di baris 4, tanggal sel Excel
            df = pd.read_excel(f, sheet_name=0, header=3)
            for i, r in df.iterrows():
                rows.append({"station_code": station, "period": period, "recap_level": "ORDER",
                             "sales_date": pd.to_datetime(r["Sales Date"]).date(), "shift_no": None,
                             "window_no": None if pd.isna(r["Window"]) else int(r["Window"]),
                             "order_no": str(r["Order Number"]).strip(), "buyer_name": None,
                             "ticket_count": int(r["Pax"]), "payment_method": r["Payment"], "cash_amount": None,
                             "noncash_amount": None, "total_amount": parse_rupiah(r["Amount"]),
                             "source_file": f.name, "source_row": i + 5})
    df = pd.DataFrame(rows)
    for c in ("shift_no", "window_no"):
        df[c] = df[c].astype("Int64")
    return insert(con, "stg_station_recap", df)


def load_refunds(con, src: Path) -> int:
    frames = []
    for f in sorted((src / "stasiun").glob("refund_*.csv")):
        df = pd.read_csv(f, dtype={"id_number": str, "bank_account": str})
        df["source_file"] = f.name
        frames.append(df)
    df = pd.concat(frames, ignore_index=True)
    df["refund_date"] = pd.to_datetime(df["refund_date"]).dt.date
    df["account_holder_key"] = df["account_holder"].map(name_key)
    return insert(con, "stg_refund", df)


def load_finance(con, src: Path) -> dict:
    out = {}
    frames = []
    for f in sorted((src / "finance").glob("bak_group_order_*.csv")):
        df = pd.read_csv(f, dtype={"bukti_transfer": str, "manifest": str})
        df["source_file"] = f.name
        frames.append(df)
    bak = pd.concat(frames, ignore_index=True).rename(columns={
        "no_dokumen": "bak_no", "periode": "period", "tanggal_dokumen": "document_date",
        "nama_pihak_kedua": "counterparty_name", "jumlah_tiket": "ticket_count", "total_nominal": "total_amount",
        "stasiun": "station_code", "disetujui_oleh": "approved_by", "bukti_transfer": "transfer_proof_flag",
        "manifest": "manifest_flag", "keterangan": "remarks"})
    bak["document_date"] = pd.to_datetime(bak["document_date"]).dt.date
    out["stg_bak"] = insert(con, "stg_bak", bak)

    frames = []
    for f in sorted((src / "finance").glob("bukti_transfer_*.csv")):
        df = pd.read_csv(f)
        df["source_file"] = f.name
        frames.append(df)
    proof = pd.concat(frames, ignore_index=True)
    proof["uploaded_at"] = pd.to_datetime(proof["uploaded_at"])
    proof["transfer_date"] = pd.to_datetime(proof["transfer_date"]).dt.date
    out["stg_transfer_proof"] = insert(con, "stg_transfer_proof", proof)

    rows = []
    patterns = [
        ("TRANSFER_IN", re.compile(r"^TRF (FT\w+) (.+)$")),
        # Sebagian bank tidak meneruskan nomor referensi pengirim; pencocokan jatuh ke nominal dan tanggal.
        ("TRANSFER_IN_NOREF", re.compile(r"^TRF DR (.+)$")),
        ("CASH_DEPOSIT", re.compile(r"^SETORAN TUNAI (\w+) (\d{2}/\d{2}/\d{2})$")),
        ("SETTLEMENT", re.compile(r"^STLM (\S+) (\d{6})$")),
        ("TRANSFER_OUT", re.compile(r"^TRF KE (.+) (BANK \w+)$")),
        ("INTEREST", re.compile(r"^BUNGA")),
        ("FEE", re.compile(r"^BIAYA")),
    ]
    for f in sorted((src / "finance").glob("rekening_koran_*.csv")):
        df = pd.read_csv(f, dtype=str)
        for i, r in df.iterrows():
            desc = r["Keterangan"].strip()
            rec = {"bank_ref": r["No Ref Bank"], "account_no": "1020304050",
                   "posting_date": pd.to_datetime(r["Tanggal"], format="%d/%m/%Y").date(),
                   "value_date": pd.to_datetime(r["Tgl Valuta"], format="%d/%m/%Y").date(),
                   "description": desc, "branch": r["Cabang"], "debit": parse_rupiah(r["Debet"]),
                   "credit": parse_rupiah(r["Kredit"]), "balance": parse_rupiah(r["Saldo"]),
                   "txn_category": "UNKNOWN", "ref_no": None, "key_station": None, "key_date": None,
                   "key_gateway": None, "counterparty": None, "source_file": f.name, "source_row": i + 2}
            for cat, pat in patterns:
                m = pat.match(desc)
                if not m:
                    continue
                rec["txn_category"] = cat
                if cat == "TRANSFER_IN":
                    rec["ref_no"], rec["counterparty"] = m.group(1), m.group(2)
                elif cat == "TRANSFER_IN_NOREF":
                    rec["txn_category"], rec["counterparty"] = "TRANSFER_IN", m.group(1)
                elif cat == "CASH_DEPOSIT":
                    rec["key_station"] = m.group(1)
                    rec["key_date"] = pd.to_datetime(m.group(2), format="%d/%m/%y").date()
                elif cat == "SETTLEMENT":
                    rec["key_gateway"] = m.group(1)
                    rec["key_date"] = pd.to_datetime(m.group(2), format="%d%m%y").date()
                elif cat == "TRANSFER_OUT":
                    rec["counterparty"] = name_key(m.group(1))
                break
            rows.append(rec)
    out["stg_bank_statement"] = insert(con, "stg_bank_statement", pd.DataFrame(rows))
    return out


def load_hcm(con, src: Path) -> dict:
    emp = pd.read_csv(src / "hcm" / "employees.csv")
    emp["join_date"] = pd.to_datetime(emp["join_date"]).dt.date
    ros = pd.read_csv(src / "hcm" / "shift_roster.csv")
    ros["roster_date"] = pd.to_datetime(ros["roster_date"]).dt.date
    for c in ("shift_start", "shift_end"):
        ros[c] = pd.to_datetime(ros[c], format="%H:%M").dt.time
    ros["window_no"] = ros["window_no"].astype("Int64")
    return {"stg_employee": insert(con, "stg_employee", emp),
            "stg_shift_roster": insert(con, "stg_shift_roster", ros)}


def load_portal(con, src: Path) -> dict:
    log = pd.read_csv(src / "portal" / "upload_log.csv")
    for c in ("uploaded_at", "deadline_at", "approved_at"):
        log[c] = pd.to_datetime(log[c])
    log["row_count"] = log["row_count"].astype("Int64")
    # Inventaris objek: checksum dihitung ulang dari isi file yang tersimpan
    inv = [{"file_name": f.name, "sha256": hashlib.sha256(f.read_bytes()).hexdigest(), "size_bytes": f.stat().st_size}
           for sub in ("it", "stasiun", "finance") for f in sorted((src / sub).iterdir())]
    return {"stg_upload_log": insert(con, "stg_upload_log", log),
            "stg_object_inventory": insert(con, "stg_object_inventory", pd.DataFrame(inv))}


def run_sql(con, name: str):
    con.execute((SQL_DIR / name).read_text(encoding="utf-8"))


def load_all(con, src: Path) -> dict:
    run_sql(con, "01_staging_ddl.sql")
    run_sql(con, "02_reference_data.sql")
    counts = {"stg_ticket_sales": load_ticket_sales(con, src),
              "stg_station_recap": load_station_recaps(con, src),
              "stg_refund": load_refunds(con, src)}
    counts.update(load_finance(con, src))
    counts.update(load_hcm(con, src))
    counts.update(load_portal(con, src))
    return counts
