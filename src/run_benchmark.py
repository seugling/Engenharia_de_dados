"""Export the fact table to CSV / Parquet / partitioned Parquet and time three queries.

Method
------
- Storage layouts share the same columns (including year_month = date_sk // 100).
- Partition column: year_month (YYYYMM), chosen because two of the three queries
  group or filter by month, so Hive-style pruning can skip files.
- Each timed run uses a fresh in-memory DuckDB connection (no persistent buffer of
  a previous scan). One warmup run is discarded; we then measure N_RUNS times and
  report the median. The OS page cache is *not* dropped, so absolute times vary by
  machine; the ranking across layouts is what we compare.
- The three queries are executed more than once, as required by the assignment.
"""
from __future__ import annotations

import csv
import os
import shutil
import statistics
import time
from pathlib import Path

import duckdb

from run_sql import run_sql_file

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)

N_WARMUP = 1
N_RUNS = 5
MONTH = 201711

CURATED = ROOT / "data" / "curated"
CSV_PATH = CURATED / "fact_order_item.csv"
PARQUET_PATH = CURATED / "fact_order_item.parquet"
PART_DIR = CURATED / "fact_order_item_partitioned"
DIM_PRODUCT = CURATED / "dim_product.parquet"
EVIDENCE_MD = ROOT / "evidence" / "benchmark_results.md"
EVIDENCE_CSV = ROOT / "evidence" / "benchmark_runs.csv"

FACT_SCANS = {
    "csv": "read_csv_auto('data/curated/fact_order_item.csv')",
    "parquet": "read_parquet('data/curated/fact_order_item.parquet')",
    "parquet_partitioned": (
        "read_parquet('data/curated/fact_order_item_partitioned/**/*.parquet', "
        "hive_partitioning := true)"
    ),
}

QUERIES = {
    "q1_revenue_by_month": """
        SELECT year_month,
               round(sum(gross_value), 2) AS revenue
        FROM {fact}
        GROUP BY year_month
        ORDER BY year_month
    """,
    "q2_one_month": f"""
        SELECT round(sum(gross_value), 2) AS revenue,
               count(*) AS item_count
        FROM {{fact}}
        WHERE year_month = {MONTH}
    """,
    "q3_top5_categories": """
        SELECT p.category_en,
               round(sum(f.gross_value), 2) AS revenue
        FROM {fact} f
        JOIN read_parquet('data/curated/dim_product.parquet') p
          ON f.product_sk = p.product_sk
        GROUP BY p.category_en
        ORDER BY revenue DESC
        LIMIT 5
    """,
}


def bytes_on_disk(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.stat().st_size for p in path.rglob("*") if p.is_file())


def mib(n: int) -> float:
    return n / (1024 * 1024)


def export_layouts(con: duckdb.DuckDBPyConnection) -> None:
    CURATED.mkdir(parents=True, exist_ok=True)
    if PART_DIR.exists():
        shutil.rmtree(PART_DIR)
    run_sql_file(con, ROOT / "sql" / "export_curated.sql")


def run_once(sql: str):
    con = duckdb.connect()
    try:
        t0 = time.perf_counter()
        rows = con.execute(sql).fetchall()
        elapsed = time.perf_counter() - t0
    finally:
        con.close()
    return elapsed, rows


def benchmark_one(sql: str) -> tuple[list[float], list]:
    _, warmup_rows = run_once(sql)
    times = []
    last_rows = warmup_rows
    for _ in range(N_RUNS):
        elapsed, last_rows = run_once(sql)
        times.append(elapsed)
    return times, last_rows


def main() -> None:
    db = ROOT / "northmart.duckdb"
    if not db.exists():
        raise SystemExit("northmart.duckdb not found. Run python src/run_build.py first.")

    warehouse = duckdb.connect(str(db))
    print("Exporting CSV, Parquet and partitioned Parquet …")
    export_layouts(warehouse)
    warehouse.close()

    sizes = {
        "csv": bytes_on_disk(CSV_PATH),
        "parquet": bytes_on_disk(PARQUET_PATH),
        "parquet_partitioned": bytes_on_disk(PART_DIR),
        "dim_product": bytes_on_disk(DIM_PRODUCT),
    }
    n_part_files = len(list(PART_DIR.rglob("*.parquet")))
    print(
        f"Sizes: CSV {mib(sizes['csv']):.3f} MiB | "
        f"Parquet {mib(sizes['parquet']):.3f} MiB | "
        f"Partitioned {mib(sizes['parquet_partitioned']):.3f} MiB "
        f"({n_part_files} files)"
    )

    results: dict[str, dict[str, dict]] = {}
    reference_rows: dict[str, list] = {}

    for layout, scan in FACT_SCANS.items():
        results[layout] = {}
        print(f"\n=== {layout} ===")
        for qname, template in QUERIES.items():
            sql = template.format(fact=scan)
            times, rows = benchmark_one(sql)
            median_s = statistics.median(times)
            results[layout][qname] = {
                "times": times,
                "median_s": median_s,
                "min_s": min(times),
                "mean_s": statistics.mean(times),
            }
            if qname not in reference_rows:
                reference_rows[qname] = rows
            elif rows != reference_rows[qname]:
                raise SystemExit(
                    f"Result mismatch on {qname} / {layout}: {rows!r} vs {reference_rows[qname]!r}"
                )
            print(
                f"  {qname}: median {median_s*1000:.2f} ms "
                f"(min {min(times)*1000:.2f}, mean {statistics.mean(times)*1000:.2f}) "
                f"rows={len(rows)}"
            )

    write_evidence(sizes, n_part_files, results, reference_rows)
    print(f"\nWrote {EVIDENCE_MD.relative_to(ROOT)} and {EVIDENCE_CSV.relative_to(ROOT)}")


