# PA1 Task 4 — storage benchmark

## Method

- Same fact projection in three layouts: CSV, single Parquet file (Snappy),
  Hive-partitioned Parquet by `year_month` (24 partition files).
- `dim_product.parquet` is constant and used only by Q3.
- Each query: 1 warmup + 5 timed runs on a **new in-memory DuckDB**
  connection. Times below are the **median** of the timed runs.
- OS page cache is not flushed; re-run `python src/run_benchmark.py` on the demo machine.
- Filter month for Q2: **2017-11** (Black Friday peak in this dataset).

## File size

| Layout | Path | Size (bytes) | Size (MiB) |
| --- | --- | ---: | ---: |
| CSV | `data/curated/fact_order_item.csv` | 14,562,762 | 13.888 |
| Parquet (unpartitioned) | `data/curated/fact_order_item.parquet` | 7,162,651 | 6.831 |
| Parquet (partitioned by year_month) | `data/curated/fact_order_item_partitioned/` | 7,300,034 | 6.962 |
| dim_product (not in the comparison) | `data/curated/dim_product.parquet` | 1,481,038 | 1.412 |

CSV / unpartitioned Parquet ratio: **2.03×** (CSV is larger).

## Query runtime (median milliseconds)

| Query | CSV | Parquet | Partitioned Parquet |
| --- | ---: | ---: | ---: |
| Q1 revenue per month (full period) | 160.70 | 16.24 | 221.77 |
| Q2 revenue + item count for 2017-11 | 154.68 | 14.34 | 248.16 |
| Q3 top 5 categories by revenue | 216.03 | 30.14 | 251.43 |

## Query results (identical on all three layouts)

Q2 2017-11: revenue **1,179,143.77**, item count **8,665**.

Q3 top 5 categories:

| category_en | revenue |
| --- | ---: |
| health_beauty | 1,441,248.07 |
| watches_gifts | 1,305,541.61 |
| bed_bath_table | 1,241,681.72 |
| sports_leisure | 1,156,656.48 |
| computers_accessories | 1,059,272.40 |

Q1 first three months (24 distinct year_month values, one partition file each):

| year_month | revenue |
| --- | ---: |
| 201609 | 354.75 |
| 201610 | 56,808.84 |
| 201612 | 19.62 |
| … | … |
| 201809 | 166.46 |
