# Zoho API tools

Use these scripts from `reports/mis`. Do not reimplement the HTTP call.

Credentials come from `E:\work\nellon\.env_zoho` through `zoho_client.py` (`ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`, `ZOHO_ORG_ID`). The client posts to `https://accounts.zoho.com/oauth/v2/token` and calls `https://www.zohoapis.com/books/v3`.

## Full invoice

When a task needs one Zoho Books invoice with its line items, taxes, addresses, custom fields, and payments, run:

```text
python zoho_api_tools/fetch_invoice.py INVOICE_ID
```

`INVOICE_ID` is the numeric Zoho `invoice_id`, not the invoice number (`SMR-INV-00672` and similar).

The script calls `GET /invoices/{invoice_id}?organization_id=...&accept=json` (scope `ZohoBooks.invoices.READ`). That is the full invoice. `GET /invoices` is a list and omits the detail payload.

Stdout is the Books JSON: `code`, `message`, and `invoice`. Exit `0` on success. Exit `1` and a one-line message on stderr on failure. Exit `2` when the arguments are wrong.

To keep a large invoice out of the chat, write it to a file and then read only the fields you need:

```text
python zoho_api_tools/fetch_invoice.py INVOICE_ID --out zoho_api_tools/out/INVOICE_ID.json
```

Do not commit files under `zoho_api_tools/out/`.

## Invoice list for a date range

When a task needs the invoices whose invoice date falls in a range, run:

```text
python zoho_api_tools/list_invoices.py --from YYYY-MM-DD --to YYYY-MM-DD
```

Both dates are inclusive. The script calls `GET /invoices` with `date_start`, `date_end`, `sort_column=date`, and `per_page=200`, then follows `page_context.has_more_page` (scope `ZohoBooks.invoices.READ`). It stops after 100 pages.

Stdout is one JSON object: `code`, `message`, `date_start`, `date_end`, `page_count`, `invoice_count`, and `invoices`. Each invoice is the list summary (id, number, date, status, customer, total, balance). It does not include line items. For one full invoice, use `fetch_invoice.py` with that row's `invoice_id`.

```text
python zoho_api_tools/list_invoices.py --from YYYY-MM-DD --to YYYY-MM-DD --out zoho_api_tools/out/invoices.json
```

Python needs `requests` and `python-dotenv` (`requirements.txt`). If the workspace interpreter lacks them, use `E:\work\nellon\zoho_endpoints\venv\Scripts\python.exe`.
