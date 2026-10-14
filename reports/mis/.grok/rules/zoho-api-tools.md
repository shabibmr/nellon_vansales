# Zoho invoice fetches

Do not write a new Python client or one-off script to read Zoho Books invoices.

- One full invoice: `python zoho_api_tools/fetch_invoice.py INVOICE_ID`
- Invoices in a date range: `python zoho_api_tools/list_invoices.py --from YYYY-MM-DD --to YYYY-MM-DD`

`INVOICE_ID` is the numeric Zoho id. Read `zoho_api_tools/tools_context.md` before calling either script. Credentials stay in `E:\work\nellon\.env_zoho` through `zoho_client.py`.
