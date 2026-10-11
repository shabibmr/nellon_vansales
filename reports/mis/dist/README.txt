Trial Balance export (Zoho Books GL + Chart of Accounts)
========================================================

1. Place this folder next to your .env_zoho, OR keep the script under
   nellon_vansales/reports/mis/ (it loads ../../.env_zoho).

2. Setup:
     python3 -m venv .venv
     .venv/bin/pip install -r requirements.txt

3. Run:
     .venv/bin/python export_trial_balance.py --from-date 2026-04-01 --to-date 2026-10-11

Outputs CSV / Excel / JSON under ./output/
