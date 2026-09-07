"""
Write Off Invoices
--------------------
Takes a candidates file produced by find_writeoff_candidates.py and writes
off each invoice's balance to the Bad Debts account. Also supports undoing
a previous run via --undo.

Each write-off call has real network latency (~2-3s), so a single-threaded loop
falls well short of the calls-per-min pace cap even with a short sleep. --concurrency
runs multiple calls in flight at once, while a shared rate limiter still enforces the
aggregate calls/min ceiling across all worker threads combined (not per-thread).

Usage:
    pip install requests python-dotenv
    python writeoff_invoices.py --input writeoff_runs/candidates_<ts>.json
    python writeoff_invoices.py --input writeoff_runs/candidates_<ts>.json --concurrency 5 --calls-per-min 80
    python writeoff_invoices.py --undo writeoff_runs/writeoff_log_<ts>.json
"""

import argparse
import json
import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env_zoho"))


def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key}  (set it in .env_zoho)")
    return val


CLIENT_ID = _require_env("ZOHO_CLIENT_ID")
CLIENT_SECRET = _require_env("ZOHO_CLIENT_SECRET")
REFRESH_TOKEN = _require_env("ZOHO_REFRESH_TOKEN")
ORG_ID = _require_env("ZOHO_ORG_ID")
TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"

RUNS_DIR = os.path.join(os.path.dirname(__file__), "writeoff_runs")


class TokenManager:
    """Thread-safe OAuth token manager that automatically refreshes the token before expiry."""

    def __init__(self):
        self.lock = threading.Lock()
        self.token = ""
        self.expires_at = 0.0
        self.last_refreshed = 0.0

    def get_token(self, force_refresh: bool = False) -> str:
        with self.lock:
            now = time.time()
            should_refresh = (
                not self.token
                or now >= self.expires_at
                or (force_refresh and (now - self.last_refreshed > 10))
            )
            if should_refresh:
                for attempt in range(3):
                    try:
                        resp = requests.post(TOKEN_URL, params={
                            "grant_type": "refresh_token",
                            "refresh_token": REFRESH_TOKEN,
                            "client_id": CLIENT_ID,
                            "client_secret": CLIENT_SECRET,
                        }, timeout=20)
                        data = resp.json()
                        if "access_token" in data:
                            self.token = data["access_token"]
                            self.expires_at = now + data.get("expires_in", 3600) - 180
                            self.last_refreshed = now
                            return self.token
                    except Exception:
                        time.sleep(2)
                if not self.token:
                    raise RuntimeError("Token refresh failed after retries")
            return self.token


token_mgr = TokenManager()


def get_access_token() -> str:
    return token_mgr.get_token()


def _load_succeeded_ids(log_path: str) -> set[str]:
    """Read a previous run's log (.json array or .jsonl lines) and return invoice_ids
    that succeeded or were already closed, so a resumed run can skip them."""
    path = _resolve(log_path)
    succeeded = set()
    if path.endswith(".jsonl"):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                    if entry.get("success") or "closed invoice" in entry.get("message", "").lower():
                        succeeded.add(entry["invoice_id"])
                except Exception:
                    pass
    else:
        with open(path, encoding="utf-8") as f:
            entries = json.load(f)
        succeeded = {
            e["invoice_id"]
            for e in entries
            if e.get("success") or "closed invoice" in e.get("message", "").lower()
        }
    return succeeded


def _resolve(path: str) -> str:
    """Accept a bare filename (looked up in writeoff_runs/) or a full path."""
    if os.path.exists(path):
        return path
    candidate = os.path.join(RUNS_DIR, path)
    if os.path.exists(candidate):
        return candidate
    raise FileNotFoundError(f"Could not find file: {path}")


def confirm(prompt: str) -> bool:
    answer = input(f"{prompt} [y/N]: ").strip().lower()
    return answer == "y"


class RateLimiter:
    """Shared across worker threads — caps the aggregate call rate, not per-thread."""

    def __init__(self, calls_per_min: int):
        self.interval = 60.0 / calls_per_min
        self.lock = threading.Lock()
        self.next_slot = time.monotonic()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            slot = max(now, self.next_slot)
            self.next_slot = slot + self.interval
        delay = slot - now
        if delay > 0:
            time.sleep(delay)


