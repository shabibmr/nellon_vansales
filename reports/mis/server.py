"""Local web editor for the Category Master (stdlib only).

    GET  / or /reports           → web/reports.html (report viewer; reads MariaDB only)
    GET  /categories             → web/category_master.html (Category Master editor)

All page/asset/API URLs in the web files are relative, so the app also works
behind a reverse proxy under a sub-path (e.g. /koyson-zoho/acc-reports/).
    GET  /assets/<name>.css|.js|.svg → web/assets/ (shared styles, page scripts, icon sprite)
    GET  /api/runs?kind=         → stored runs
    GET  /api/statement?run_id=&name=   Executive Summary | PL | BS
    GET  /api/tb?run_id=         → monthly trial balance
    GET  /api/margin?run_id=&dim=&measure=   margin pivot by month
    GET  /api/purchases?run_id=&dim=&measure=   bills + purchase orders pivot by month
    GET  /api/export.xlsx?run_id=        → Excel workbook (Exec Summary, PL, BS, Trial Balance)
    GET  /api/category-master    → rows built from the cached COA snapshot + overrides
    POST /api/refresh            → re-pull Chart of Accounts from Zoho; returns rebuilt payload

The Category Master is read-only over HTTP (it is publicly deployed): mappings are
changed by editing category_overrides.csv and re-running `main.py category-master`.

Zoho credentials stay server-side. Binds to 127.0.0.1 by default — there is no
auth, so don't expose it on a public interface.
"""

from __future__ import annotations

import json
import re
import threading
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlsplit

from exporters import write_csv, write_excel_sheets
from main import BASE_DIR, COA_SNAPSHOT, OUT_DIR, OVERRIDES_CSV, load_coa_snapshot
from reports import category_master as cm
from reports import db
from reports.excel_export import build_workbook

WEB_PAGE = BASE_DIR / "web" / "category_master.html"
REPORTS_PAGE = BASE_DIR / "web" / "reports.html"
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


def _payload(*, refresh: bool = False) -> dict[str, Any]:
    snapshot = load_coa_snapshot(refresh=refresh)
    rows = cm.build_category_master(snapshot, cm.load_overrides(OVERRIDES_CSV))
    summary = cm.category_master_summary(rows)
    _export(rows, summary)
    return {
        "organization_name": snapshot.get("organization_name", ""),
        "currency_code": snapshot.get("currency_code", ""),
        "snapshot_time": datetime.fromtimestamp(COA_SNAPSHOT.stat().st_mtime).isoformat(timespec="seconds"),
        "categories": cm.CATEGORIES,
        "summary": summary,
        "rows": rows,
    }


def _int(q: dict[str, str], key: str) -> int:
    try:
        return int(q.get(key, ""))
    except ValueError:
        raise ValueError(f"{key} must be an integer") from None


class Handler(BaseHTTPRequestHandler):
    server_version = "NellonMIS/1.0"

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, data: Any) -> None:
        self._send(status, json.dumps(data).encode("utf-8"), "application/json; charset=utf-8")

    def do_GET(self) -> None:  # noqa: N802
        parts = urlsplit(self.path)
        path = parts.path
        q = {k: v[-1] for k, v in parse_qs(parts.query).items()}
        if path in ("/", "/index.html", "/reports", "/reports.html"):
            self._send(HTTPStatus.OK, REPORTS_PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if path in ("/categories", "/category_master.html"):
            self._send(HTTPStatus.OK, WEB_PAGE.read_bytes(), "text/html; charset=utf-8")
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
            elif path.startswith("/api/") and not db.enabled():
                self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "MariaDB not configured (MIS_DB_* in .env)"})
            elif path == "/api/runs":
                kind = q.get("kind") or None
                if kind not in (None, "financials", "margin", "purchases"):
                    raise ValueError("kind must be financials, margin or purchases")
                self._json(HTTPStatus.OK, {"runs": db.list_runs(kind)})
            elif path == "/api/run":
                run = db.get_run(_int(q, "run_id"))
                self._json(HTTPStatus.OK if run else HTTPStatus.NOT_FOUND, run or {"error": "run not found"})
            elif path == "/api/statement":
                name = q.get("name", "")
                if name not in STATEMENTS:
                    raise ValueError(f"name must be one of {sorted(STATEMENTS)}")
                self._json(HTTPStatus.OK, db.get_statement(_int(q, "run_id"), name))
            elif path == "/api/tb":
                self._json(HTTPStatus.OK, db.get_trial_balance(_int(q, "run_id")))
            elif path == "/api/export.xlsx":
                body, filename = build_workbook(_int(q, "run_id"))
                self.send_response(HTTPStatus.OK)
                self.send_header(
                    "Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                )
                self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path == "/api/margin":
                self._json(
                    HTTPStatus.OK,
                    db.get_margin_pivot(_int(q, "run_id"), q.get("dim", "item"), q.get("measure", "net_sales")),
                )
            elif path == "/api/purchases":
                self._json(
                    HTTPStatus.OK,
                    db.get_purchase_pivot(_int(q, "run_id"), q.get("dim", "vendor"), q.get("measure", "amount")),
                )
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception as exc:  # Zoho / DB / IO failures surface in the page
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        try:
            with _lock:
                if path == "/api/refresh":
                    self._json(HTTPStatus.OK, _payload(refresh=True))
                else:
                    self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
        except ValueError as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        except Exception as exc:
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"{self.address_string()} {fmt % args}")


def serve(host: str = "127.0.0.1", port: int = 8765) -> None:
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"Report viewer          → http://{host}:{port}/")
    print(f"Category Master editor → http://{host}:{port}/categories  (Ctrl+C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
