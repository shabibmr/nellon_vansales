"""Local web editor for the Category Master (stdlib only).

    GET  / or /reports           → web/reports.html (report viewer; reads MariaDB only)
    GET  /sales-dashboard        → loader page; the dashboard files come from /api/sales-dashboard/* (JWT only)
    GET  /cashflow               → web/cashflow.html (day seeker; reads the local cache, no Zoho)
    GET  /categories             → web/category_master.html (Category Master editor)

All page/asset/API URLs in the web files are relative, so the app also works
behind a reverse proxy under a sub-path (e.g. /koyson-zoho/acc-reports/).
    GET  /assets/<name>.css|.js|.svg → web/assets/ (shared styles, page scripts, icon sprite)
    GET  /api/org                → organization profile (name, currency) from the `organization` table
    GET  /api/config             → {live_financials, fiscal_year_start_month}
    GET  /api/statement?name=&cols=key:from:to,…[&refresh=1]   live from Zoho (MIS_LIVE_FINANCIALS=1):
         Executive Summary | PL | BS (+ expandable `tree` for the first two), with fetched_at / stale /
         zoho_calls
    GET  /api/tb?cols=…[&refresh=1]   live trial balance
    GET  /api/coverage?dataset=sales|purchases  → loaded date ranges and gaps
    GET  /api/margin?from=&to=[&cols=key:from:to,…]&dim=&measure=   margin pivot over any dates
         (columns = the given ranges, default one per month + Total)
    GET  /api/margin-detail?from=&to=&view=line|invoice   margin per invoice line / per invoice
    GET  /api/purchases?from=&to=[&cols=…]&dim=&measure=   bills + purchase orders pivot
    GET  /api/export.xlsx?cols=…  → Excel workbook: live financials + margin / purchases for those columns
    GET  /api/category-master    → rows read from the `accounts` table
    GET  /api/cashflow           → cash forecast from the COA snapshot and cached documents (no Zoho)
    POST /api/category-override  → {account_id, pl_bs, category, sub_category, note}: save a mapping override
    POST /api/category-override/delete → {account_id}: drop the override (back to rule/type)

Overrides are written to category_overrides.csv (so a reseed keeps them), saved to `accounts`
(source='override'), and logged to output/category_audit.log with the Zoho user id. Editing needs the Zoho JWT
auth to be enabled (MIS_JWT_SECRET); without it the endpoints refuse. Live financials apply a changed
mapping at once.

Live financials call Zoho only for GL periods not cached in this process (reports/live_financials.py:
15-minute cache, one Zoho fetch at a time, last good copy served when Zoho fails).

Zoho credentials stay server-side. Binds to 127.0.0.1 by default. Every /api route needs the
Zoho web-tab JWT as a Bearer header; pages/assets are refused unless the browser loads them inside an
iframe (Sec-Fetch-Dest) and CSP frame-ancestors limits that iframe to Zoho. See reports/web_auth.py and
web/assets/webtab-auth.js. With MIS_JWT_SECRET unset all /api routes are refused (fail closed);
MIS_AUTH_DISABLED=1 skips both checks for local development only.
"""

from __future__ import annotations

import json
import os
import re
import threading
from pathlib import Path
from datetime import date, datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlsplit

from backend.exporters import write_csv, write_excel_sheets
from backend.main import BASE_DIR, COA_SNAPSHOT, OUT_DIR, OVERRIDES_CSV
from backend.reports import category_master as cm
from backend.reports import cashflow_forecast as cf
from backend.reports import web_auth
from common import db, periods
from backend.reports import live_financials as live
from backend.reports.excel_export import build_live_workbook

WEB_PAGE = BASE_DIR / "web" / "category_master.html"
REPORTS_PAGE = BASE_DIR / "web" / "reports.html"
CASHFLOW_PAGE = BASE_DIR / "web" / "cashflow.html"
DASHBOARD_PAGE = BASE_DIR / "web" / "sales_dashboard.html"
# The Sales Dashboard sources live in web/sales_dashboard/ (JWT-gated, never under /assets); override for a deploy that moves them.
DASHBOARD_DIR = Path(os.getenv("MIS_DASHBOARD_DIR") or BASE_DIR / "web" / "sales_dashboard")
_DASHBOARD_FILE = re.compile(r"^(index\.html|(css|js)/[A-Za-z0-9_.-]+\.(css|js))$")
ASSETS_DIR = BASE_DIR / "web" / "assets"
ASSET_TYPES = {
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
}
_ASSET_NAME = re.compile(r"^[A-Za-z0-9_-]+\.(css|js|svg)$")
STATEMENTS = {"Executive Summary", "PL", "BS"}

