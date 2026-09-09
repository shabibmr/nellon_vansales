"""
Journal-credit aged-balance transfer -- single-invoice live test (KGT-IN-001691).

Flow:
  1. POST /journals                          -> create DRAFT manual journal
        Cr  Accounts Receivable (contact = customer)   524.42
        Dr  SHAMEER OLD BALANCE (other_current_asset)  524.42
  2. POST /journals/{id}/status/publish      -> publish it (creates the customer credit)
  3. GET  /journals/{id}                     -> dump resulting structure
  4. GET  /journals/{id}/credits            -> confirm available receivables credit
  5. POST /journals/{id}/credits/{journal_line_id}/invoices
        {"invoices":[{"invoice_id","amount_applied"}]}   -> apply credit to the invoice
        (journal_line_id = the AR credit line's line_id)
  6. GET /invoices/{inv} -> confirm balance went 524.42 -> 0

Usage:
  python jc_transfer_test.py --dry-run             # print payloads only
  python jc_transfer_test.py --run                # create journal + publish + apply
  python jc_transfer_test.py --apply <journal_id>  # apply step only, for an existing journal
  python jc_transfer_test.py --undo <journal_id>   # unapply + delete the journal
"""
import argparse, json, os, sys, time
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env_zoho"))

CID = os.environ["ZOHO_CLIENT_ID"]
CSEC = os.environ["ZOHO_CLIENT_SECRET"]
RTOK = os.environ["ZOHO_REFRESH_TOKEN"]
ORG = os.environ["ZOHO_ORG_ID"]
BASE = "https://www.zohoapis.com/books/v3"

# --- fixed facts for this invoice (verified via jc_probe.py) --------------------
INV_ID = "3331482000003593671"
INV_NO = "KGT-IN-001691"
CUST_ID = "3331482000002568353"
AR_ACCT = "3331482000000000364"          # Accounts Receivable
OCA_ACCT = "3331482000184871012"         # SHAMEER OLD BALANCE (other_current_asset)
CUST_NAME = "DARL AL ANWAR CAFTERIA"
LEDGER_NAME = "SHAMEER OLD BALANCE"
SALESMAN = "SHAMEER TAYYIL&HASHIM"
CURRENT_SALESMAN = "MR SHAMEER"
INV_DATE = "2022-12-24"
DUE_DATE = "2022-12-24"
AGE_DAYS = 1339
INV_TOTAL = 924.42
AMOUNT = 524.42
JOURNAL_DATE = "2026-09-10"
REF = f"OLDBAL-JC-{INV_NO}"

_session = requests.Session()
_token = None
# shared with settle_old_bills_to_salesman.py -> avoids Zoho token-gen rate limits
TOKEN_CACHE = os.path.join(os.path.dirname(__file__), "settle_runs", ".token_cache.json")


def token():
    global _token
    if _token:
        return _token
    try:
        with open(TOKEN_CACHE, encoding="utf-8") as f:
            d = json.load(f)
        import time as _t
        if d.get("access_token") and d.get("expires_at", 0) > _t.time() + 120:
            _token = d["access_token"]
            return _token
    except (OSError, ValueError):
        pass
    import time as _t
    r = _session.post(
        "https://accounts.zoho.com/oauth/v2/token",
        params={"grant_type": "refresh_token", "refresh_token": RTOK,
                "client_id": CID, "client_secret": CSEC}, timeout=30).json()
    if "access_token" not in r:
        raise RuntimeError(f"token refresh failed: {r}")
    _token = r["access_token"]
    try:
        os.makedirs(os.path.dirname(TOKEN_CACHE), exist_ok=True)
        with open(TOKEN_CACHE, "w", encoding="utf-8") as f:
            json.dump({"access_token": _token,
                       "expires_at": _t.time() + r.get("expires_in", 3600) - 180}, f)
    except OSError:
        pass
    return _token


def call(method, path, body=None):
    r = _session.request(
        method, f"{BASE}{path}",
        headers={"Authorization": f"Zoho-oauthtoken {token()}",
                 "Content-Type": "application/json"},
        params={"organization_id": ORG},
        data=json.dumps(body) if body is not None else None, timeout=60)
    try:
        data = r.json() if r.content else {}
    except ValueError:
        data = {"_raw": r.text}
    return r.status_code, data


JOURNAL_BODY = {
    "journal_date": JOURNAL_DATE,
    "reference_number": REF,
    "notes": " ".join([
        f"Aged-debt accountability transfer (old_bills.xlsx, {JOURNAL_DATE}).",
        f"Invoice {INV_NO} dated {INV_DATE}, total AED {INV_TOTAL:.2f}, {AGE_DAYS}d overdue.",
        f"Customer: {CUST_NAME}. Salesman {SALESMAN}, now {CURRENT_SALESMAN}.",
        f"AED {AMOUNT:.2f} open balance moved from A/R to {LEDGER_NAME} (Other Current Asset).",
        "Not a write-off; original revenue and VAT unchanged.",
    ]),
    "journal_type": "both",
    "line_items": [
        {"account_id": AR_ACCT, "customer_id": CUST_ID,
         "debit_or_credit": "credit", "amount": AMOUNT,
         "description": (f"{INV_NO} {CUST_NAME} - aged open balance {AMOUNT:.2f} "
                         f"cleared from A/R to {LEDGER_NAME}")},
        {"account_id": OCA_ACCT,
         "debit_or_credit": "debit", "amount": AMOUNT,
         "description": (f"{INV_NO} aged receivable parked in {LEDGER_NAME} - "
                         f"salesman {SALESMAN}, invoice {INV_DATE}, {AGE_DAYS}d overdue")},
    ],
}