class QuotaTracker:
    """Monitors X-Rate-Limit-Remaining header from Zoho and signals a graceful stop
    when remaining daily calls hit the safety threshold (default 100 remaining = 9,900 calls used)."""

    def __init__(self, min_remaining: int = 100):
        self.lock = threading.Lock()
        self.min_remaining = min_remaining
        self.stop_requested = False
        self.last_remaining = None

    def record_headers(self, headers):
        rem = headers.get("X-Rate-Limit-Remaining")
        if rem is not None:
            try:
                rem_val = int(rem)
                with self.lock:
                    self.last_remaining = rem_val
                    if rem_val <= self.min_remaining and not self.stop_requested:
                        self.stop_requested = True
                        print(f"\n[ALERT] Reached safe daily API limit cap! Remaining: {rem_val} (safe buffer: {self.min_remaining}). Gracefully stopping batch for today.\n", flush=True)
            except ValueError:
                pass

    def should_stop(self) -> bool:
        with self.lock:
            return self.stop_requested


def do_writeoff(invoice_id: str, quota_tracker: QuotaTracker | None = None) -> tuple[bool, str]:
    if quota_tracker and quota_tracker.should_stop():
        return False, "Skipped: Daily API call limit reached (buffer <= 100)"
    for attempt in range(3):
        try:
            token = token_mgr.get_token()
            headers = {"Authorization": f"Zoho-oauthtoken {token}"}
            resp = requests.post(
                f"{API_BASE}/invoices/{invoice_id}/writeoff",
                headers=headers,
                params={"organization_id": ORG_ID},
                timeout=30,
            )
            if quota_tracker:
                quota_tracker.record_headers(resp.headers)

            if resp.status_code == 401:
                token = token_mgr.get_token(force_refresh=True)
                headers = {"Authorization": f"Zoho-oauthtoken {token}"}
                resp = requests.post(
                    f"{API_BASE}/invoices/{invoice_id}/writeoff",
                    headers=headers,
                    params={"organization_id": ORG_ID},
                    timeout=30,
                )
                if quota_tracker:
                    quota_tracker.record_headers(resp.headers)

            if resp.status_code == 429:
                time.sleep(5)
                continue
            data = resp.json() if resp.content else {}
            if resp.status_code == 200:
                return True, data.get("message", "OK")
            return False, data.get("message", f"HTTP {resp.status_code}")
        except Exception as e:
            if attempt == 2:
                return False, f"Error: {e}"
            time.sleep(2)
    return False, "Unknown failure after retries"


def do_cancel(invoice_id: str) -> tuple[bool, str]:
    for attempt in range(3):
        try:
            token = token_mgr.get_token()
            headers = {"Authorization": f"Zoho-oauthtoken {token}"}
            resp = requests.post(
                f"{API_BASE}/invoices/{invoice_id}/writeoff/cancel",
                headers=headers,
                params={"organization_id": ORG_ID},
                timeout=30,
            )
            if resp.status_code == 401:
                token = token_mgr.get_token(force_refresh=True)
                headers = {"Authorization": f"Zoho-oauthtoken {token}"}
                resp = requests.post(
                    f"{API_BASE}/invoices/{invoice_id}/writeoff/cancel",
                    headers=headers,
                    params={"organization_id": ORG_ID},
                    timeout=30,
                )
            if resp.status_code == 429:
                time.sleep(5)
                continue
            data = resp.json() if resp.content else {}
            if resp.status_code == 200:
                return True, data.get("message", "OK")
            return False, data.get("message", f"HTTP {resp.status_code}")
        except Exception as e:
            if attempt == 2:
                return False, f"Error: {e}"
            time.sleep(2)
    return False, "Unknown failure after retries"