_lock = threading.Lock()


def _export(rows: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    """Keep output/category_master.* in step with every edit."""
    write_csv(rows, cm.COLUMNS, OUT_DIR / "category_master.csv")
    write_excel_sheets({"Category Master": (cm.COLUMNS, rows)}, OUT_DIR / "category_master.xlsx")
    (OUT_DIR / "category_master.json").write_text(
        json.dumps({"summary": summary, "rows": rows}, indent=1), encoding="utf-8"
    )


def _org_currency(fallback: str) -> str:
    """Currency code from `organization`; `fallback` if the DB has none."""
    try:
        if db.enabled():
            return db.get_organization().get("currency_code") or fallback
    except Exception:  # DB down: the cached snapshot is still good enough for a subtitle
        pass
    return fallback


def _payload(*, fresh: bool = False) -> dict[str, Any]:
    snapshot = db.coa_snapshot(refresh=fresh)
    rows = snapshot["categories"]
    summary = cm.category_master_summary(rows)
    _export(rows, summary)
    return {
        "can_edit": web_auth.enabled(),
        "currency_code": snapshot.get("currency_code", ""),
        "snapshot_time": (snapshot.get("synced_at") or "").replace(" ", "T"),
        "categories": cm.CATEGORIES,
        "summary": summary,
        "rows": rows,
    }


MAX_BODY = 16 * 1024
AUDIT_LOG = OUT_DIR / "category_audit.log"
_CTRL = re.compile(r"[\x00-\x1f\x7f]")


def _text(body: dict[str, Any], key: str, limit: int) -> str:
    v = body.get(key, "")
    if not isinstance(v, str):
        raise ValueError(f"{key} must be text")
    v = _CTRL.sub(" ", v).strip()
    if len(v) > limit:
        raise ValueError(f"{key} is longer than {limit} characters")
    return v


def _save_override(body: dict[str, Any], user: str, *, delete: bool) -> dict[str, Any]:
    """Validate + persist one override (or delete it), then return the rebuilt payload."""
    if not web_auth.enabled():
        raise PermissionError("Editing is disabled until Zoho JWT auth (MIS_JWT_SECRET) is configured")
    account_id = _text(body, "account_id", 40)
    snapshot = db.coa_snapshot()
    account = next((a for a in snapshot.get("accounts", []) if str(a.get("account_id")) == account_id), None)
    if not account:
        raise ValueError("unknown account_id")
    overrides = cm.load_overrides(OVERRIDES_CSV)
    before = overrides.get(account_id)
    if delete:
        if not overrides.pop(account_id, None):
            raise ValueError("this account has no override")
        after = None
    else:
        pl_bs = _text(body, "pl_bs", 2)
        category = _text(body, "category", 120)
        if pl_bs not in cm.CATEGORIES:
            raise ValueError("pl_bs must be PL or BS")
        if category not in cm.CATEGORIES[pl_bs]:
            raise ValueError(f"category must be one of the {pl_bs} reporting lines")
        after = {
            "account_id": account_id,
            "ledger_name": (account.get("account_name") or "").strip(),
            "pl_bs": pl_bs,
            "category": category,
            "sub_category": _text(body, "sub_category", 255),
            "note": _text(body, "note", 500),
        }
        overrides[account_id] = after
    cm.save_overrides(OVERRIDES_CSV, overrides)
    # Rebuild every row from the chart + overrides, then write the MIS columns to `accounts`.
    db.save_category_master(cm.build_category_master(snapshot, overrides))
    payload = _payload(fresh=True)
    with AUDIT_LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"at": datetime.now().isoformat(timespec="seconds"), "user": user,
                            "account_id": account_id, "before": before, "after": after}) + "\n")
    return payload


def _int(q: dict[str, str], key: str) -> int:
    try:
        return int(q.get(key, ""))
    except ValueError:
        raise ValueError(f"{key} must be an integer") from None


