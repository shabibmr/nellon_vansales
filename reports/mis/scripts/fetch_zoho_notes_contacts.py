"""Fetch credit notes, debit notes and contacts from Zoho Books into output/cache/.

Writes only local cache files. seed_notes_contacts_from_cache.py loads them into MariaDB.

    output/cache/contacts/customers.json   {"contacts": [...]}   all customers
    output/cache/contacts/vendors.json     {"contacts": [...]}   all vendors
    output/cache/creditnotes/{id}.json     GET /creditnotes/{id}  (header + line_items)
    output/cache/debitnotes/{id}.json      GET /invoices/{id}     (a debit note is an invoice)

Usage (from reports/mis):
    python -m scripts.fetch_zoho_notes_contacts --from 2026-09-01 --to 2026-09-30            # plan only, NO network
    python -m scripts.fetch_zoho_notes_contacts --from 2026-09-01 --to 2026-09-30 --yes-live # calls Zoho

Without --yes-live nothing touches the network. Zoho rate-limits OAuth and API calls, so
the run stops at --max-calls, reuses cached detail files, and sleeps between calls.
Credit-note list: only an exact `date` filter is documented, so all list pages are read
(200 per page) and filtered by date here.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import date
from pathlib import Path

from common.seed_common import BASE_DIR, parse_date

CACHE = BASE_DIR / "output" / "cache"
PER_PAGE = 200
MAX_LIST_PAGES = 50


class CallBudget:
    def __init__(self, limit: int, pause: float) -> None:
        self.limit, self.pause, self.used = limit, pause, 0

    def get(self, client, endpoint: str, params: dict | None = None) -> dict:
        if self.used >= self.limit:
            raise SystemExit(f"Stopped: reached --max-calls={self.limit} (cache files already written are kept).")
        self.used += 1
        if self.used > 1:
            time.sleep(self.pause)
        return client.get(endpoint, params)


def write_json(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def list_pages(budget: CallBudget, client, endpoint: str, key: str, params: dict) -> list[dict]:
    rows: list[dict] = []
    for page in range(1, MAX_LIST_PAGES + 1):
        body = budget.get(client, endpoint, {**params, "page": page, "per_page": PER_PAGE})
        rows.extend(body.get(key) or [])
        if not (body.get("page_context") or {}).get("has_more_page"):
            return rows
    raise SystemExit(f"{endpoint}: more than {MAX_LIST_PAGES} pages; refusing to continue.")


def fetch_details(budget, client, ids: list[str], folder: Path, endpoint: str, refresh: bool) -> int:
    got = 0
    for doc_id in ids:
        target = folder / f"{doc_id}.json"
        if target.exists() and not refresh:
            continue
        write_json(target, budget.get(client, f"{endpoint}/{doc_id}"))
        got += 1
    return got


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--from", dest="dfrom", required=True)
    ap.add_argument("--to", dest="dto", required=True)
    ap.add_argument("--what", nargs="+", choices=["contacts", "creditnotes", "debitnotes"],
                    default=["contacts", "creditnotes", "debitnotes"])
    ap.add_argument("--yes-live", action="store_true", help="actually call Zoho (default: print the plan only)")
    ap.add_argument("--max-calls", type=int, default=400)
    ap.add_argument("--sleep", type=float, default=0.5, help="seconds between calls")
    ap.add_argument("--refresh", action="store_true", help="re-fetch detail files already cached")
    ap.add_argument("--no-details", action="store_true",
                    help="list calls only: save _list.json for notes, skip the per-note detail calls")
    args = ap.parse_args()
    dfrom, dto = parse_date(args.dfrom), parse_date(args.dto)
    if not dfrom or not dto or dfrom > dto:
        ap.error("--from / --to must be YYYY-MM-DD with from <= to")

    print(f"Window {dfrom}..{dto}; fetching: {', '.join(args.what)}; max {args.max_calls} calls")
    if args.no_details:
        print("Detail calls per credit/debit note are SKIPPED (--no-details).")
    print("Plan:")
    if "contacts" in args.what:
        print("  GET /contacts?contact_type=customer  (pages of 200), then contact_type=vendor")
    if "creditnotes" in args.what:
        print("  GET /creditnotes (all pages, date-filtered here), then GET /creditnotes/{id} per note in window")
    if "debitnotes" in args.what:
        print(f"  GET /invoices?filter_by=Type.DebitNote&date_start&date_end, then GET /invoices/{{id}} per note")
    if not args.yes_live:
        print("\n[PLAN ONLY] No Zoho call was made. Add --yes-live to run.")
        return 0

    from common.zoho_client import ZohoClient  # imported late so a plan run never needs credentials

    client = ZohoClient()
    budget = CallBudget(args.max_calls, args.sleep)

    if "contacts" in args.what:
        for ctype, name in (("customer", "customers"), ("vendor", "vendors")):
            rows = list_pages(budget, client, "/contacts", "contacts", {"contact_type": ctype})
            write_json(CACHE / "contacts" / f"{name}.json", {"contacts": rows})
            print(f"  {name}: {len(rows)} contacts")

    if "creditnotes" in args.what:
        rows = list_pages(budget, client, "/creditnotes", "creditnotes", {"sort_column": "date"})
        in_window = lambda r: (parse_date(r.get("date")) or date.min) >= dfrom and (parse_date(r.get("date")) or date.max) <= dto
        ids = [r["creditnote_id"] for r in rows if in_window(r)]
        print(f"  creditnotes: {len(rows)} listed, {len(ids)} in window")
        write_json(CACHE / "creditnotes" / "_list.json", {"creditnotes": rows})
        if not args.no_details:
            print(f"  creditnote details fetched: {fetch_details(budget, client, ids, CACHE / 'creditnotes', '/creditnotes', args.refresh)}")

    if "debitnotes" in args.what:
        rows = list_pages(
            budget, client, "/invoices", "invoices",
            {"filter_by": "Type.DebitNote", "date_start": str(dfrom), "date_end": str(dto), "sort_column": "date"},
        )
        ids = [r["invoice_id"] for r in rows]
        print(f"  debitnotes: {len(ids)} in window")
        write_json(CACHE / "debitnotes" / "_list.json", {"invoices": rows})
        if not args.no_details:
            print(f"  debitnote details fetched: {fetch_details(budget, client, ids, CACHE / 'debitnotes', '/invoices', args.refresh)}")

    print(f"Done. Zoho calls used: {budget.used}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
