"""MariaDB `Store`. Imported only by the CLI and the master wrappers.

Plan: docs/sync/transaction-sync-plan.md, "`Store` protocol" / `store_db.py`.
Upserts go through `seed_common.upsert_sql`. Columns are read once per table
(`SHOW COLUMNS`); a mapper key that is not a column raises. `replace_lines`
and `replace_range` each run in one transaction.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from seed_common import upsert_sql

from .store import TABLE_KEY_COLUMNS, RowNotFound, key_for


class UnknownColumn(ValueError):
    """Raised when a mapper row carries a key that is not a column of the table."""


class DbStore:
    """MariaDB-backed `Store`. Pass `columns` in tests to skip `SHOW COLUMNS`."""

    def __init__(self, conn: Any, columns: dict[str, set[str]] | None = None) -> None:
        self._conn = conn
        self._columns: dict[str, set[str]] = {k: set(v) for k, v in (columns or {}).items()}

    def _table_columns(self, table: str) -> set[str]:
        if table in self._columns:
            return self._columns[table]
        with self._conn.cursor() as cur:
            cur.execute(f"SHOW COLUMNS FROM `{table}`")
            cols = {row["Field"] for row in cur.fetchall()}
        self._columns[table] = cols
        return cols

    def _validate_rows(self, table: str, rows: list[dict[str, Any]]) -> list[str]:
        allowed = self._table_columns(table)
        keys: list[str] = []
        seen: set[str] = set()
        for row in rows:
            for col in row:
                if col not in allowed:
                    raise UnknownColumn(f"store_db: {table}.{col} is not a column")
                if col not in seen:
                    seen.add(col)
                    keys.append(col)
        return keys

    def get(self, table: str, key: Any) -> dict[str, Any] | None:
        key_cols = TABLE_KEY_COLUMNS[table]
        if len(key_cols) == 1:
            where = f"`{key_cols[0]}` = %s"
            args: tuple[Any, ...] = (key,)
        else:
            where = " AND ".join(f"`{c}` = %s" for c in key_cols)
            args = tuple(key)
        with self._conn.cursor() as cur:
            cur.execute(f"SELECT * FROM `{table}` WHERE {where}", args)
            row = cur.fetchone()
        return dict(row) if row else None

    def has(self, table: str, key: Any) -> bool:
        return self.get(table, key) is not None

    def upsert(self, table: str, rows: list[dict[str, Any]], update_cols: list[str] | None = None) -> None:
        """Upsert full rows into `table`.

        `update_cols`, if provided, restricts which columns to refresh on key conflict.
        Every row must still be complete (carrying NOT NULL columns without defaults);
        use `update` for partial updates to existing rows.
        """
        if not rows:
            return
        cols = self._validate_rows(table, rows)
        key_cols = TABLE_KEY_COLUMNS[table]
        if update_cols is not None:
            # Restrict ON DUPLICATE KEY UPDATE to the named columns (plus keep keys out).
            sql_cols = list(dict.fromkeys([*key_cols, *[c for c in update_cols if c in cols]]))
            # Rows may carry extra keys that must still validate; write only sql_cols.
            write_cols = sql_cols
        else:
            write_cols = cols
        sql = upsert_sql(table, write_cols, key_cols)
        payload = [{c: row.get(c) for c in write_cols} for row in rows]
        with self._conn.cursor() as cur:
            cur.executemany(sql, payload)
        self._conn.commit()

    def update(self, table: str, key: Any, values: dict[str, Any]) -> None:
        """Update named columns of an existing row. Raises RowNotFound if no row matches."""
        if not values:
            return
        allowed = self._table_columns(table)
        for col in values:
            if col not in allowed:
                raise UnknownColumn(f"store_db: {table}.{col} is not a column")
        key_cols = TABLE_KEY_COLUMNS[table]
        set_cols = [c for c in values if c not in key_cols]
        if not set_cols:
            return
        set_clause = ", ".join(f"`{c}` = %s" for c in set_cols)
        if len(key_cols) == 1:
            where = f"`{key_cols[0]}` = %s"
            key_args: tuple[Any, ...] = (key,)
        else:
            where = " AND ".join(f"`{c}` = %s" for c in key_cols)
            key_args = tuple(key)
        sql = f"UPDATE `{table}` SET {set_clause} WHERE {where}"
        args = tuple(values[c] for c in set_cols) + key_args
        with self._conn.cursor() as cur:
            cur.execute(sql, args)
            if cur.rowcount == 0:
                raise RowNotFound(f"store_db: no row in `{table}` for key {key!r}")
        self._conn.commit()

    def replace_lines(self, table: str, parent_col: str, parent_id: Any, rows: list[dict[str, Any]]) -> None:
        key_cols = TABLE_KEY_COLUMNS[table]
        try:
            if rows:
                cols = self._validate_rows(table, rows)
                sql = upsert_sql(table, cols, key_cols)
                with self._conn.cursor() as cur:
                    cur.executemany(sql, [{c: row.get(c) for c in cols} for row in rows])
                    keep = [key_for(table, row) for row in rows]
                    self._delete_missing_lines(cur, table, parent_col, parent_id, key_cols, keep)
            else:
                with self._conn.cursor() as cur:
                    cur.execute(f"DELETE FROM `{table}` WHERE `{parent_col}` = %s", (parent_id,))
            self._conn.commit()
        except Exception:
            self._conn.rollback()
            raise

    def _delete_missing_lines(
        self,
        cur: Any,
        table: str,
        parent_col: str,
        parent_id: Any,
        key_cols: tuple[str, ...],
        keep: list[Any],
    ) -> None:
        if len(key_cols) == 1:
            col = key_cols[0]
            if keep:
                placeholders = ", ".join(["%s"] * len(keep))
                cur.execute(
                    f"DELETE FROM `{table}` WHERE `{parent_col}` = %s AND `{col}` NOT IN ({placeholders})",
                    (parent_id, *keep),
                )
            else:
                cur.execute(f"DELETE FROM `{table}` WHERE `{parent_col}` = %s", (parent_id,))
            return
        # Composite keys (item_units): fetch then delete stale in Python.
        cur.execute(f"SELECT * FROM `{table}` WHERE `{parent_col}` = %s", (parent_id,))
        keep_set = set(keep)
        for row in cur.fetchall():
            k = key_for(table, row)
            if k not in keep_set:
                where = " AND ".join(f"`{c}` = %s" for c in key_cols)
                cur.execute(f"DELETE FROM `{table}` WHERE {where}", k)

    def replace_range(self, account_id: str, date_from: date, date_to: date, rows: list[dict[str, Any]]) -> None:
        table = "gl_journals"
        try:
            with self._conn.cursor() as cur:
                if rows:
                    cols = self._validate_rows(table, rows)
                    sql = upsert_sql(table, cols, ("account_id", "categorized_transaction_id"))
                    cur.executemany(sql, [{c: row.get(c) for c in cols} for row in rows])
                    keep = [row["categorized_transaction_id"] for row in rows]
                    placeholders = ", ".join(["%s"] * len(keep)) if keep else None
                    if keep:
                        cur.execute(
                            f"DELETE FROM `{table}` WHERE `account_id` = %s "
                            f"AND `transaction_date` >= %s AND `transaction_date` <= %s "
                            f"AND `categorized_transaction_id` NOT IN ({placeholders})",
                            (account_id, date_from, date_to, *keep),
                        )
                    else:
                        cur.execute(
                            f"DELETE FROM `{table}` WHERE `account_id` = %s "
                            f"AND `transaction_date` >= %s AND `transaction_date` <= %s",
                            (account_id, date_from, date_to),
                        )
                else:
                    cur.execute(
                        f"DELETE FROM `{table}` WHERE `account_id` = %s "
                        f"AND `transaction_date` >= %s AND `transaction_date` <= %s",
                        (account_id, date_from, date_to),
                    )
            self._conn.commit()
        except Exception:
            self._conn.rollback()
            raise

    def iter_table(self, table: str) -> Any:
        with self._conn.cursor() as cur:
            cur.execute(f"SELECT * FROM `{table}`")
            return [dict(r) for r in cur.fetchall()]

    def iter_where(
        self,
        table: str,
        where: dict[str, Any] | None = None,
        where_in: dict[str, list[Any]] | None = None,
        date_column: str | None = None,
        date_ranges: list[Any] | None = None,
    ) -> list[dict[str, Any]]:
        allowed = self._table_columns(table)
        clauses: list[str] = []
        args: list[Any] = []

        if where:
            for col, val in where.items():
                if col not in allowed:
                    raise UnknownColumn(f"store_db: {table}.{col} is not a column")
                clauses.append(f"`{col}` = %s")
                args.append(val)

        if where_in:
            for col, vals in where_in.items():
                if col not in allowed:
                    raise UnknownColumn(f"store_db: {table}.{col} is not a column")
                if not vals:
                    return []
                placeholders = ", ".join(["%s"] * len(vals))
                clauses.append(f"`{col}` IN ({placeholders})")
                args.extend(vals)

        if date_column and date_ranges:
            if date_column not in allowed:
                raise UnknownColumn(f"store_db: {table}.{date_column} is not a column")
            if not date_ranges:
                return []
            range_clauses = []
            for r in date_ranges:
                range_clauses.append(f"(`{date_column}` >= %s AND `{date_column}` <= %s)")
                args.extend([r.date_from, r.date_to])
            clauses.append(f"({' OR '.join(range_clauses)})")

        where_sql = f" WHERE {' AND '.join(clauses)}" if clauses else ""
        sql = f"SELECT * FROM `{table}`{where_sql}"
        with self._conn.cursor() as cur:
            cur.execute(sql, tuple(args))
            return [dict(r) for r in cur.fetchall()]

    def max_value(self, table: str, column: str) -> Any:
        allowed = self._table_columns(table)
        if column not in allowed:
            raise UnknownColumn(f"store_db: {table}.{column} is not a column")
        with self._conn.cursor() as cur:
            cur.execute(f"SELECT MAX(`{column}`) AS v FROM `{table}`")
            row = cur.fetchone()
        return row["v"] if row else None

    def add_pending(
        self, dataset: str, doc_id: str, modified_time: str = "", reason: str = "", error: str | None = None
    ) -> None:
        with self._conn.cursor() as cur:
            cur.execute(
                "INSERT INTO sync_pending "
                "(dataset, doc_id, modified_time, reason, last_error, attempts, first_seen, last_tried) "
                "VALUES (%s, %s, %s, %s, %s, 1, %s, %s) "
                "ON DUPLICATE KEY UPDATE "
                "modified_time = VALUES(modified_time), reason = VALUES(reason), "
                "last_error = VALUES(last_error), attempts = attempts + 1, "
                "last_tried = VALUES(last_tried)",
                (dataset, doc_id, modified_time, reason, error, datetime.now(), datetime.now()),
            )
        self._conn.commit()

    def list_pending(self, dataset: str) -> list[dict[str, Any]]:
        with self._conn.cursor() as cur:
            cur.execute("SELECT * FROM sync_pending WHERE dataset = %s", (dataset,))
            return [dict(r) for r in cur.fetchall()]

    def clear_pending(self, dataset: str, doc_id: str) -> None:
        with self._conn.cursor() as cur:
            cur.execute("DELETE FROM sync_pending WHERE dataset = %s AND doc_id = %s", (dataset, doc_id))
        self._conn.commit()

    def get_watermark(self, dataset: str) -> str | None:
        with self._conn.cursor() as cur:
            cur.execute("SELECT watermark FROM sync_state WHERE dataset = %s", (dataset,))
            row = cur.fetchone()
        if not row:
            return None
        value = row["watermark"]
        return value or None

    def set_watermark(self, dataset: str, watermark: str) -> None:
        with self._conn.cursor() as cur:
            cur.execute(
                "INSERT INTO sync_state (dataset, watermark, last_run_at) VALUES (%s, %s, %s) "
                "ON DUPLICATE KEY UPDATE watermark = VALUES(watermark), last_run_at = VALUES(last_run_at)",
                (dataset, watermark, datetime.now()),
            )
        self._conn.commit()
