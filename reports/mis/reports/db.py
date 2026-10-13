"""MariaDB storage for processed MIS data.

Config (reports/mis/.env, git-ignored):

    MIS_DB_HOST=127.0.0.1  MIS_DB_PORT=3306  MIS_DB_USER=…  MIS_DB_PASSWORD=…  MIS_DB_NAME=nellon_mis

Every `financials` / `margin` run is stored as a `report_runs` row; its data
hangs off `run_id` (ON DELETE CASCADE), so old runs can be dropped cleanly.
`category_master` holds the current mapping (upserted).

    report_runs        one row per run (kind = financials | margin | purchases)
    tb_accounts        monthly TB per account: opening, period Dr/Cr, movement, closing
    tb_monthly         per-account net movement for each month (long format)
    statement_lines    Executive Summary / PL / BS lines in display order
    statement_values   amount per line per column (month or Total)
    margin_lines       invoice-line margin rows
    purchase_lines     bill / purchase-order line rows
    category_master    current ledger → PL/BS / category mapping
    cashflow_runs      one forecast pull (as-of date, opening cash, totals)
    cashflow_accounts  leaf bank and cash balances for that run
    cashflow_events    dated AR / AP / PO / SO movements
    cashflow_unscheduled  open items with no cash date

The web viewer reads only from here — it never calls Zoho.
"""

from __future__ import annotations

