#!/usr/bin/env python3
"""MIS reports from Zoho Books.

Currently:
  trial-balance    — period TB from General Ledger + Chart of Accounts
  monthly-tb       — monthly TB: opening, one column per month, closing + categories
  financials       — Executive Summary + P&L + Balance Sheet workbook (from a saved TB or live)
  purchases        — bills + purchase orders by line (cached)
  margin           — revenue & margin by invoice line, with item/customer/salesperson/van rollups
  category-master  — ledger → PL/BS category mapping from Chart of Accounts
  org-sync         — store organization name/currency in MariaDB (1 Zoho call)
  db-init / db-load / db-runs — MariaDB storage of processed runs (see reports/db.py)
  webtab           — add the deployed report viewer as a Zoho Books web tab (idempotent)
  cashflow         — cash forecast from the local cache (no Zoho): bank, cash, bills, orders
  serve            — local web: Category Master editor (/) and report viewer (/reports)

Usage:
  .venv/bin/python main.py trial-balance --from-date 2026-04-01 --to-date 2026-10-11
  .venv/bin/python main.py trial-balance --from-date 2026-04-01 --to-date 2026-10-11 --include-zero
  .venv/bin/python main.py monthly-tb --from-date 2026-04-01 --to-date 2026-09-30
  .venv/bin/python main.py financials --tb-json output/monthly_tb_<...>.json   # offline
  .venv/bin/python main.py financials --from-date 2026-04-01 --to-date 2026-09-30
  .venv/bin/python main.py margin --from-date 2026-09-01 --to-date 2026-09-30
  .venv/bin/python main.py category-master
  .venv/bin/python main.py cashflow         # local files only; then open /cashflow
  .venv/bin/python main.py serve            # http://127.0.0.1:8765
"""

from __future__ import annotations

import argparse
import json
from datetime import date, datetime, timedelta
from pathlib import Path

from exporters import write_csv, write_excel_sheets, write_statement_workbook
from reports import category_master as cm
from reports.cashflow_forecast import balances as cashflow_balances
from reports.cashflow_forecast import load_offline as load_cashflow
from reports.financials import build_financials
from reports.financials import checks as financial_checks
from reports import db
from reports import invoice_margin as im
from reports import purchases as pu
from reports.monthly_trial_balance import generate_monthly_trial_balance
from reports.trial_balance import COLUMNS, generate_trial_balance
from zoho_client import ZohoClient

BASE_DIR = Path(__file__).resolve().parent
OUT_DIR = BASE_DIR / "output"
COA_SNAPSHOT = OUT_DIR / "coa_snapshot.json"
OVERRIDES_CSV = BASE_DIR / "category_overrides.csv"


