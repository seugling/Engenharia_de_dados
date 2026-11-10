"""Run sql/profiling.sql against DuckDB and print each result set."""
import os
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SQL = (ROOT / "sql" / "profiling.sql").read_text(encoding="utf-8")
con = duckdb.connect()

# Split on statement boundaries while keeping comments attached to the next query.
parts = []
buf = []
for line in SQL.splitlines():
    buf.append(line)
    if line.strip().endswith(";") and not line.strip().startswith("--"):
        stmt = "\n".join(buf).strip()
        if stmt:
            parts.append(stmt)
        buf = []

for i, stmt in enumerate(parts, 1):
    title = next((ln[2:].strip() for ln in stmt.splitlines() if ln.startswith("--")), f"query_{i}")
    print("\n" + "=" * 80)
    print(f"[{i}] {title}")
    print("=" * 80)
    try:
        rel = con.sql(stmt)
        df = rel.df()
        print(df.to_string(index=False))
    except Exception as exc:
        print(f"ERROR: {exc}")
        print(stmt[:500])