def dry_run():
    print("STEP 1  POST /journals")
    print(json.dumps(JOURNAL_BODY, indent=2))
    print("\nSTEP 2  POST /journals/{journal_id}/status/publish   (no body; skipped if auto-published)")
    print("\nSTEP 4  GET /journals/{journal_id}/credits   (confirm available receivables credit)")
    print("\nSTEP 5  POST /journals/{journal_id}/credits/{journal_line_id}/invoices")
    print("        journal_line_id = line_id of the AR credit line")
    print(json.dumps({"invoices": [
        {"invoice_id": INV_ID, "amount_applied": AMOUNT}]}, indent=2))


def show(tag, sc, data):
    print(f"\n--- {tag}  HTTP {sc}")
    print(json.dumps(data, indent=2)[:4000])


def run():
    sc, inv = call("GET", f"/invoices/{INV_ID}")
    bal = float(inv.get("invoice", {}).get("balance", 0) or 0)
    st = inv.get("invoice", {}).get("status")
    print(f"pre-check: invoice {INV_NO} status={st} balance={bal}")
    if st in ("paid", "void", "draft") or bal <= 0:
        sys.exit("invoice not open / nothing to transfer -- abort")
    apply_amt = round(min(AMOUNT, bal), 2)

    sc, data = call("POST", "/journals", JOURNAL_BODY)
    show("1. create journal", sc, data)
    if sc not in (200, 201):
        sys.exit("journal create failed -- abort")
    jid = data["journal"]["journal_id"]
    print(f"\n>>> journal_id = {jid}   (use this for --undo)")

    if data["journal"].get("status") != "published":
        sc, data = call("POST", f"/journals/{jid}/status/publish")
        show("2. publish", sc, data)
    else:
        print("\n--- 2. publish  (auto-published on create)")

    _apply(jid, apply_amt)


def _ar_credit_line_id(journal):
    """line_id of the credit line that is on Accounts Receivable with a contact."""
    for li in journal.get("line_items", []):
        if (li.get("debit_or_credit") == "credit"
                and li.get("account_id") == AR_ACCT
                and li.get("customer_id")):
            return li["line_id"]
    return None


def _apply(jid, apply_amt):
    sc, data = call("GET", f"/journals/{jid}")
    show("3. journal", sc, data)
    jrn = data.get("journal", {})
    line_id = _ar_credit_line_id(jrn)
    print(f"\nAR credit line_id = {line_id}   "
          f"available_receivables_credits = {jrn.get('available_receivables_credits')}")
    if not line_id:
        sys.exit("could not find the AR credit line -- abort")

    sc, data = call("GET", f"/journals/{jid}/credits")
    show("4. GET /journals/{jid}/credits", sc, data)

    body = {"invoices": [{"invoice_id": INV_ID, "amount_applied": apply_amt}]}
    sc, data = call("POST", f"/journals/{jid}/credits/{line_id}/invoices", body)
    show("5. POST .../credits/{line_id}/invoices", sc, data)
    applied_ok = sc in (200, 201) and data.get("code") in (0, None)

    sc, inv = call("GET", f"/invoices/{INV_ID}")
    i = inv.get("invoice", {})
    print(f"\npost-check: invoice {INV_NO} status={i.get('status')} "
          f"balance={i.get('balance')} credits_applied={i.get('credits_applied')}")
    print(f"\n{'>>> APPLY SUCCEEDED' if applied_ok else '[!] APPLY FAILED'}   journal_id={jid}")
    if not applied_ok:
        print(f"    clean up:  python jc_transfer_test.py --undo {jid}")


def apply_only(jid):
    sc, inv = call("GET", f"/invoices/{INV_ID}")
    bal = float(inv.get("invoice", {}).get("balance", 0) or 0)
    _apply(jid, round(min(AMOUNT, bal), 2))


def undo(jid):
    # unapply each credit first (journal can't be deleted while applied).
    # resource id = invoices_credited[].journal_invoice_id, path .../receivables
    sc, data = call("GET", f"/journals/{jid}")
    for jinv in data.get("journal", {}).get("invoices_credited", []) or []:
        jinv_id = jinv.get("journal_invoice_id")
        s2, d2 = call("DELETE", f"/journals/{jid}/credits/{jinv_id}/receivables")
        show(f"unapply {jinv.get('invoice_number')} ({jinv_id})", s2, d2)
    sc, data = call("DELETE", f"/journals/{jid}")
    show("delete journal", sc, data)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--dry-run", action="store_true")
    g.add_argument("--run", action="store_true")
    g.add_argument("--apply", metavar="JOURNAL_ID")
    g.add_argument("--undo", metavar="JOURNAL_ID")
    a = ap.parse_args()
    if a.dry_run:
        dry_run()
    elif a.run:
        run()
    elif a.apply:
        apply_only(a.apply)
    else:
        undo(a.undo)
