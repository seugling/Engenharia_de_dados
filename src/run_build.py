"""Build the NorthMart star schema into northmart.duckdb and print referential checks."""
from __future__ import annotations

import os
from pathlib import Path

import duckdb

from run_sql import run_sql_file

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)

DB = ROOT / "northmart.duckdb"
con = duckdb.connect(str(DB))
run_sql_file(con, ROOT / "sql" / "build_model.sql")

print(f"Database: {DB}")
print("\nMart tables")
print(con.sql("""
    SELECT schema_name, table_name, estimated_size
    FROM duckdb_tables()
    WHERE schema_name IN ('raw', 'mart')
    ORDER BY schema_name, table_name
""").df().to_string(index=False))

print("\nReferential checks (delta must be 0 except the documented JSON duplicate count)")
print(con.sql("SELECT * FROM mart.ref_checks ORDER BY check_name").df().to_string(index=False))

print("\nSeller dimension: JSON attributes populated")
print(con.sql("""
    SELECT
        count(*) AS sellers,
        count(*) FILTER (WHERE seller_tier = 'unknown') AS tier_unknown,
        count(*) FILTER (WHERE joined_on IS NULL) AS joined_null,
        count(*) FILTER (WHERE handling_days IS NULL) AS handling_null,
        count(DISTINCT seller_tier) AS distinct_tiers
    FROM mart.dim_seller
    WHERE seller_sk <> -1
""").df().to_string(index=False))

print("\nTier values after normalisation")
print(con.sql("""
    SELECT seller_tier, count(*) AS n
    FROM mart.dim_seller
    WHERE seller_sk <> -1
    GROUP BY seller_tier
    ORDER BY n DESC
""").df().to_string(index=False))

print("\nFact grain sample")
print(con.sql("SELECT * FROM mart.fact_order_item LIMIT 5").df().to_string(index=False))

con.close()
print("\nDone.")