import json
import os
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Any, Iterator

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS report_runs (
        id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        kind              VARCHAR(20)  NOT NULL,
        organization_id   VARCHAR(32)  NOT NULL DEFAULT '',
        organization_name VARCHAR(200) NOT NULL DEFAULT '',
        currency_code     VARCHAR(8)   NOT NULL DEFAULT '',
        from_date         DATE         NOT NULL,
        to_date           DATE         NOT NULL,
        fiscal_year_start DATE         NULL,
        months            TEXT         NOT NULL,
        summary           LONGTEXT     NOT NULL,
        source            VARCHAR(255) NOT NULL DEFAULT '',
        created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_runs_kind_period (kind, from_date, to_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS tb_accounts (
        run_id              BIGINT UNSIGNED NOT NULL,
        account_id          VARCHAR(40)   NOT NULL,
        account_code        VARCHAR(40)   NOT NULL DEFAULT '',
        account_name        VARCHAR(255)  NOT NULL DEFAULT '',
        account_type        VARCHAR(40)   NOT NULL DEFAULT '',
        parent_account_name VARCHAR(255)  NOT NULL DEFAULT '',
        group_ledger        VARCHAR(10)   NOT NULL DEFAULT '',
        pl_bs               CHAR(2)       NOT NULL DEFAULT '',
        category            VARCHAR(120)  NOT NULL DEFAULT '',
        sub_category        VARCHAR(255)  NOT NULL DEFAULT '',
        category_source     VARCHAR(12)   NOT NULL DEFAULT '',
        opening             DECIMAL(18,2) NOT NULL DEFAULT 0,
        period_debit        DECIMAL(18,2) NOT NULL DEFAULT 0,
        period_credit       DECIMAL(18,2) NOT NULL DEFAULT 0,
        movement            DECIMAL(18,2) NOT NULL DEFAULT 0,
        closing             DECIMAL(18,2) NOT NULL DEFAULT 0,
        PRIMARY KEY (run_id, account_id),
        KEY ix_tb_category (run_id, pl_bs, category),
        CONSTRAINT fk_tb_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS tb_monthly (
        run_id     BIGINT UNSIGNED NOT NULL,
        account_id VARCHAR(40)   NOT NULL,
        month      CHAR(7)       NOT NULL,
        amount     DECIMAL(18,2) NOT NULL DEFAULT 0,
        PRIMARY KEY (run_id, account_id, month),
        CONSTRAINT fk_tbm_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS statement_lines (
        run_id    BIGINT UNSIGNED NOT NULL,
        statement VARCHAR(40)  NOT NULL,
        line_no   INT UNSIGNED NOT NULL,
        label     VARCHAR(255) NOT NULL,
        kind      VARCHAR(12)  NOT NULL,
        PRIMARY KEY (run_id, statement, line_no),
        CONSTRAINT fk_sl_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS statement_values (
        run_id    BIGINT UNSIGNED NOT NULL,
        statement VARCHAR(40)  NOT NULL,
        line_no   INT UNSIGNED NOT NULL,
        col       VARCHAR(20)  NOT NULL,
        col_order INT UNSIGNED NOT NULL,
        amount    DECIMAL(20,4) NOT NULL DEFAULT 0,
        PRIMARY KEY (run_id, statement, line_no, col),
        CONSTRAINT fk_sv_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS margin_lines (
        run_id           BIGINT UNSIGNED NOT NULL,
        line_no          INT UNSIGNED  NOT NULL,
        month            CHAR(7)       NOT NULL,
        date             DATE          NULL,
        invoice_id       VARCHAR(40)   NOT NULL DEFAULT '',
        invoice_number   VARCHAR(60)   NOT NULL DEFAULT '',
        customer_name    VARCHAR(255)  NOT NULL DEFAULT '',
        salesperson_name VARCHAR(255)  NOT NULL DEFAULT '',
        van              VARCHAR(255)  NOT NULL DEFAULT '',
        item_id          VARCHAR(40)   NOT NULL DEFAULT '',
        item_name        VARCHAR(255)  NOT NULL DEFAULT '',
        sku              VARCHAR(100)  NOT NULL DEFAULT '',
        unit             VARCHAR(40)   NOT NULL DEFAULT '',
        quantity         DECIMAL(18,4) NOT NULL DEFAULT 0,
        conversion_rate  DECIMAL(18,6) NOT NULL DEFAULT 1,
        base_quantity    DECIMAL(18,4) NOT NULL DEFAULT 0,
        rate             DECIMAL(18,4) NOT NULL DEFAULT 0,
        gross_amount     DECIMAL(18,2) NOT NULL DEFAULT 0,
        line_discount    DECIMAL(18,2) NOT NULL DEFAULT 0,
        invoice_discount DECIMAL(18,2) NOT NULL DEFAULT 0,
        net_sales        DECIMAL(18,2) NOT NULL DEFAULT 0,
        cost_rate        DECIMAL(18,4) NOT NULL DEFAULT 0,
        cost             DECIMAL(18,2) NOT NULL DEFAULT 0,
        gross_margin     DECIMAL(18,2) NOT NULL DEFAULT 0,
        flag             VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        KEY ix_margin_month (run_id, month),
        CONSTRAINT fk_ml_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS purchase_lines (
        run_id      BIGINT UNSIGNED NOT NULL,
        line_no     INT UNSIGNED  NOT NULL,
        month       CHAR(7)       NOT NULL,
        date        DATE          NULL,
        kind        VARCHAR(20)   NOT NULL DEFAULT '',
        number      VARCHAR(60)   NOT NULL DEFAULT '',
        vendor_name VARCHAR(255)  NOT NULL DEFAULT '',
        status      VARCHAR(40)   NOT NULL DEFAULT '',
        item_id     VARCHAR(40)   NOT NULL DEFAULT '',
        item_name   VARCHAR(255)  NOT NULL DEFAULT '',
        sku         VARCHAR(100)  NOT NULL DEFAULT '',
        unit        VARCHAR(40)   NOT NULL DEFAULT '',
        quantity    DECIMAL(18,4) NOT NULL DEFAULT 0,
        rate        DECIMAL(18,4) NOT NULL DEFAULT 0,
        amount      DECIMAL(18,2) NOT NULL DEFAULT 0,
        doc_id      VARCHAR(40)   NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        KEY ix_purchase_month (run_id, month),
        CONSTRAINT fk_pl_run FOREIGN KEY (run_id) REFERENCES report_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS category_master (
        account_id          VARCHAR(40)   NOT NULL PRIMARY KEY,
        account_code        VARCHAR(40)   NOT NULL DEFAULT '',
        ledger_name         VARCHAR(255)  NOT NULL DEFAULT '',
        entity_name         VARCHAR(200)  NOT NULL DEFAULT '',
        group_ledger        VARCHAR(10)   NOT NULL DEFAULT '',
        pl_bs               CHAR(2)       NOT NULL DEFAULT '',
        category            VARCHAR(120)  NOT NULL DEFAULT '',
        sub_category        VARCHAR(255)  NOT NULL DEFAULT '',
        source              VARCHAR(12)   NOT NULL DEFAULT '',
        note                VARCHAR(500)  NOT NULL DEFAULT '',
        account_type        VARCHAR(40)   NOT NULL DEFAULT '',
        parent_account_name VARCHAR(255)  NOT NULL DEFAULT '',
        path                VARCHAR(1000) NOT NULL DEFAULT '',
        current_balance     DECIMAL(18,2) NOT NULL DEFAULT 0,
        is_active           TINYINT(1)    NOT NULL DEFAULT 1,
        updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_runs (
        id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        as_of             DATE         NOT NULL,
        organization_id   VARCHAR(32)  NOT NULL DEFAULT '',
        organization_name VARCHAR(200) NOT NULL DEFAULT '',
        currency_code     VARCHAR(8)   NOT NULL DEFAULT '',
        opening           DECIMAL(18,2) NOT NULL DEFAULT 0,
        ar_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        ap_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        po_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        so_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        counts_json       TEXT         NOT NULL,
        notes             TEXT         NOT NULL,
        api_calls         INT          NOT NULL DEFAULT 0,
        source            VARCHAR(255) NOT NULL DEFAULT '',
        created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_cf_asof (as_of)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_accounts (
        run_id       BIGINT UNSIGNED NOT NULL,
        line_no      INT UNSIGNED  NOT NULL,
        account_name VARCHAR(255)  NOT NULL,
        account_type VARCHAR(20)   NOT NULL,
        balance      DECIMAL(18,2) NOT NULL,
        PRIMARY KEY (run_id, line_no),
        CONSTRAINT fk_cfa_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_events (
        run_id      BIGINT UNSIGNED NOT NULL,
        line_no     INT UNSIGNED  NOT NULL,
        cash_date   DATE          NOT NULL,
        source_date DATE          NULL,
        overdue     TINYINT(1)    NOT NULL DEFAULT 0,
        kind        VARCHAR(8)    NOT NULL,
        amount      DECIMAL(18,2) NOT NULL,
        party       VARCHAR(255)  NOT NULL DEFAULT '',
        number      VARCHAR(60)   NOT NULL DEFAULT '',
        label       VARCHAR(120)  NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        KEY ix_cfe_date (run_id, cash_date),
        CONSTRAINT fk_cfe_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_unscheduled (
        run_id  BIGINT UNSIGNED NOT NULL,
        line_no INT UNSIGNED  NOT NULL,
        kind    VARCHAR(8)    NOT NULL,
        number  VARCHAR(60)   NOT NULL DEFAULT '',
        party   VARCHAR(255)  NOT NULL DEFAULT '',
        amount  DECIMAL(18,2) NOT NULL,
        reason  VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        CONSTRAINT fk_cfu_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
]

MARGIN_DB_COLUMNS = [
    "month", "date", "invoice_id", "invoice_number", "customer_name", "salesperson_name", "van",
    "item_id", "item_name", "sku", "unit", "quantity", "conversion_rate", "base_quantity", "rate",
    "gross_amount", "line_discount", "invoice_discount", "net_sales", "cost_rate", "cost",
    "gross_margin", "flag",
]
MARGIN_DIMENSIONS = {
    "item": "item_name",
    "customer": "customer_name",
    "salesperson": "salesperson_name",
    "van": "van",
}
PURCHASE_DB_COLUMNS = [
    "month", "date", "kind", "number", "vendor_name", "status", "item_id", "item_name", "sku", "unit",
    "quantity", "rate", "amount", "doc_id",
]
PURCHASE_DIMENSIONS = {"vendor": "vendor_name", "item": "item_name", "kind": "kind"}
PURCHASE_MEASURES = {"amount", "quantity", "documents"}
MARGIN_MEASURES = {"net_sales", "cost", "gross_margin", "base_quantity", "gm_pct"}

CATEGORY_DB_COLUMNS = [
    "account_id", "account_code", "ledger_name", "entity_name", "group_ledger", "pl_bs", "category",
    "sub_category", "source", "note", "account_type", "parent_account_name", "path",
    "current_balance", "is_active",
]


def config() -> dict[str, Any] | None:
    """DB settings from env, or None when MIS_DB_NAME isn't configured."""
    name = os.getenv("MIS_DB_NAME")
    if not name:
        return None
    return {
        "host": os.getenv("MIS_DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("MIS_DB_PORT", "3306")),
        "user": os.getenv("MIS_DB_USER", ""),
        "password": os.getenv("MIS_DB_PASSWORD", ""),
        "database": name,
    }


def enabled() -> bool:
    return config() is not None


@contextmanager
def connect(*, database: bool = True) -> Iterator[Any]:
    import pymysql

    cfg = config()
    if cfg is None:
        raise RuntimeError("MariaDB not configured — set MIS_DB_* in reports/mis/.env")
    if not database:
        cfg = {k: v for k, v in cfg.items() if k != "database"}
    conn = pymysql.connect(**cfg, charset="utf8mb4", autocommit=False,
                           cursorclass=pymysql.cursors.DictCursor)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_schema() -> str:
    """Create the database (if missing) and all tables. Idempotent."""
    cfg = config()
    if cfg is None:
        raise RuntimeError("MariaDB not configured — set MIS_DB_* in reports/mis/.env")
    name = cfg["database"]
    if not name.replace("_", "").isalnum():
        raise ValueError(f"unsafe database name {name!r}")
    with connect(database=False) as conn, conn.cursor() as cur:
        cur.execute(
            f"CREATE DATABASE IF NOT EXISTS `{name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
    with connect() as conn, conn.cursor() as cur:
        for ddl in SCHEMA:
            cur.execute(ddl)
    return name


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------


def _new_run(cur: Any, kind: str, summary: dict[str, Any], months: list[str], source: str) -> int:
    cur.execute(
        """INSERT INTO report_runs
           (kind, organization_id, organization_name, currency_code, from_date, to_date,
            fiscal_year_start, months, summary, source)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        (
            kind,
            str(summary.get("organization_id") or ""),
            summary.get("organization_name") or "",
            summary.get("currency_code") or "",
            summary["from_date"],
            summary["to_date"],
            summary.get("fiscal_year_start") or None,
            json.dumps(months),
            json.dumps(summary),
            source[:255],
        ),
    )
    return int(cur.lastrowid)


def save_financials_run(
    tb_rows: list[dict[str, Any]],
    summary: dict[str, Any],
    statements: list[Any],
    *,
    source: str,
) -> int:
    months = list(summary.get("months") or [])
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "financials", summary, months, source)
        cur.executemany(
            """INSERT INTO tb_accounts
               (run_id, account_id, account_code, account_name, account_type, parent_account_name,
                group_ledger, pl_bs, category, sub_category, category_source,
                opening, period_debit, period_credit, movement, closing)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            [
                (run_id, r["account_id"], r.get("account_code", ""), r.get("account_name", ""),
                 r.get("account_type", ""), r.get("parent_account_name", ""), r.get("group_ledger", ""),
                 r.get("pl_bs", ""), r.get("category", ""), r.get("sub_category", ""),
                 r.get("category_source", ""), r.get("opening", 0), r.get("period_debit", 0),
                 r.get("period_credit", 0), r.get("movement", 0), r.get("closing", 0))
                for r in tb_rows
            ],
        )
        cur.executemany(
            "INSERT INTO tb_monthly (run_id, account_id, month, amount) VALUES (%s,%s,%s,%s)",
            [(run_id, r["account_id"], m, r.get(m, 0) or 0) for r in tb_rows for m in months
             if abs(float(r.get(m, 0) or 0)) >= 0.005],
        )
        line_rows, value_rows = [], []
        for st in statements:
            for line_no, ln in enumerate(st.lines, 1):
                line_rows.append((run_id, st.name, line_no, ln.label[:255], ln.kind))
                for order, col in enumerate(st.columns):
                    if col in ln.values:
                        value_rows.append((run_id, st.name, line_no, col, order, ln.values[col]))
        cur.executemany(
            "INSERT INTO statement_lines (run_id, statement, line_no, label, kind) VALUES (%s,%s,%s,%s,%s)",
            line_rows,
        )
        cur.executemany(
            """INSERT INTO statement_values (run_id, statement, line_no, col, col_order, amount)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            value_rows,
        )
    return run_id


def save_margin_run(rows: list[dict[str, Any]], summary: dict[str, Any], *, source: str) -> int:
    months = sorted({r["month"] for r in rows if r.get("month")})
    cols = ", ".join(MARGIN_DB_COLUMNS)
    marks = ", ".join(["%s"] * (len(MARGIN_DB_COLUMNS) + 2))
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "margin", summary, months, source)
        cur.executemany(
            f"INSERT INTO margin_lines (run_id, line_no, {cols}) VALUES ({marks})",
            [
                (run_id, n, *[(r.get(c) or None) if c == "date" else r.get(c, "") for c in MARGIN_DB_COLUMNS])
                for n, r in enumerate(rows, 1)
            ],
        )
    return run_id


def save_purchases_run(rows: list[dict[str, Any]], summary: dict[str, Any], *, source: str) -> int:
    months = sorted({r["month"] for r in rows if r.get("month")})
    cols = ", ".join(PURCHASE_DB_COLUMNS)
    marks = ", ".join(["%s"] * (len(PURCHASE_DB_COLUMNS) + 2))
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "purchases", summary, months, source)
        cur.executemany(
            f"INSERT INTO purchase_lines (run_id, line_no, {cols}) VALUES ({marks})",
            [
                (run_id, n, *[(r.get(c) or None) if c == "date" else r.get(c, "") for c in PURCHASE_DB_COLUMNS])
                for n, r in enumerate(rows, 1)
            ],
        )
    return run_id


def _sql_date(value: Any) -> str | None:
    text = str(value or "")[:10]
    return text if len(text) == 10 and text[4] == "-" else None


def save_cashflow_run(
    payload: dict[str, Any],
    *,
    organization_id: str,
    api_calls: int,
    source: str,
) -> int:
    """Store one forecast. Returns cashflow_runs.id."""
    totals = payload.get("totals") or {}
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """INSERT INTO cashflow_runs
               (as_of, organization_id, organization_name, currency_code, opening,
                ar_total, ap_total, po_total, so_total, counts_json, notes, api_calls, source)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (
                payload["as_of"],
                organization_id,
                payload.get("organization") or "",
                payload.get("currency") or "",
                payload.get("opening") or 0,
                totals.get("ar") or 0,
                totals.get("ap") or 0,
                totals.get("po") or 0,
                totals.get("so") or 0,
                json.dumps(payload.get("counts") or {}),
                json.dumps(payload.get("notes") or []),
                api_calls,
                source[:255],
            ),
        )
        run_id = int(cur.lastrowid)
        accounts = [
            (run_id, n, (row.get("name") or "")[:255], (row.get("type") or "")[:20], row.get("balance") or 0)
            for n, row in enumerate(payload.get("accounts") or [], 1)
        ]
        if accounts:
            cur.executemany(
                """INSERT INTO cashflow_accounts (run_id, line_no, account_name, account_type, balance)
                   VALUES (%s,%s,%s,%s,%s)""",
                accounts,
            )
        events = [
            (
                run_id, n, row["date"], _sql_date(row.get("source_date")), 1 if row.get("overdue") else 0,
                (row.get("kind") or "")[:8], row.get("amount") or 0,
                (row.get("party") or "")[:255], (row.get("number") or "")[:60], (row.get("label") or "")[:120],
            )
            for n, row in enumerate(payload.get("events") or [], 1)
        ]
        if events:
            cur.executemany(
                """INSERT INTO cashflow_events
                   (run_id, line_no, cash_date, source_date, overdue, kind, amount, party, number, label)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                events,
            )
        pending = [
            (
                run_id, n, (row.get("kind") or "")[:8], (row.get("number") or "")[:60],
                (row.get("party") or "")[:255], row.get("amount") or 0, (row.get("reason") or "")[:255],
            )
            for n, row in enumerate(payload.get("unscheduled") or [], 1)
        ]
        if pending:
            cur.executemany(
                """INSERT INTO cashflow_unscheduled (run_id, line_no, kind, number, party, amount, reason)
                   VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                pending,
            )
    return run_id


def save_category_master(rows: list[dict[str, Any]]) -> int:
    cols = ", ".join(CATEGORY_DB_COLUMNS)
    marks = ", ".join(["%s"] * len(CATEGORY_DB_COLUMNS))
    updates = ", ".join(f"{c}=VALUES({c})" for c in CATEGORY_DB_COLUMNS if c != "account_id")
    with connect() as conn, conn.cursor() as cur:
        cur.executemany(
            f"INSERT INTO category_master ({cols}) VALUES ({marks}) ON DUPLICATE KEY UPDATE {updates}",
            [tuple(r.get(c, "") for c in CATEGORY_DB_COLUMNS) for r in rows],
        )
        ids = [r["account_id"] for r in rows]
        if ids:
            cur.execute(
                f"DELETE FROM category_master WHERE account_id NOT IN ({', '.join(['%s'] * len(ids))})", ids
            )
    return len(rows)


def get_category_master() -> list[dict[str, Any]]:
    """Saved ledger → category mapping (empty until `main.py category-master` has saved it)."""
    cols = ", ".join(CATEGORY_DB_COLUMNS)
    with connect() as conn, conn.cursor() as cur:
        cur.execute(f"SELECT {cols} FROM category_master ORDER BY pl_bs, category, ledger_name")
        return [_clean(r) for r in cur.fetchall()]


def delete_run(run_id: int) -> bool:
    with connect() as conn, conn.cursor() as cur:
        return cur.execute("DELETE FROM report_runs WHERE id = %s", (run_id,)) > 0


# ---------------------------------------------------------------------------
# Reads (web viewer)
# ---------------------------------------------------------------------------


def _jsonable(v: Any) -> Any:
    if isinstance(v, date):
        return v.isoformat()
    if hasattr(v, "is_finite"):  # Decimal
        return float(v)
    return v


def _clean(row: dict[str, Any]) -> dict[str, Any]:
    return {k: _jsonable(v) for k, v in row.items()}


def list_runs(kind: str | None = None, limit: int = 100) -> list[dict[str, Any]]:
    sql = """SELECT id, kind, organization_name, currency_code, from_date, to_date, fiscal_year_start,
                    months, source, created_at
             FROM report_runs {where} ORDER BY id DESC LIMIT %s"""
    params: list[Any] = []
    where = ""
    if kind:
        where, params = "WHERE kind = %s", [kind]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql.format(where=where), [*params, limit])
        out = []
        for r in cur.fetchall():
            r = _clean(r)
            r["months"] = json.loads(r["months"] or "[]")
            r["created_at"] = str(r["created_at"])
            out.append(r)
        return out


def get_run(run_id: int) -> dict[str, Any] | None:
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM report_runs WHERE id = %s", (run_id,))
        r = cur.fetchone()
    if not r:
        return None
    r = _clean(r)
    r["months"] = json.loads(r["months"] or "[]")
    r["summary"] = json.loads(r["summary"] or "{}")
    r["created_at"] = str(r["created_at"])
    return r


def get_statement(run_id: int, statement: str) -> dict[str, Any]:
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT line_no, label, kind FROM statement_lines WHERE run_id=%s AND statement=%s ORDER BY line_no",
            (run_id, statement),
        )
        lines = {r["line_no"]: {"label": r["label"], "kind": r["kind"], "values": {}} for r in cur.fetchall()}
        cur.execute(
            """SELECT line_no, col, col_order, amount FROM statement_values
               WHERE run_id=%s AND statement=%s ORDER BY col_order""",
            (run_id, statement),
        )
        columns: dict[str, int] = {}
        for r in cur.fetchall():
            columns.setdefault(r["col"], r["col_order"])
            if r["line_no"] in lines:
                lines[r["line_no"]]["values"][r["col"]] = float(r["amount"])
    return {
        "statement": statement,
        "columns": sorted(columns, key=columns.get),
        "lines": [lines[k] for k in sorted(lines)],
    }


def get_trial_balance(run_id: int) -> dict[str, Any]:
    run = get_run(run_id)
    months = run["months"] if run else []
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT account_id, account_code, account_name, account_type, pl_bs, category, sub_category,
                      category_source, opening, period_debit, period_credit, movement, closing
               FROM tb_accounts WHERE run_id=%s
               ORDER BY pl_bs DESC, category, account_code, account_name""",
            (run_id,),
        )
        rows = {r["account_id"]: _clean(r) for r in cur.fetchall()}
        cur.execute("SELECT account_id, month, amount FROM tb_monthly WHERE run_id=%s", (run_id,))
        for r in cur.fetchall():
            if r["account_id"] in rows:
                rows[r["account_id"]][r["month"]] = float(r["amount"])
    for r in rows.values():
        for m in months:
            r.setdefault(m, 0.0)
    return {"months": months, "rows": list(rows.values())}


def get_margin_pivot(run_id: int, dimension: str, measure: str) -> dict[str, Any]:
    """Rows = dimension values, columns = months + Total."""
    if dimension not in MARGIN_DIMENSIONS or measure not in MARGIN_MEASURES:
        raise ValueError("unknown dimension or measure")
    col = MARGIN_DIMENSIONS[dimension]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""SELECT {col} AS dim, month,
                       SUM(net_sales) AS net_sales, SUM(cost) AS cost,
                       SUM(gross_margin) AS gross_margin, SUM(base_quantity) AS base_quantity,
                       SUM(flag <> '') AS flagged
                FROM margin_lines WHERE run_id=%s GROUP BY {col}, month""",
            (run_id,),
        )
        data = cur.fetchall()

    def value(agg: dict[str, float]) -> float:
        if measure == "gm_pct":
            return round(agg["gross_margin"] / agg["net_sales"], 4) if agg["net_sales"] else 0.0
        return round(agg[measure], 4)

    months = sorted({r["month"] for r in data})
    by_dim: dict[str, dict[str, dict[str, float]]] = {}
    for r in data:
        cell = {k: float(r[k] or 0) for k in ("net_sales", "cost", "gross_margin", "base_quantity", "flagged")}
        by_dim.setdefault(r["dim"] or "(none)", {})[r["month"]] = cell

    def total(cells: list[dict[str, float]]) -> dict[str, float]:
        keys = ("net_sales", "cost", "gross_margin", "base_quantity", "flagged")
        return {k: sum(c.get(k, 0.0) for c in cells) for k in keys}

    rows = []
    for dim, per_month in by_dim.items():
        t = total(list(per_month.values()))
        values = {m: value(per_month[m]) for m in per_month}
        values["Total"] = value(t)
        rows.append({"label": dim, "values": values, "net_sales": t["net_sales"], "flagged": int(t["flagged"])})
    rows.sort(key=lambda r: r["net_sales"], reverse=True)

    grand_by_month = {m: total([pm[m] for pm in by_dim.values() if m in pm]) for m in months}
    grand = {m: value(v) for m, v in grand_by_month.items()}
    grand["Total"] = value(total(list(grand_by_month.values())))
    return {"columns": months + ["Total"], "rows": rows, "total": grand,
            "dimension": dimension, "measure": measure}



def get_margin_detail(run_id: int, view: str) -> dict[str, Any]:
    """Margin as a flat list: one row per invoice line (`line`) or per invoice (`invoice`)."""
    if view == "line":
        sql = """SELECT date, invoice_number, customer_name, item_name, unit, quantity, rate,
                        net_sales, cost_rate, cost, gross_margin, flag
                 FROM margin_lines WHERE run_id=%s ORDER BY date, invoice_number, line_no"""
    elif view == "invoice":
        sql = """SELECT MIN(date) AS date, invoice_number, MAX(customer_name) AS customer_name,
                        MAX(salesperson_name) AS salesperson_name, COUNT(*) AS line_count,
                        SUM(net_sales) AS net_sales, SUM(cost) AS cost, SUM(gross_margin) AS gross_margin,
                        SUM(flag <> '') AS flagged
                 FROM margin_lines WHERE run_id=%s GROUP BY invoice_id, invoice_number
                 ORDER BY MIN(date), invoice_number"""
    else:
        raise ValueError("view must be line or invoice")
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, (run_id,))
        rows = cur.fetchall()
    for r in rows:
        r["date"] = r["date"].isoformat() if r["date"] else ""
        for k, v in r.items():
            if hasattr(v, "as_tuple"):  # Decimal
                r[k] = float(v)
        r["gm_pct"] = round(r["gross_margin"] / r["net_sales"], 4) if r["net_sales"] else 0.0
    t = {k: sum(r[k] for r in rows) for k in ("net_sales", "cost", "gross_margin")}
    t["gm_pct"] = round(t["gross_margin"] / t["net_sales"], 4) if t["net_sales"] else 0.0
    return {"view": view, "rows": rows, "total": t}


def get_purchase_pivot(run_id: int, dimension: str, measure: str) -> dict[str, Any]:
    """Rows = dimension values, columns = months + Total (same shape as the margin pivot)."""
    if dimension not in PURCHASE_DIMENSIONS or measure not in PURCHASE_MEASURES:
        raise ValueError("unknown dimension or measure")
    col = PURCHASE_DIMENSIONS[dimension]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""SELECT {col} AS dim, month, SUM(amount) AS amount, SUM(quantity) AS quantity,
                       COUNT(DISTINCT kind, doc_id) AS documents
                FROM purchase_lines WHERE run_id=%s GROUP BY {col}, month""",
            (run_id,),
        )
        data = cur.fetchall()
        cur.execute(
            f"""SELECT {col} AS dim, SUM(amount) AS amount, SUM(quantity) AS quantity,
                       COUNT(DISTINCT kind, doc_id) AS documents
                FROM purchase_lines WHERE run_id=%s GROUP BY {col}""",
            (run_id,),
        )
        dim_totals = {(r["dim"] or "(none)"): r for r in cur.fetchall()}
        cur.execute(
            "SELECT SUM(amount) AS amount, SUM(quantity) AS quantity, COUNT(DISTINCT kind, doc_id) AS documents "
            "FROM purchase_lines WHERE run_id=%s",
            (run_id,),
        )
        grand_total = cur.fetchone() or {}
        cur.execute(
            "SELECT month, SUM(amount) AS amount, SUM(quantity) AS quantity, COUNT(DISTINCT kind, doc_id) AS documents "
            "FROM purchase_lines WHERE run_id=%s GROUP BY month",
            (run_id,),
        )
        month_totals = {r["month"]: r for r in cur.fetchall()}

    def val(r: dict[str, Any]) -> float:
        return round(float(r.get(measure) or 0), 4)

    months = sorted({r["month"] for r in data})
    by_dim: dict[str, dict[str, float]] = {}
    for r in data:
        by_dim.setdefault(r["dim"] or "(none)", {})[r["month"]] = val(r)
    rows = []
    for dim, values in by_dim.items():
        values["Total"] = val(dim_totals[dim])
        rows.append({"label": dim, "values": values, "amount": float(dim_totals[dim]["amount"] or 0)})
    rows.sort(key=lambda r: r["amount"], reverse=True)
    total = {m: val(month_totals[m]) for m in months}
    total["Total"] = val(grand_total)
    return {"columns": months + ["Total"], "rows": rows, "total": total, "dimension": dimension, "measure": measure}