def write_evidence(
    sizes: dict[str, int],
    n_part_files: int,
    results: dict,
    reference_rows: dict,
) -> None:
    EVIDENCE_MD.parent.mkdir(parents=True, exist_ok=True)

    def ms(layout: str, q: str) -> str:
        return f"{results[layout][q]['median_s'] * 1000:.2f}"

    q1_rows = "\n".join(
        f"| {ym} | {rev:,.2f} |" for ym, rev in reference_rows["q1_revenue_by_month"][:3]
    )
    last = reference_rows["q1_revenue_by_month"][-1]
    top5 = "\n".join(
        f"| {cat} | {rev:,.2f} |" for cat, rev in reference_rows["q3_top5_categories"]
    )
    q2_rev, q2_n = reference_rows["q2_one_month"][0]

    lines = [
        "# PA1 Task 4 — storage benchmark",
        "",
        "## Method",
        "",
        "- Same fact projection in three layouts: CSV, single Parquet file (Snappy),",
        f"  Hive-partitioned Parquet by `year_month` ({n_part_files} partition files).",
        "- `dim_product.parquet` is constant and used only by Q3.",
        f"- Each query: {N_WARMUP} warmup + {N_RUNS} timed runs on a **new in-memory DuckDB**",
        "  connection. Times below are the **median** of the timed runs.",
        "- OS page cache is not flushed; re-run `python src/run_benchmark.py` on the demo machine.",
        "- Filter month for Q2: **2017-11** (Black Friday peak in this dataset).",
        "",
        "## File size",
        "",
        "| Layout | Path | Size (bytes) | Size (MiB) |",
        "| --- | --- | ---: | ---: |",
        f"| CSV | `data/curated/fact_order_item.csv` | {sizes['csv']:,} | {mib(sizes['csv']):.3f} |",
        f"| Parquet (unpartitioned) | `data/curated/fact_order_item.parquet` | {sizes['parquet']:,} | {mib(sizes['parquet']):.3f} |",
        f"| Parquet (partitioned by year_month) | `data/curated/fact_order_item_partitioned/` | {sizes['parquet_partitioned']:,} | {mib(sizes['parquet_partitioned']):.3f} |",
        f"| dim_product (not in the comparison) | `data/curated/dim_product.parquet` | {sizes['dim_product']:,} | {mib(sizes['dim_product']):.3f} |",
        "",
        f"CSV / unpartitioned Parquet ratio: **{sizes['csv'] / sizes['parquet']:.2f}×** "
        "(CSV is larger).",
        "",
        "## Query runtime (median milliseconds)",
        "",
        "| Query | CSV | Parquet | Partitioned Parquet |",
        "| --- | ---: | ---: | ---: |",
        f"| Q1 revenue per month (full period) | {ms('csv','q1_revenue_by_month')} | {ms('parquet','q1_revenue_by_month')} | {ms('parquet_partitioned','q1_revenue_by_month')} |",
        f"| Q2 revenue + item count for 2017-11 | {ms('csv','q2_one_month')} | {ms('parquet','q2_one_month')} | {ms('parquet_partitioned','q2_one_month')} |",
        f"| Q3 top 5 categories by revenue | {ms('csv','q3_top5_categories')} | {ms('parquet','q3_top5_categories')} | {ms('parquet_partitioned','q3_top5_categories')} |",
        "",
        "## Query results (identical on all three layouts)",
        "",
        f"Q2 2017-11: revenue **{q2_rev:,.2f}**, item count **{q2_n:,}**.",
        "",
        "Q3 top 5 categories:",
        "",
        "| category_en | revenue |",
        "| --- | ---: |",
        top5,
        "",
        "Q1 first three months (24 distinct year_month values, one partition file each):",
        "",
        "| year_month | revenue |",
        "| --- | ---: |",
        q1_rows,
        f"| … | … |",
        f"| {last[0]} | {last[1]:,.2f} |",
        "",
    ]
    EVIDENCE_MD.write_text("\n".join(lines), encoding="utf-8")

    with EVIDENCE_CSV.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["layout", "query", "run_index", "seconds"])
        for layout, qs in results.items():
            for qname, payload in qs.items():
                for i, sec in enumerate(payload["times"], 1):
                    w.writerow([layout, qname, i, f"{sec:.6f}"])


if __name__ == "__main__":
    main()
