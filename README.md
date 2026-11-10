# NorthMart — Data Engineering practical work

One repository for PA1–PA3. **PA1 (tasks 1–5) is complete.**

## Setup

```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# WSL / Linux: source .venv/bin/activate
pip install -r requirements.txt
```

Put the nine Olist CSV files and `json_northmart_seller_profiles.json` in `data/source/`. Do not edit or commit them.

## How to reproduce PA1

From the repository root:

```bash
python src/run_profiling.py
python src/run_build.py
python src/run_benchmark.py
```

| Script | What it does |
| --- | --- |
| `src/run_profiling.py` | Task 1: row/column counts, keys, nulls, FKs, JSON quality |
| `src/run_build.py` | Task 3: `raw` + `mart` in `northmart.duckdb`, prints referential checks |
| `src/run_benchmark.py` | Task 4: export CSV + two Parquet layouts, time the three queries **twice internally** (1 warmup + 5 runs) |

Star schema (task 2): [`architecture/star_schema.md`](architecture/star_schema.md).  
Benchmark table (task 4): [`evidence/benchmark_results.md`](evidence/benchmark_results.md).

Outputs land in `data/curated/`:

- `fact_order_item.csv`
- `fact_order_item.parquet`
- `fact_order_item_partitioned/` (Hive folders `year_month=YYYYMM`)
- `dim_product.parquet` (only for Q3; not part of the size comparison)

---

## PA1 — Task 1 findings

Five concrete findings from DuckDB profiling. **(1) and (2) come from the seller JSON.**

1. **The JSON export is not one row per seller.** `json_northmart_seller_profiles.json` has **3 095** documents but only **3 070** distinct `seller_id` values (**25 extra rows**). Seven of those duplicated sellers even disagree on `profile.tier` across versions. The mart therefore keeps **one record per seller**, taking the latest `updated_at`.
2. **The nested profile was exported carelessly.** `tier` arrives in mixed case (`bronze` / `Bronze` / `BRONZE`, same for silver and gold); **30** documents have a null `shipping` object (so `handling_days` and `carriers` are missing); **141** rows have `joined_on` after `updated_at`; and coverage vs the sellers CSV is incomplete (**40** CSV sellers with no JSON profile, **15** JSON sellers absent from the CSV). Emails are syntactically valid, so the damage is in identity, nesting and vocabulary — not in contact format.
3. **`order_id` + `order_item_id` is a clean grain; several other “keys” are not.** Order items have **112 650** unique pairs and **zero** orphans toward orders, products and sellers. By contrast, `review_id` is **not** unique (**814** duplicate rows), `customer_unique_id` repeats (**3 345** extra rows — returning buyers), and geolocation zip prefixes explode (**1 000 163** rows for **19 015** zips). Geolocation is therefore not a dimension in PA1.
4. **Payments cannot be copied onto the item fact.** There are **103 886** payment rows for **99 440** orders, and **2 961** orders have more than one payment. Joining `payment_value` to items would duplicate merchandise revenue.
5. **The fact will be smaller than the orders file, on purpose.** **775** orders have no item row (603 `unavailable`, 164 `canceled`, plus a handful of `created` / `invoiced` / `shipped`). About **2.98%** of orders lack a customer delivery timestamp, almost entirely on non-delivered statuses (only **8** `delivered` orders are missing that date). Product category is null for **610** products (**1.85%**), and two Portuguese categories (`pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos`) have no English translation.

Row / column counts used above:

| File | Rows | Columns |
| --- | ---: | ---: |
| customers | 99 441 | 5 |
| geolocation | 1 000 163 | 5 |
| orders | 99 441 | 8 |
| order_items | 112 650 | 7 |
| order_payments | 103 886 | 5 |
| order_reviews | 99 224 | 7 |
| products | 32 951 | 9 |
| sellers | 3 095 | 4 |
| category_translation | 71 | 2 |
| seller JSON | 3 095 | 5 nested fields |

---

## PA1 — Task 2 (summary)

- **Grain:** one fact row per order item.
- **Measures:** `item_price`, `freight_value`, `gross_value` (price + freight).
- **Dimensions:** `dim_date` (purchase date), `dim_customer`, `dim_product`, `dim_seller` (CSV + JSON), `dim_order_status`.
- **Non-obvious decision:** do **not** put payments on this fact (see finding 4 and `architecture/star_schema.md`).

---

## PA1 — Task 3 (what the SQL does)

`sql/build_model.sql`:

1. Loads every source file into `raw.*`.
2. Flattens `profile`, `contact` and `shipping` from the JSON; deduplicates with `QUALIFY row_number() ... updated_at DESC`; lower-cases `tier`.
3. Builds surrogate keys (`row_number`, and `YYYYMMDD` for dates). `dim_seller` has an unknown member (`seller_sk = -1`) and a `FULL OUTER JOIN` so JSON-only sellers are kept.
4. Builds `mart.fact_order_item` at item grain with inner joins on date, customer, product and status.
5. Writes `mart.ref_checks`: fact row count **112 650**, **zero** FK orphans.

Reproduce the checks with `python src/run_build.py`.

---

## PA1 — Task 4 (Parquet export and benchmark)

Partition column: **`year_month`** (`YYYYMM` from `date_sk`), because Q1 groups by month and Q2 filters one month.

The script was run **twice**. File sizes did not change. CSV milliseconds jitter; the ranking is stable.

| Layout | Size (MiB) |
| --- | ---: |
| CSV | 13.888 |
| Parquet (one file) | 6.869 |
| Parquet partitioned by `year_month` (24 files) | 6.998 |

Median runtime, second execution (ms):

| Query | CSV | Parquet | Partitioned |
| --- | ---: | ---: | ---: |
| Q1 revenue per month | 251.62 | 9.64 | 16.35 |
| Q2 2017-11 revenue + item count | 277.06 | 10.74 | 12.11 |
| Q3 top 5 categories | 332.91 | 29.20 | 41.69 |

Q2 result: revenue **1,179,143.77**, **8,665** items. Q3: health_beauty, watches_gifts, bed_bath_table, sports_leisure, computers_accessories. Full method and the first-run table: `evidence/benchmark_results.md`.

---

## PA1 — Task 5 (max. 150 words)

NorthMart is better served by a lakehouse than by a warehouse or a data lake alone. Analysts already live on a lake of CSV files and suffer slow, inconsistent joins. A warehouse would give them the star schema we built, but it would hide the storage lesson: the same 112 650 fact rows occupy 13.888 MiB as CSV and 6.869 MiB as one Snappy Parquet file (2.02× smaller), and median Q1 time fell from hundreds of milliseconds on CSV to about 8–10 ms on Parquet. A lake of Hive partitions is not automatically faster: 24 month folders made Q1 slower (~16 ms) than the single Parquet file, because small-file overhead dominates at this volume. A lakehouse keeps those Parquet files, lets DuckDB run warehouse-style SQL on them, and only partitions when the files are large enough to prune.