def run_writeoff(input_path: str, max_calls: int | None = None, calls_per_min: int = 80,
                  skip_confirm: bool = False, concurrency: int = 1, resume_from: str | None = None,
                  min_remaining: int = 100):
    path = _resolve(input_path)
    with open(path, encoding="utf-8") as f:
        candidates = json.load(f)

    if resume_from:
        already_done = _load_succeeded_ids(resume_from)
        before = len(candidates)
        candidates = [c for c in candidates if c["invoice_id"] not in already_done]
        print(f"Resuming: skipping {before - len(candidates)} invoice(s) already processed per {resume_from}.", flush=True)

    if not candidates:
        print("Candidate file is empty (or everything already done). Nothing to do.", flush=True)
        return

    deferred = []
    if max_calls is not None and len(candidates) > max_calls:
        deferred = candidates[max_calls:]
        candidates = candidates[:max_calls]

    total = sum(c["balance"] for c in candidates)
    print(f"Loaded {len(candidates)} invoice(s) from {path}"
          + (f" (capped at {max_calls}; {len(deferred)} deferred to a later run)" if deferred else ""), flush=True)
    print(f"Total balance to write off this run: {total:.2f}", flush=True)
    print(f"Pace: {calls_per_min} calls/min, {concurrency} concurrent worker(s)", flush=True)
    print(f"Safety Cap: Stopping when daily remaining quota reaches {min_remaining} (stop at 9,900/10,000)\n", flush=True)

    if not skip_confirm and not confirm(f"Write off {len(candidates)} invoice(s) to Bad Debts?"):
        print("Aborted. Nothing was changed.", flush=True)
        return

    token_mgr.get_token()  # Pre-warm token
    limiter = RateLimiter(calls_per_min)
    quota_tracker = QuotaTracker(min_remaining=min_remaining)
    io_lock = threading.Lock()
    log = []
    ok_count = 0
    done = 0

    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    jsonl_path = os.path.join(RUNS_DIR, f"writeoff_log_{timestamp}.jsonl")
    jsonl_file = open(jsonl_path, "a", encoding="utf-8")
    print(f"Live log (crash-safe, one line per call): {jsonl_path}\n", flush=True)

    def process(c: dict) -> dict:
        if quota_tracker.should_stop():
            return {**c, "success": False, "message": "Deferred: Daily API limit buffer reached (<= 100 remaining)"}
        try:
            limiter.wait()
            if quota_tracker.should_stop():
                return {**c, "success": False, "message": "Deferred: Daily API limit buffer reached (<= 100 remaining)"}
            success, message = do_writeoff(c["invoice_id"], quota_tracker)
            return {**c, "success": success, "message": message}
        except Exception as err:
            return {**c, "success": False, "message": f"Exception: {err}"}

    processed_ids = set()
    try:
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            future_to_cand = {}
            for c in candidates:
                if quota_tracker.should_stop():
                    break
                fut = pool.submit(process, c)
                future_to_cand[fut] = c
                if len(future_to_cand) >= concurrency * 2:
                    # Drain completed before submitting more to allow timely stop
                    done_set = {f for f in future_to_cand if f.done()}
                    for fut in done_set:
                        entry = fut.result()
                        done += 1
                        processed_ids.add(entry["invoice_id"])
                        status = "OK" if entry["success"] else "FAIL"
                        with io_lock:
                            print(f"  [{done}/{len(candidates)}] [{status}] {entry['customer_name']:<35} "
                                  f"{entry['invoice_number']:<18} {entry['message']}", flush=True)
                            jsonl_file.write(json.dumps(entry, ensure_ascii=False) + "\n")
                            jsonl_file.flush()
                        log.append(entry)
                        if entry["success"]:
                            ok_count += 1
                        del future_to_cand[fut]

            for fut in as_completed(future_to_cand):
                try:
                    entry = fut.result()
                except Exception as err:
                    entry = {"invoice_id": "", "invoice_number": "", "customer_name": "UNKNOWN", "balance": 0.0, "success": False, "message": f"Future failed: {err}"}
                done += 1
                processed_ids.add(entry.get("invoice_id", ""))
                status = "OK" if entry["success"] else "FAIL"
                with io_lock:
                    print(f"  [{done}/{len(candidates)}] [{status}] {entry['customer_name']:<35} "
                          f"{entry['invoice_number']:<18} {entry['message']}", flush=True)
                    jsonl_file.write(json.dumps(entry, ensure_ascii=False) + "\n")
                    jsonl_file.flush()
                log.append(entry)
                if entry["success"]:
                    ok_count += 1
    finally:
        jsonl_file.close()

    log_path = os.path.join(RUNS_DIR, f"writeoff_log_{timestamp}.json")
    with open(log_path, "w", encoding="utf-8") as f:
        json.dump(log, f, indent=2, ensure_ascii=False)

    print(f"\n{ok_count}/{done} written off successfully in this session.", flush=True)
    print(f"Log saved to: {log_path}", flush=True)

    unprocessed = [c for c in candidates if c["invoice_id"] not in processed_ids]
    all_deferred = unprocessed + deferred
    if all_deferred:
        deferred_path = os.path.join(RUNS_DIR, f"candidates_postponed_{timestamp}.json")
        with open(deferred_path, "w", encoding="utf-8") as f:
            json.dump(all_deferred, f, indent=2, ensure_ascii=False)
        print(f"\n[POSTPONED] {len(all_deferred)} invoice(s) saved for next run / tomorrow: {deferred_path}", flush=True)
        print(f"  To resume after quota reset: python writeoff_invoices.py --input {os.path.basename(deferred_path)} --concurrency {concurrency} --yes", flush=True)


