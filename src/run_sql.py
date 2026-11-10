"""Execute a multi-statement .sql file in DuckDB, statement by statement."""
from __future__ import annotations

from pathlib import Path


def split_statements(sql: str) -> list[str]:
    stmts: list[str] = []
    buf: list[str] = []
    for line in sql.splitlines():
        buf.append(line)
        stripped = line.strip()
        if stripped.endswith(";") and not stripped.startswith("--"):
            stmt = "\n".join(buf).strip()
            if stmt and any(
                not ln.strip().startswith("--") and ln.strip()
                for ln in stmt.splitlines()
            ):
                stmts.append(stmt)
            buf = []
    tail = "\n".join(buf).strip()
    if tail:
        stmts.append(tail)
    return stmts


def run_sql_file(con, path: Path) -> None:
    sql = path.read_text(encoding="utf-8")
    for stmt in split_statements(sql):
        con.execute(stmt)