def _cols(q: dict[str, str]) -> list[periods.Col]:
    """Report columns: `cols=key:from:to,…` from the date filter, else one per month of from..to + Total."""
    if q.get("cols"):
        return periods.parse_cols(q["cols"])
    return periods.month_cols(*periods.parse_range(q.get("from"), q.get("to")))


class Unavailable(Exception):
    """→ 503 with the message."""


def _cached_snapshot() -> dict[str, Any]:
    """Chart + organization from the database; never calls Zoho."""
    if not db.enabled():
        raise Unavailable("MariaDB not configured (MIS_DB_* in .env)")
    snap = db.coa_snapshot()
    if not snap["accounts"]:
        raise Unavailable("No chart of accounts loaded yet: the seeder fills `accounts`.")
    return snap


def _live_args(q: dict[str, str]) -> tuple[list[periods.Col], dict[str, Any], dict[str, dict[str, str]]]:
    if not live.enabled():
        raise Unavailable("Live financials are switched off on this server (MIS_LIVE_FINANCIALS=1).")
    return _cols(q), _cached_snapshot(), cm.load_overrides(OVERRIDES_CSV)


class Handler(BaseHTTPRequestHandler):
    server_version = "NellonMIS/1.0"

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", web_auth.FRAME_ANCESTORS)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, data: Any) -> None:
        self._send(status, json.dumps(data).encode("utf-8"), "application/json; charset=utf-8")

    _claims: dict[str, Any] = {}

    def _read_json(self) -> dict[str, Any]:
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_BODY:
            raise ValueError("request too large")
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            raise ValueError("body must be JSON") from None
        if not isinstance(body, dict):
            raise ValueError("body must be a JSON object")
        return body

    def _authorized(self, path: str) -> bool:
        """Pages/assets only load inside the Zoho web-tab iframe; every /api route needs a Zoho JWT."""
        if not path.startswith("/api/"):
            if web_auth.explicitly_disabled() or web_auth.framed(self.headers.get("Sec-Fetch-Dest"),
                                                                  asset=path.startswith("/assets/")):
                return True
            print(f"auth: refusing direct access to {path} (Sec-Fetch-Dest={self.headers.get('Sec-Fetch-Dest')})")
            self._send(HTTPStatus.FORBIDDEN, b"<!doctype html><meta charset=utf-8><title>MIS Reports</title>"
                       b"<p>Open this report from the Zoho Books web tab.</p>", "text/html; charset=utf-8")
            return False
        key = web_auth.secret()
        if key is None:
            if web_auth.explicitly_disabled():
                return True
            print(f"auth: refusing {path} (MIS_JWT_SECRET not set)")
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "Server auth is not configured (MIS_JWT_SECRET)."})
            return False
        bearer = self.headers.get("Authorization", "")
        token = bearer[7:].strip() if bearer.lower().startswith("bearer ") else ""
        if token:
            try:
                self._claims = web_auth.verify_jwt(token, key)
                return True
            except ValueError as exc:
                print(f"auth rejected: {exc}")
        else:
            print(f"auth: no bearer token on {path}")
        self._json(HTTPStatus.UNAUTHORIZED, {"error": "Open this report from the Zoho Books web tab."})
        return False

    def do_GET(self) -> None:  # noqa: N802
        parts = urlsplit(self.path)
        path = parts.path
        q = {k: v[-1] for k, v in parse_qs(parts.query).items()}
        if not self._authorized(path):
            return
        if path in ("/", "/index.html", "/reports", "/reports.html"):
            self._send(HTTPStatus.OK, REPORTS_PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if path in ("/categories", "/category_master.html"):
            self._send(HTTPStatus.OK, WEB_PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if path in ("/cashflow", "/cashflow.html"):
            self._send(HTTPStatus.OK, CASHFLOW_PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if path in ("/sales-dashboard", "/sales_dashboard.html"):
            self._send(HTTPStatus.OK, DASHBOARD_PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if path.startswith("/api/sales-dashboard/"):  # JWT already verified above
            name = path[len("/api/sales-dashboard/"):]
            f = (DASHBOARD_DIR / name).resolve()
            if _DASHBOARD_FILE.match(name) and f.is_file() and DASHBOARD_DIR.resolve() in f.parents:
                ctype = {".html": "text/html", ".css": "text/css", ".js": "text/javascript"}[f.suffix]
                self._send(HTTPStatus.OK, f.read_bytes(), f"{ctype}; charset=utf-8")
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        if path.startswith("/assets/"):
            name = path[len("/assets/"):]
            asset = ASSETS_DIR / name
            if _ASSET_NAME.match(name) and asset.is_file():
                self._send(HTTPStatus.OK, asset.read_bytes(), ASSET_TYPES[asset.suffix])
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
            return
        try:
            if path == "/api/category-master":
                with _lock:
                    self._json(HTTPStatus.OK, _payload())
            elif path == "/api/cashflow":
                as_of = date.fromisoformat(q["as_of"]) if q.get("as_of") else date.today()
                payload = cf.load_offline(COA_SNAPSHOT, OUT_DIR / "cache", as_of)
                payload["currency"] = _org_currency(payload.get("currency", ""))
                payload.pop("organization", None)
                self._json(HTTPStatus.OK, payload)
            elif path == "/api/config":
                fy = db.enabled() and db.get_organization().get("fiscal_year_start_month")
                self._json(HTTPStatus.OK, {"live_financials": live.enabled(), "fiscal_year_start_month": fy or None})
            elif path == "/api/statement":
                cols, snapshot, overrides = _live_args(q)
                self._json(HTTPStatus.OK, live.statement(q.get("name", ""), cols, snapshot, overrides,
                                                         refresh=q.get("refresh") == "1"))
            elif path == "/api/tb":
                cols, snapshot, overrides = _live_args(q)
                self._json(HTTPStatus.OK, live.trial_balance(cols, snapshot, overrides, refresh=q.get("refresh") == "1"))
            elif path.startswith("/api/") and not db.enabled():
                self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "MariaDB not configured (MIS_DB_* in .env)"})
            elif path == "/api/org":
                self._json(HTTPStatus.OK, db.get_organization())
            elif path == "/api/export.xlsx":
                body, filename = build_live_workbook(*_live_args(q), refresh=q.get("refresh") == "1")
                self.send_response(HTTPStatus.OK)
                self.send_header(
                    "Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                )
                self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path == "/api/coverage":
                self._json(HTTPStatus.OK, db.get_coverage(q.get("dataset", "")))
            elif path == "/api/margin":
                self._json(HTTPStatus.OK, db.get_margin_pivot_range(
                    _cols(q), q.get("dim", "item"), q.get("measure", "net_sales")))
            elif path == "/api/margin-detail":
                start, end = periods.parse_range(q.get("from"), q.get("to"))
                self._json(HTTPStatus.OK, db.get_margin_detail_range(start, end, q.get("view", "line")))
            elif path == "/api/purchases":
                self._json(HTTPStatus.OK, db.get_purchase_pivot_range(
                    _cols(q), q.get("dim", "vendor"), q.get("measure", "amount")))
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except (Unavailable, live.Busy) as exc:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": str(exc)})
        except live.ZohoDown as exc:
            self._json(HTTPStatus.BAD_GATEWAY, {"error": str(exc)})
        except Exception as exc:  # Zoho / DB / IO failures surface in the page
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if not self._authorized(path):
            return
        try:
            with _lock:
                if path in ("/api/category-override", "/api/category-override/delete"):
                    user = str(self._claims.get("user_id", "unknown"))
                    self._json(HTTPStatus.OK, _save_override(self._read_json(), user,
                                                             delete=path.endswith("/delete")))
                else:
                    self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        except PermissionError as exc:
            self._json(HTTPStatus.FORBIDDEN, {"error": str(exc)})
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception as exc:
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} {fmt % args}")


def serve(host: str = "127.0.0.1", port: int = 8765) -> None:
    if not web_auth.enabled():
        print("WARNING: MIS_JWT_SECRET not set — " + (
            "MIS_AUTH_DISABLED=1, report viewer has NO authentication" if web_auth.explicitly_disabled()
            else "all /api routes will be refused"))
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"Report viewer          → http://{host}:{port}/")
    print(f"Cashflow seeker        → http://{host}:{port}/cashflow")
    print(f"Category Master editor → http://{host}:{port}/categories  (Ctrl+C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