def run_undo(log_path: str):
    path = _resolve(log_path)
    with open(path, encoding="utf-8") as f:
        entries = json.load(f)

    succeeded = [e for e in entries if e.get("success")]
    if not succeeded:
        print("No successful write-offs in this log to undo.", flush=True)
        return

    print(f"Loaded {len(succeeded)} previously written-off invoice(s) from {path}", flush=True)
    for e in succeeded:
        print(f"  {e['customer_name']:<35} {e['invoice_number']:<18} {e['balance']:>10.2f}", flush=True)
    print()

    if not confirm(f"Cancel the write-off for all {len(succeeded)} invoice(s) above?"):
        print("Aborted. Nothing was changed.", flush=True)
        return

    token_mgr.get_token()  # Pre-warm token
    ok_count = 0
    for e in succeeded:
        success, message = do_cancel(e["invoice_id"])
        status = "OK" if success else "FAIL"
        print(f"  [{status}] {e['customer_name']:<35} {e['invoice_number']:<18} {message}", flush=True)
        if success:
            ok_count += 1
        time.sleep(0.75)  # 80 calls/min

    print(f"\n{ok_count}/{len(succeeded)} write-offs cancelled.", flush=True)


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--input", help="Candidates JSON file from find_writeoff_candidates.py")
    group.add_argument("--undo", help="writeoff_log_*.json file from a previous run to reverse")
    parser.add_argument("--max-calls", type=int, default=None,
                         help="Cap on invoices processed this run; the rest are saved to a 'remaining' file.")
    parser.add_argument("--calls-per-min", type=int, default=80,
                         help="Write-off call pace, staying under Zoho's 100/min limit. Default 80.")
    parser.add_argument("--concurrency", type=int, default=1,
                         help="Number of write-off calls to have in flight at once. Default 1.")
    parser.add_argument("--yes", action="store_true", help="Skip the interactive y/N confirmation.")
    parser.add_argument("--resume-from", default=None,
                         help="A previous run's log (.json or .jsonl) — invoices already written off "
                              "there are skipped in this run.")
    parser.add_argument("--min-remaining", type=int, default=100,
                         help="Stop batch when Zoho daily remaining API quota reaches this buffer (default 100, stopping at 9,900/10,000).")
    args = parser.parse_args()

    if args.input:
        run_writeoff(args.input, max_calls=args.max_calls, calls_per_min=args.calls_per_min,
                      skip_confirm=args.yes, concurrency=args.concurrency, resume_from=args.resume_from,
                      min_remaining=args.min_remaining)
    else:
        run_undo(args.undo)


if __name__ == "__main__":
    main()
