# PA1 Task 3 — referential checks

Produced by `python src/run_build.py` against `northmart.duckdb`.

Expected after a successful build:

| check_name | actual | expected | delta |
| --- | ---: | ---: | ---: |
| fact_rowcount_vs_items | 112650 | 112650 | 0 |
| fact_orphan_date | 0 | 0 | 0 |
| fact_orphan_customer | 0 | 0 | 0 |
| fact_orphan_product | 0 | 0 | 0 |
| fact_orphan_seller | 0 | 0 | 0 |
| fact_orphan_status | 0 | 0 | 0 |
| seller_unknown_member_used | 0 | 0 | 0 |
| dim_seller_duplicate_nk | 0 | 0 | 0 |
| json_extra_rows_before_dedup | 25 | 25 | 0 |

`json_extra_rows_before_dedup` documents the 25 extra JSON rows **before** `raw.seller_profiles_latest` keeps one record per seller. It is not an integrity failure.
