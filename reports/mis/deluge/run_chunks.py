#!/usr/bin/env python3
"""Run backfill_cogs in chunks of explicit invoice IDs (fits Zoho's ~40 s Deluge limit).

For each chunk: PUT the script with that chunk's invoice IDs, then POST .../execute.
Stops on the first error / failed invoice. Progress goes to deluge/run_chunks.log;
re-running resumes after the last finished chunk (deluge/run_chunks.state).
Restores the full-range script at the end.
"""
import json, re, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from zoho_client import ZohoClient

D = Path(__file__).resolve().parent
FID = "3331482000188166178"
FROM_DATE, END_DATE, CHUNK, PAUSE = "2026-09-11", "2026-09-30", 33, 5
rows = json.loads((D / "sept_invoices.json").read_text())
sel = [r for r in rows if FROM_DATE <= r["date"] <= END_DATE and r["status"] not in ("void", "draft")]
full = (D / "backfill_cogs.deluge").read_text()
a = full.index("batch = List();"); b = full.index('info "Invoices to process: "')
state = D / f"run_chunks_{FROM_DATE}_{END_DATE}.state"
done_chunks = int(state.read_text()) if state.exists() else 0
log = open(D / f"run_chunks_{FROM_DATE}_{END_DATE}.log", "a")
def say(m): print(m, flush=True); log.write(m + "\n"); log.flush()

c = ZohoClient()
chunks = [sel[i:i + CHUNK] for i in range(0, len(sel), CHUNK)]
say(f"{len(sel)} invoices, {len(chunks)} chunks, resuming at chunk {done_chunks + 1}")
for n, ch in enumerate(chunks, 1):
    if n <= done_chunks: continue
    lit = "batch = List();\n" + "".join(
        f'm = Map();\nm.put("invoice_id","{r["invoice_id"]}");\nm.put("invoice_number","{r["invoice_number"]}");\nm.put("status","{r["status"]}");\nbatch.add(m);\n' for r in ch)
    script = full[:a] + lit + full[b:]
    c.put(f"/integrations/customfunctions/{FID}", json_data={"entity": "invoice", "language": "deluge", "function_name": "backfill_cogs", "return_type": "void", "script": script})
    r = c.post(f"/integrations/customfunctions/{FID}/execute", params={"entity_id": ch[0]["invoice_id"]})
    logs = r.get("response", {}).get("log_message", [])
    summ = next((l for l in reversed(logs) if "updated=" in l), "")
    say(f"chunk {n}/{len(chunks)} {ch[0]['invoice_number']}..{ch[-1]['invoice_number']}: {summ or logs[-3:]}")
    m = re.search(r"updated=(\d+) skipped=(\d+) failed=(\d+)", summ)
    if not m or int(m[1]) != len(ch) or int(m[3]):
        say("STOPPING: chunk did not fully succeed"); sys.exit(1)
    state.write_text(str(n)); time.sleep(PAUSE)
c.put(f"/integrations/customfunctions/{FID}", json_data={"entity": "invoice", "language": "deluge", "function_name": "backfill_cogs", "return_type": "void", "script": full})
say("ALL DONE; full-range script restored")