def _cmd_trial_balance(args: argparse.Namespace) -> int:
    client = ZohoClient()
    rows, summary = generate_trial_balance(
        client,
        args.from_date,
        args.to_date,
        include_zero=args.include_zero,
    )

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"trial_balance_{args.from_date}_{args.to_date}_{stamp}"
    csv_path = OUT_DIR / f"{stem}.csv"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"

    write_csv(rows, COLUMNS, csv_path)
    summary_rows = [{"metric": k, "value": v} for k, v in summary.items()]
    write_excel_sheets(
        {
            "TrialBalance": (COLUMNS, rows),
            "Summary": (["metric", "value"], summary_rows),
        },
        xlsx_path,
    )
    json_path.write_text(
        json.dumps({"summary": summary, "rows": rows}, indent=2),
        encoding="utf-8",
    )

    print()
    print(f"Accounts:     {summary['account_count']}")
    print(f"Gross debit:  {summary['debit_total_sum']:,.2f}")
    print(f"Gross credit: {summary['credit_total_sum']:,.2f}")
    print(f"Net debit:    {summary['net_debit_sum']:,.2f}")
    print(f"Net credit:   {summary['net_credit_sum']:,.2f}")
    balanced = abs(summary["debit_total_sum"] - summary["credit_total_sum"]) < 0.015
    print(f"Gross balanced: {balanced}")
    print(f"CSV   -> {csv_path}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return 0


def refresh_coa_snapshot() -> dict:
    print("Fetching chart of accounts…")
    snapshot = cm.fetch_coa_snapshot(ZohoClient())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    COA_SNAPSHOT.write_text(json.dumps(snapshot, indent=1), encoding="utf-8")
    print(f"  accounts: {len(snapshot['accounts'])} ({snapshot['organization_name']})")
    return snapshot


def load_coa_snapshot(*, refresh: bool = False) -> dict:
    if refresh or not COA_SNAPSHOT.exists():
        return refresh_coa_snapshot()
    return json.loads(COA_SNAPSHOT.read_text(encoding="utf-8"))


def _cmd_category_master(args: argparse.Namespace) -> int:
    snapshot = load_coa_snapshot(refresh=not args.cached)
    rows = cm.build_category_master(snapshot, cm.load_overrides(OVERRIDES_CSV))
    summary = cm.category_master_summary(rows)

    stem = "category_master"
    csv_path = OUT_DIR / f"{stem}.csv"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"
    write_csv(rows, cm.COLUMNS, csv_path)
    write_excel_sheets({"Category Master": (cm.COLUMNS, rows)}, xlsx_path)
    if db.enabled() and not args.no_db:
        print(f"MariaDB: category_master upserted ({db.save_category_master(rows)} accounts)")
    json_path.write_text(json.dumps({"summary": summary, "rows": rows}, indent=1), encoding="utf-8")

    print()
    print(f"Accounts: {summary['account_count']} ({summary['ledger_count']} ledgers, {summary['group_count']} groups)")
    for source, n in sorted(summary["by_source"].items()):
        print(f"  {source:9} {n}")
    print(f"CSV   -> {csv_path}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return 0


def _build_monthly_tb(args: argparse.Namespace) -> tuple[list[dict], list[str], dict]:
    from_date = date.fromisoformat(args.from_date)
    to_date = date.fromisoformat(args.to_date)
    client = ZohoClient()
    snapshot = load_coa_snapshot(refresh=not args.cached_coa)
    fy_month = args.fy_start_month or snapshot.get("fiscal_year_start_month")
    if not fy_month:
        raise SystemExit("Fiscal year start month unknown — pass --fy-start-month (1-12)")
    return generate_monthly_trial_balance(
        client,
        snapshot,
        cm.load_overrides(OVERRIDES_CSV),
        from_date,
        to_date,
        fy_start_month=int(fy_month),
        include_zero=args.include_zero,
    )


def _save_monthly_tb(rows: list[dict], columns: list[str], summary: dict) -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"monthly_tb_{summary['from_date']}_{summary['to_date']}_{stamp}"
    csv_path = OUT_DIR / f"{stem}.csv"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"
    write_csv(rows, columns, csv_path)
    summary_rows = [{"metric": k, "value": json.dumps(v) if isinstance(v, (dict, list)) else v}
                    for k, v in summary.items()]
    write_excel_sheets(
        {"MonthlyTB": (columns, rows), "Summary": (["metric", "value"], summary_rows)},
        xlsx_path,
    )
    json_path.write_text(
        json.dumps({"summary": summary, "columns": columns, "rows": rows}, indent=1), encoding="utf-8"
    )

    print()
    print(f"Accounts:       {summary['account_count']}  (FY starts {summary['fiscal_year_start']})")
    print(f"Opening net:    {summary['opening_net']:,.2f}   (should be 0.00)")
    for month, net in summary["months_net"].items():
        print(f"  {month} net:  {net:,.2f}")
    print(f"Closing Dr/Cr:  {summary['closing_debit']:,.2f} / {summary['closing_credit']:,.2f}")
    print(f"Uncategorised:  {summary['uncategorised']}   Needs review: {summary['needs_review']}")
    print(f"CSV   -> {csv_path}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return json_path


def _tb_balanced(summary: dict) -> bool:
    return abs(summary["closing_net"]) < 0.015 and abs(summary["opening_net"]) < 0.015


def _cmd_monthly_tb(args: argparse.Namespace) -> int:
    rows, columns, summary = _build_monthly_tb(args)
    _save_monthly_tb(rows, columns, summary)
    return 0 if _tb_balanced(summary) else 1


def _cmd_financials(args: argparse.Namespace) -> int:
    if args.tb_json:
        data = json.loads(Path(args.tb_json).read_text(encoding="utf-8"))
        rows, summary = data["rows"], data["summary"]
        columns = data.get("columns") or list(rows[0].keys() if rows else [])
        print(f"Using saved trial balance {args.tb_json} (no Zoho calls)")
    else:
        if not args.from_date:
            raise SystemExit("Pass --tb-json <saved monthly_tb_*.json> or --from-date")
        rows, columns, summary = _build_monthly_tb(args)
        _save_monthly_tb(rows, columns, summary)

    statements = build_financials(rows, summary)
    data_sheets = {"MonthlyTB": (columns, rows)}
    if COA_SNAPSHOT.exists():
        snapshot = json.loads(COA_SNAPSHOT.read_text(encoding="utf-8"))
        cat_rows = cm.build_category_master(snapshot, cm.load_overrides(OVERRIDES_CSV))
        data_sheets["Category Master"] = (cm.COLUMNS, cat_rows)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"mis_{summary['from_date']}_{summary['to_date']}_{stamp}"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"
    write_statement_workbook(statements, xlsx_path, data_sheets)
    json_path.write_text(
        json.dumps(
            {
                "summary": summary,
                "statements": [
                    {"name": st.name, "title": st.title, "subtitle": st.subtitle,
                     "columns": st.columns, "rows": st.rows()}
                    for st in statements
                ],
            },
            indent=1,
        ),
        encoding="utf-8",
    )

    _db_save(args, lambda src: db.save_financials_run(rows, summary, statements, source=src),
             args.tb_json or "zoho")

    results = financial_checks(statements)
    print()
    for name, diff in results.items():
        print(f"{name:4} check: {'OK' if diff < 0.015 else f'OFF by {diff:,.2f}'}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return 0 if all(d < 0.015 for d in results.values()) and _tb_balanced(summary) else 1


def _cmd_margin(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache_dir) if args.cache_dir else OUT_DIR / "cache"
    source = im.MarginSource(cache_dir, None if args.offline else ZohoClient())
    rows, invoice_rows, summaries, summary = im.generate_invoice_margin(source, args.from_date, args.to_date)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"margin_{args.from_date}_{args.to_date}_{stamp}"
    csv_path = OUT_DIR / f"{stem}.csv"
    xlsx_path = OUT_DIR / f"{stem}.xlsx"
    json_path = OUT_DIR / f"{stem}.json"
    write_csv(rows, im.COLUMNS, csv_path)
    sheets = {"Invoices": (im.INVOICE_COLUMNS, invoice_rows), "Lines": (im.COLUMNS, rows)}
    sheets.update({name: (im.SUMMARY_COLUMNS, data) for name, data in summaries.items()})
    write_excel_sheets(sheets, xlsx_path)
    json_path.write_text(
        json.dumps({"summary": summary, "summaries": summaries, "invoices": invoice_rows, "rows": rows}, indent=1), encoding="utf-8"
    )

    print()
    print(f"Invoices: {summary['invoices']}   Lines: {summary['lines']}   Zoho calls: {summary['api_calls']}")
    print(f"Net sales:    {summary['net_sales']:,.2f}")
    print(f"Cost:         {summary['cost']:,.2f}   ({summary['cost_basis']})")
    print(f"Gross margin: {summary['gross_margin']:,.2f}  ({summary['gross_margin_pct']:.1%})")
    print(f"Flagged lines: {summary['flagged_lines']}  (see 'flag' column)")
    _db_save(args, lambda src: db.save_margin_run(rows, summary, source=src, invoices=invoice_rows),
             "cache" if args.offline else "zoho")
    print(f"CSV   -> {csv_path}")
    print(f"Excel -> {xlsx_path}")
    print(f"JSON  -> {json_path}")
    return 0


def _cmd_purchases(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache_dir) if args.cache_dir else OUT_DIR / "cache"
    source = pu.PurchaseSource(cache_dir, None if args.offline else ZohoClient())
    source._throttle.min_interval = max(args.delay, 0.7)  # seconds between Zoho calls
    kinds = [args.kind] if args.kind else None
    rows, summaries, summary = pu.generate_purchases(source, args.from_date, args.to_date, kinds)

    stem = f"purchases_{args.from_date}_{args.to_date}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    write_csv(rows, pu.COLUMNS, OUT_DIR / f"{stem}.csv")
    sheets = {"Lines": (pu.COLUMNS, rows)}
    sheets.update({name: (pu.SUMMARY_COLUMNS, data) for name, data in summaries.items()})
    write_excel_sheets(sheets, OUT_DIR / f"{stem}.xlsx")
    (OUT_DIR / f"{stem}.json").write_text(
        json.dumps({"summary": summary, "summaries": summaries, "rows": rows}, indent=1), encoding="utf-8"
    )
    print(f"Documents: {summary['documents']}   Lines: {summary['lines']}   Zoho calls: {summary['api_calls']}")
    print(f"Amount by kind: {summary['amount_by_kind']}")
    _db_save(args, lambda src: db.save_purchases_run(rows, summary, source=src),
             "cache" if args.offline else "zoho")
    print(f"Excel -> {OUT_DIR / (stem + '.xlsx')}")
    return 0


def _db_save(args: argparse.Namespace, save, source: str) -> None:
    if getattr(args, "no_db", False):
        return
    if not db.enabled():
        print("MariaDB: not configured (MIS_DB_* in .env) — skipped")
        return
    run_id = save(source)
    print(f"MariaDB: saved as run #{run_id}  → view at /reports?run={run_id}")


def _cmd_db_init(args: argparse.Namespace) -> int:
    print(f"MariaDB: database `{db.init_schema()}` and tables ready")
    return 0


def _cmd_org_sync(args: argparse.Namespace) -> int:
    """One Zoho call (GET /organizations): store name, currency etc. in MariaDB for the web UI."""
    if not db.enabled():
        raise SystemExit("MariaDB not configured (MIS_DB_* in .env)")
    db.init_schema()
    org = cm.fetch_organization(ZohoClient())
    db.save_organization(org)
    print(f"Organization saved: {org.get('name')} · {org.get('currency_code')} ({org.get('currency_symbol')})")
    return 0


def _cmd_db_load(args: argparse.Namespace) -> int:
    """Import saved JSON outputs into MariaDB — no Zoho calls."""
    if args.tb_json:
        data = json.loads(Path(args.tb_json).read_text(encoding="utf-8"))
        rows, summary = data["rows"], data["summary"]
        statements = build_financials(rows, summary)
        run_id = db.save_financials_run(rows, summary, statements, source=args.tb_json)
        print(f"Financials run #{run_id}: {len(rows)} TB accounts, {summary['from_date']} → {summary['to_date']}")
    if args.margin_json:
        data = json.loads(Path(args.margin_json).read_text(encoding="utf-8"))
        run_id = db.save_margin_run(data["rows"], data["summary"], source=args.margin_json,
                                    invoices=data.get("invoices"))
        print(f"Margin run #{run_id}: {len(data['rows'])} invoice lines")
    if args.purchases_json:
        data = json.loads(Path(args.purchases_json).read_text(encoding="utf-8"))
        run_id = db.save_purchases_run(data["rows"], data["summary"], source=args.purchases_json)
        print(f"Purchases run #{run_id}: {len(data['rows'])} lines")
    if args.category_json:
        data = json.loads(Path(args.category_json).read_text(encoding="utf-8"))
        print(f"category_master upserted: {db.save_category_master(data['rows'])} accounts")
    if not (args.tb_json or args.margin_json or args.purchases_json or args.category_json):
        raise SystemExit("Pass --tb-json, --margin-json, --purchases-json and/or --category-json")
    return 0


def _cmd_db_runs(args: argparse.Namespace) -> int:
    if args.delete:
        print(f"Run #{args.delete} {'deleted' if db.delete_run(args.delete) else 'not found'}")
        return 0
    for r in db.list_runs(args.kind):
        print(f"#{r['id']:<5} {r['kind']:10} {r['from_date']} → {r['to_date']}  "
              f"{len(r['months'])} months  {r['created_at']}  {r['source']}")
    return 0


WEBTAB_NAME = "MIS Reports"
WEBTAB_URL = "https://algoray.tech/koyson-zoho/acc-reports/"


def _cmd_webtab(args: argparse.Namespace) -> int:
    """Create the Zoho Books web tab (POST /settings/tabs), or update its sharing if it exists.

    --share-with EMAIL limits the tab to that one Zoho Books user (shared_mode=selected).
    With neither --share-with nor --shared-mode, an existing tab's sharing is left untouched.
    """
    client = ZohoClient()
    payload: dict = {"name": args.name, "url": args.url, "shared_mode": args.shared_mode or "all",
                     "portal_webtab": False, "is_zoho_url": False}
    sharing_requested = bool(args.share_with or args.shared_mode)
    if args.share_with:
        users = client.get("/users", {"per_page": 200}).get("users") or []
        user = next((u for u in users if str(u.get("email", "")).lower() == args.share_with.lower()), None)
        if not user:
            raise SystemExit(f"No Zoho Books user with email {args.share_with}")
        payload["shared_mode"] = "selected"
        payload["shared_to"] = [{"shared_type": "user", "shared_id": str(user["user_id"]), "permission": "read"}]
        print(f"Sharing only with {user.get('name')} <{user.get('email')}> (user_id {user['user_id']})")

    listed = client.get("/settings/tabs")
    # Live API returns "tabs"/"tab_id"; the published docs say "web_tabs"/"webtab_id". Accept both.
    tabs = listed.get("tabs") or listed.get("web_tabs") or []
    existing = next((t for t in tabs if str(t.get("name", "")).strip().lower() == args.name.lower()), None)
    if existing:
        tab_id = existing.get("tab_id") or existing.get("webtab_id")
        if not sharing_requested and existing.get("url") == args.url:
            print(f"Web tab '{existing.get('name')}' exists (id {tab_id}) -> {existing.get('url')}, "
                  f"shared_mode={existing.get('shared_mode')}. No changes.")
            return 0
        if not sharing_requested:
            payload["shared_mode"] = existing.get("shared_mode") or "all"
            if existing.get("shared_mode") == "selected":
                detail = client.get(f"/settings/tabs/{tab_id}")
                current = (detail.get("tab") or detail.get("web_tab") or {}).get("shared_to") or []
                payload["shared_to"] = [{"shared_type": x.get("shared_type"), "shared_id": x.get("shared_id"),
                                         "permission": x.get("permission")} for x in current]
        body = client.put(f"/settings/tabs/{tab_id}", payload)
        print(f"{body.get('message', 'Updated')} id={tab_id} shared_mode={payload['shared_mode']}")
        return 0
    body = client.post("/settings/tabs", payload)
    tab = body.get("tab") or body.get("web_tab") or {}
    tab_id = tab.get("tab_id") or tab.get("webtab_id") or "(see Zoho Books > Settings > Web Tabs)"
    print(f"{body.get('message', 'Created')} id={tab_id} shared_mode={payload['shared_mode']}")
    return 0


def _cmd_cashflow(args: argparse.Namespace) -> int:
    """Write the forecast. --from-zoho calls Zoho and stores the run in MariaDB."""
    as_of = date.fromisoformat(args.as_of) if args.as_of else date.today()
    end = date.fromisoformat(args.to_date) if args.to_date else as_of + timedelta(days=args.days)
    if end < as_of:
        raise SystemExit("--to-date is before --as-of")
    org_id = ""
    api_calls = 0
    if args.from_zoho:
        from reports.cashflow_load import load_from_zoho

        payload, org_id, api_calls = load_from_zoho(ZohoClient(), OUT_DIR / "cache", as_of)
        db.init_schema()
        run_id = db.save_cashflow_run(
            payload,
            organization_id=org_id,
            api_calls=api_calls,
            source="GET /chartofaccounts + unpaid invoices/bills + open purchase orders and sales orders",
        )
        print(f"MariaDB: cashflow run #{run_id}  ({api_calls} API calls)")
        published = Path("/var/www/html/algo_cloud/koyson-zoho/cashflow/forecast/forecast.json")
        if published.parent.is_dir():
            published.write_text(json.dumps(payload, indent=1), encoding="utf-8")
            print(f"Page  -> {published}")
    else:
        payload = load_cashflow(COA_SNAPSHOT, OUT_DIR / "cache", as_of)
    rows = cashflow_balances(payload["opening"], payload["events"], as_of, end)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = OUT_DIR / f"cashflow_{as_of.isoformat()}_{end.isoformat()}_{stamp}.json"
    json_path.write_text(json.dumps({"horizon_end": end.isoformat(), "days": rows, **payload}, indent=1), encoding="utf-8")
    counts = payload["counts"]
    print(f"Opening cash:  {payload['opening']:,.2f} {payload['currency']}")
    print(f"Events:        AR {counts['ar']}  AP {counts['ap']}  PO {counts['po']}  SO {counts['so']}")
    print(f"Unscheduled:   {len(payload['unscheduled'])}")
    print(f"Balance {rows[0]['date']}: {rows[0]['balance']:,.2f}")
    print(f"Balance {rows[-1]['date']}: {rows[-1]['balance']:,.2f}")
    print(f"JSON  -> {json_path}")
    print("Seeker -> .venv/bin/python main.py serve   then  /cashflow")
    return 0


def _cmd_serve(args: argparse.Namespace) -> int:
    from server import serve

    serve(args.host, args.port)
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Nellon MIS reports from Zoho Books")
    sub = p.add_subparsers(dest="command", required=True)

    tb = sub.add_parser(
        "trial-balance",
        help="Trial balance from /reports/generalledger + /chartofaccounts",
    )
    tb.add_argument("--from-date", required=True, help="YYYY-MM-DD")
    tb.add_argument("--to-date", default=date.today().isoformat(), help="YYYY-MM-DD (default: today)")
    tb.add_argument(
        "--include-zero",
        action="store_true",
        help="Keep accounts with zero debit, credit, and balance",
    )
    tb.set_defaults(func=_cmd_trial_balance)

    def add_tb_args(sp: argparse.ArgumentParser, *, from_required: bool) -> None:
        sp.add_argument("--from-date", required=from_required, help="YYYY-MM-DD")
        sp.add_argument("--to-date", default=date.today().isoformat(), help="YYYY-MM-DD (default: today)")
        sp.add_argument("--fy-start-month", type=int, choices=range(1, 13), metavar="1-12",
                        help="Fiscal year start month (default: from Zoho organization)")
        sp.add_argument("--include-zero", action="store_true",
                        help="Keep accounts with no balance or movement")
        sp.add_argument("--cached-coa", action="store_true", help="Reuse output/coa_snapshot.json")

    mtb = sub.add_parser(
        "monthly-tb",
        help="Monthly TB (opening, per-month movement, closing) with Category Master columns",
    )
    add_tb_args(mtb, from_required=True)
    mtb.set_defaults(func=_cmd_monthly_tb)

    fin = sub.add_parser(
        "financials",
        help="Executive Summary + P&L + Balance Sheet workbook",
    )
    fin.add_argument("--tb-json", help="Build offline from a saved output/monthly_tb_*.json")
    add_tb_args(fin, from_required=False)
    fin.add_argument("--no-db", action="store_true", help="Don't save the run to MariaDB")
    fin.set_defaults(func=_cmd_financials)

    mg = sub.add_parser("margin", help="Revenue and margin by invoice line (item purchase rate as cost)")
    mg.add_argument("--from-date", required=True, help="YYYY-MM-DD")
    mg.add_argument("--to-date", default=date.today().isoformat(), help="YYYY-MM-DD (default: today)")
    mg.add_argument("--offline", action="store_true", help="Use cached invoices/items only (no Zoho calls)")
    mg.add_argument("--cache-dir", help="Invoice/item cache directory (default: output/cache)")
    mg.add_argument("--no-db", action="store_true", help="Don't save the run to MariaDB")
    mg.set_defaults(func=_cmd_margin)

    pc = sub.add_parser("purchases", help="Purchases by line from Zoho bills and purchase orders")
    pc.add_argument("--from-date", required=True, help="YYYY-MM-DD")
    pc.add_argument("--to-date", default=date.today().isoformat(), help="YYYY-MM-DD (default: today)")
    pc.add_argument("--kind", choices=list(pu.KINDS), help="Only bills or only purchase orders (default: both)")
    pc.add_argument("--delay", type=float, default=2.0, help="Seconds between Zoho calls (default 2, minimum 0.7)")
    pc.add_argument("--offline", action="store_true", help="Use cached documents only (no Zoho calls)")
    pc.add_argument("--cache-dir", help="Cache directory (default: output/cache)")
    pc.add_argument("--no-db", action="store_true", help="Don't save the run to MariaDB")
    pc.set_defaults(func=_cmd_purchases)

    cmp = sub.add_parser(
        "category-master",
        help="Ledger → PL/BS category mapping from /chartofaccounts + category_overrides.csv",
    )
    cmp.add_argument(
        "--cached",
        action="store_true",
        help="Reuse output/coa_snapshot.json instead of calling Zoho",
    )
    cmp.add_argument("--no-db", action="store_true", help="Don't upsert into MariaDB")
    cmp.set_defaults(func=_cmd_category_master)

    wt = sub.add_parser("webtab", help="Add the report viewer as a Zoho Books web tab (updates it if it exists)")
    wt.add_argument("--name", default=WEBTAB_NAME)
    wt.add_argument("--url", default=WEBTAB_URL)
    wt.add_argument("--shared-mode", choices=["all", "onlyme", "selected"],
                    help="Change sharing (default for a new tab: all; an existing tab keeps its sharing)")
    wt.add_argument("--share-with", metavar="EMAIL", help="Share only with this Zoho Books user")
    wt.set_defaults(func=_cmd_webtab)

    dbi = sub.add_parser("db-init", help="Create the MariaDB database and tables (idempotent)")
    dbi.set_defaults(func=_cmd_db_init)

    osy = sub.add_parser("org-sync", help="Fetch the organization (name, currency…) from Zoho into MariaDB (1 call)")
    osy.set_defaults(func=_cmd_org_sync)

    dbl = sub.add_parser("db-load", help="Import saved JSON outputs into MariaDB (no Zoho calls)")
    dbl.add_argument("--tb-json", help="output/monthly_tb_*.json → financials run (TB + statements)")
    dbl.add_argument("--margin-json", help="output/margin_*.json → margin run")
    dbl.add_argument("--purchases-json", help="output/purchases_*.json → purchases run")
    dbl.add_argument("--category-json", help="output/category_master.json → category_master table")
    dbl.set_defaults(func=_cmd_db_load)

    dbr = sub.add_parser("db-runs", help="List stored runs (or delete one)")
    dbr.add_argument("--kind", choices=["financials", "margin", "purchases"])
    dbr.add_argument("--delete", type=int, metavar="RUN_ID", help="Delete a run and its data")
    dbr.set_defaults(func=_cmd_db_runs)

    cf = sub.add_parser(
        "cashflow",
        help="Cash forecast from the local cache and COA snapshot (no Zoho calls)",
    )
    cf.add_argument("--as-of", help="YYYY-MM-DD (default: today)")
    cf.add_argument("--to-date", help="Last day on the timeline (default: --days after --as-of)")
    cf.add_argument("--days", type=int, default=90, help="Horizon in calendar days when --to-date is omitted")
    cf.add_argument("--from-zoho", action="store_true",
                    help="Call Zoho, build the forecast, and insert it into MariaDB")
    cf.set_defaults(func=_cmd_cashflow)

    sv = sub.add_parser("serve", help="Local web editor for Category Master overrides")
    sv.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    sv.add_argument("--port", type=int, default=8765)
    sv.set_defaults(func=_cmd_serve)
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
