"""Pipeline lokal: staging -> aturan audit -> kepatuhan unggah -> model dimensional,
lalu membandingkan hasil deteksi dengan kunci anomali (anomalies_truth.csv) dan memastikan
kasus pengecoh yang sah (decoys_truth.csv) tidak ikut ditandai.

Pemakaian (dari root repo):
    python etl/run_pipeline.py [--src data-dummy/output] [--db data-dummy/output/audit.duckdb]
"""
from __future__ import annotations

import argparse
from pathlib import Path

import duckdb
import pandas as pd

from load_staging import ROOT, load_all, run_sql


def evaluate(con, truth_path: Path) -> pd.DataFrame:
    truth = pd.read_csv(truth_path)[["rule_code", "entity_id"]]
    found = con.execute("SELECT rule_code, entity_id FROM audit_exception").df()
    t = set(map(tuple, truth.values))
    f = set(map(tuple, found.values))
    rules = sorted({r for r, _ in t | f})
    rows = []
    for r in rules:
        tr = {x for x in t if x[0] == r}
        fr = {x for x in f if x[0] == r}
        rows.append({"rule_code": r, "truth": len(tr), "detected": len(fr), "true_positive": len(tr & fr),
                     "false_positive": len(fr - tr), "false_negative": len(tr - fr)})
    rep = pd.DataFrame(rows)
    total = rep[["truth", "detected", "true_positive", "false_positive", "false_negative"]].sum()
    rep.loc[len(rep)] = {"rule_code": "TOTAL", **total.to_dict()}
    return rep


def evaluate_decoys(con, decoy_path: Path) -> pd.DataFrame:
    """Setiap kasus pengecoh yang muncul di audit_exception dihitung sebagai false positive."""
    decoys = pd.read_csv(decoy_path)
    found = con.execute("SELECT DISTINCT entity_type, entity_id, rule_code FROM audit_exception").df()
    hit = decoys.merge(found, on=["entity_type", "entity_id"], how="left")
    rows = []
    for rule, g in hit.groupby("target_rule"):
        flagged = g.dropna(subset=["rule_code"])
        rows.append({"target_rule": rule, "decoys": g["decoy_id"].nunique(),
                     "flagged": flagged["decoy_id"].nunique(),
                     "flagged_by": ", ".join(sorted(set(flagged["rule_code"]))) or "-"})
    rep = pd.DataFrame(rows)
    rep.loc[len(rep)] = {"target_rule": "TOTAL", "decoys": rep["decoys"].sum(), "flagged": rep["flagged"].sum(),
                         "flagged_by": "-"}
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(ROOT / "data-dummy" / "output"))
    ap.add_argument("--db", default=None, help="file DuckDB; default <src>/audit.duckdb")
    args = ap.parse_args()
    src = Path(args.src)
    db = Path(args.db) if args.db else src / "audit.duckdb"
    db.unlink(missing_ok=True)
    con = duckdb.connect(str(db))

    counts = load_all(con, src)
    print("Baris staging:")
    for k, v in counts.items():
        print(f"  {k:24s} {v:>7d}")

    for name in ("03_audit_rules.sql", "04_upload_compliance.sql", "05_dw_ddl.sql", "06_dw_load.sql"):
        run_sql(con, name)

    print("\nBaris model dimensional:")
    for tbl in ("fact_ticket_sale", "fact_bank_mutation", "fact_refund", "fact_audit_exception", "fact_upload_submission"):
        print(f"  {tbl:24s} {con.execute(f'SELECT COUNT(*) FROM {tbl}').fetchone()[0]:>7d}")

    print("\nIndikator kepatuhan unggah per departemen:")
    print(con.execute("SELECT * FROM upload_compliance_kpi ORDER BY department, period").df().to_string(index=False))

    rep = evaluate(con, src / "anomalies_truth.csv")
    rep.to_csv(src / "evaluation.csv", index=False)
    print("\nDeteksi vs kunci anomali:")
    print(rep.to_string(index=False))

    drep = evaluate_decoys(con, src / "decoys_truth.csv")
    drep.to_csv(src / "evaluation_decoys.csv", index=False)
    print("\nKasus pengecoh (seharusnya tidak ada yang ditandai):")
    print(drep.to_string(index=False))
    con.close()


if __name__ == "__main__":
    main()
