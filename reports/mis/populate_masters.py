"""Populate masters (organization, accounts, items, item_units) into MariaDB.

Usage:
    python populate_masters.py [--database zoho-koyson]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from pathlib import Path
from typing import Any

import pymysql
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")


def _s(val: Any, limit: int = 255) -> str:
    return str(val if val is not None else "").strip()[:limit]


def _f(val: Any, default: float = 0.0) -> float:
    try:
        return float(val) if val is not None else default
    except (ValueError, TypeError):
        return default


def _dt(val: Any) -> str | None:
    if not val:
        return None
    # Formats like 2026-07-22T15:32:43+0400 or 2023-11-24T11:53:23+0400
    s = str(val).strip()
    return s[:19].replace("T", " ") if len(s) >= 19 else None


def get_connection(db_name: str) -> pymysql.Connection:
    return pymysql.connect(
        host=os.getenv("MIS_DB_HOST", "127.0.0.1"),
        port=int(os.getenv("MIS_DB_PORT", "3306")),
        user=os.getenv("MIS_DB_USER", "user2grey"),
        password=os.getenv("MIS_DB_PASSWORD", "user2grey"),
        database=db_name,
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
    )


def populate_organization(cur: pymysql.cursors.DictCursor) -> int:
    """Populate organization from output/coa_snapshot.json."""
    coa_file = BASE_DIR / "output" / "coa_snapshot.json"
    if not coa_file.exists():
        print(f"Warning: {coa_file} not found, skipping organization.")
        return 0

    with open(coa_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    org_id = _s(data.get("organization_id", "783019958"), 40)
    org_name = _s(data.get("organization_name", "KOYSON GENERAL TRADING LLC"), 255)
    currency_code = _s(data.get("currency_code", "AED"), 10)
    fiscal_month = int(data.get("fiscal_year_start_month") or 1)
    if fiscal_month == 0:
        fiscal_month = 1  # Per spec: Zoho 0 means January (month 1)

    sql = """
        INSERT INTO organization (
            organization_id, name, currency_id, currency_code, currency_symbol,
            currency_format, fiscal_year_start_month, time_zone, country,
            country_code, is_tax_registered, synced_at
        ) VALUES (
            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW()
        ) ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            currency_id = VALUES(currency_id),
            currency_code = VALUES(currency_code),
            currency_symbol = VALUES(currency_symbol),
            currency_format = VALUES(currency_format),
            fiscal_year_start_month = VALUES(fiscal_year_start_month),
            time_zone = VALUES(time_zone),
            country = VALUES(country),
            country_code = VALUES(country_code),
            is_tax_registered = VALUES(is_tax_registered),
            synced_at = NOW()
    """
    cur.execute(
        sql,
        (
            org_id,
            org_name,
            "3331482000000075111",
            currency_code,
            currency_code,
            "###,##0.00",
            fiscal_month,
            "Asia/Dubai",
            "U.A.E",
            "AE",
            1,
        ),
    )
    return cur.rowcount


def populate_accounts(cur: pymysql.cursors.DictCursor) -> int:
    """Populate accounts from output/coa_snapshot.json and output/category_master.json."""
    coa_file = BASE_DIR / "output" / "coa_snapshot.json"
    cm_file = BASE_DIR / "output" / "category_master.json"

    if not coa_file.exists():
        print(f"Error: {coa_file} does not exist.")
        return 0

    with open(coa_file, "r", encoding="utf-8") as f:
        coa_data = json.load(f)

    cm_rows = {}
    if cm_file.exists():
        with open(cm_file, "r", encoding="utf-8") as f:
            cm_json = json.load(f)
            for r in cm_json.get("rows", []):
                cm_rows[r["account_id"]] = r

    accounts = coa_data.get("accounts", [])
    sql = """
        INSERT INTO accounts (
            account_id, account_code, account_name, account_type,
            parent_account_id, parent_account_name, group_ledger,
            is_active, pl_bs, category, sub_category, source,
            note, last_modified_time
        ) VALUES (
            %(account_id)s, %(account_code)s, %(account_name)s, %(account_type)s,
            %(parent_account_id)s, %(parent_account_name)s, %(group_ledger)s,
            %(is_active)s, %(pl_bs)s, %(category)s, %(sub_category)s, %(source)s,
            %(note)s, %(last_modified_time)s
        ) ON DUPLICATE KEY UPDATE
            account_code = VALUES(account_code),
            account_name = VALUES(account_name),
            account_type = VALUES(account_type),
            parent_account_id = VALUES(parent_account_id),
            parent_account_name = VALUES(parent_account_name),
            group_ledger = VALUES(group_ledger),
            is_active = VALUES(is_active),
            pl_bs = VALUES(pl_bs),
            category = VALUES(category),
            sub_category = VALUES(sub_category),
            source = VALUES(source),
            note = VALUES(note),
            last_modified_time = VALUES(last_modified_time)
    """

    rows_to_insert = []
    for a in accounts:
        aid = a["account_id"]
        cm_r = cm_rows.get(aid, {})
        parent_id = a.get("parent_account_id")
        parent_id = parent_id if parent_id else None

        row = {
            "account_id": _s(aid, 40),
            "account_code": _s(a.get("account_code"), 50),
            "account_name": _s(a.get("account_name"), 255),
            "account_type": _s(a.get("account_type"), 50),
            "parent_account_id": parent_id,
            "parent_account_name": _s(a.get("parent_account_name"), 255),
            "group_ledger": _s(cm_r.get("group_ledger") or "Ledger", 20),
            "is_active": 1 if a.get("is_active") else 0,
            "pl_bs": _s(cm_r.get("pl_bs"), 10),
            "category": _s(cm_r.get("category"), 120),
            "sub_category": _s(cm_r.get("sub_category"), 255),
            "source": _s(cm_r.get("source"), 20),
            "note": _s(cm_r.get("note"), 500),
            "last_modified_time": _dt(a.get("last_modified_time")),
        }
        rows_to_insert.append(row)

    cur.executemany(sql, rows_to_insert)
    return len(rows_to_insert)


def populate_items(cur: pymysql.cursors.DictCursor) -> int:
    """Populate items from output/cache/items/_list.json."""
    list_file = BASE_DIR / "output" / "cache" / "items" / "_list.json"
    if not list_file.exists():
        print(f"Error: {list_file} does not exist.")
        return 0

    with open(list_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    items = data.get("items", [])
    sql = """
        INSERT INTO items (
            item_id, name, sku, status, item_type, product_type, unit,
            purchase_rate, rate, account_id, account_name,
            purchase_account_id, purchase_account_name,
            tax_id, tax_name, tax_percentage, brand,
            track_inventory, can_be_sold, can_be_purchased,
            last_modified_time
        ) VALUES (
            %(item_id)s, %(name)s, %(sku)s, %(status)s, %(item_type)s, %(product_type)s, %(unit)s,
            %(purchase_rate)s, %(rate)s, %(account_id)s, %(account_name)s,
            %(purchase_account_id)s, %(purchase_account_name)s,
            %(tax_id)s, %(tax_name)s, %(tax_percentage)s, %(brand)s,
            %(track_inventory)s, %(can_be_sold)s, %(can_be_purchased)s,
            %(last_modified_time)s
        ) ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            sku = VALUES(sku),
            status = VALUES(status),
            item_type = VALUES(item_type),
            product_type = VALUES(product_type),
            unit = VALUES(unit),
            purchase_rate = VALUES(purchase_rate),
            rate = VALUES(rate),
            account_id = VALUES(account_id),
            account_name = VALUES(account_name),
            purchase_account_id = VALUES(purchase_account_id),
            purchase_account_name = VALUES(purchase_account_name),
            tax_id = VALUES(tax_id),
            tax_name = VALUES(tax_name),
            tax_percentage = VALUES(tax_percentage),
            brand = VALUES(brand),
            track_inventory = VALUES(track_inventory),
            can_be_sold = VALUES(can_be_sold),
            can_be_purchased = VALUES(can_be_purchased),
            last_modified_time = VALUES(last_modified_time)
    """

    rows_to_insert = []
    for item in items:
        aid = item.get("account_id")
        aid = aid if aid else None
        paid = item.get("purchase_account_id")
        paid = paid if paid else None

        row = {
            "item_id": _s(item.get("item_id"), 40),
            "name": _s(item.get("name") or item.get("item_name"), 255),
            "sku": _s(item.get("sku"), 100),
            "status": _s(item.get("status") or "active", 20),
            "item_type": _s(item.get("item_type"), 50),
            "product_type": _s(item.get("product_type"), 50),
            "unit": _s(item.get("unit"), 40),
            "purchase_rate": _f(item.get("purchase_rate")),
            "rate": _f(item.get("rate")),
            "account_id": aid,
            "account_name": _s(item.get("account_name"), 255),
            "purchase_account_id": paid,
            "purchase_account_name": _s(item.get("purchase_account_name"), 255),
            "tax_id": _s(item.get("tax_id"), 40),
            "tax_name": _s(item.get("tax_name"), 100),
            "tax_percentage": _f(item.get("tax_percentage")),
            "brand": _s(item.get("brand"), 100),
            "track_inventory": 1 if item.get("track_inventory") else 0,
            "can_be_sold": 1 if item.get("can_be_sold") else 0,
            "can_be_purchased": 1 if item.get("can_be_purchased") else 0,
            "last_modified_time": _dt(item.get("last_modified_time")),
        }
        rows_to_insert.append(row)

    cur.executemany(sql, rows_to_insert)
    return len(rows_to_insert)


def populate_item_units(cur: pymysql.cursors.DictCursor) -> int:
    """Populate item_units from individual cached detail files in output/cache/items/*.json."""
    item_cache_dir = BASE_DIR / "output" / "cache" / "items"
    detail_files = [f for f in glob.glob(str(item_cache_dir / "*.json")) if not f.endswith("_list.json")]

    if not detail_files:
        print("No item detail files found in cache.")
        return 0

    sql = """
        INSERT INTO item_units (
            unit_conversion_id, item_id, target_unit, conversion_rate
        ) VALUES (
            %(unit_conversion_id)s, %(item_id)s, %(target_unit)s, %(conversion_rate)s
        ) ON DUPLICATE KEY UPDATE
            target_unit = VALUES(target_unit),
            conversion_rate = VALUES(conversion_rate)
    """

    rows_to_insert = []
    seen = set()
    for file_path in detail_files:
        with open(file_path, "r", encoding="utf-8") as f:
            item = json.load(f)
        item_id = item.get("item_id")
        if not item_id:
            continue

        for uc in item.get("unit_conversions", []):
            cid = uc.get("unit_conversion_id")
            if not cid:
                continue
            pair = (item_id, cid)
            if pair in seen:
                continue
            seen.add(pair)
            rows_to_insert.append({
                "unit_conversion_id": _s(cid, 40),
                "item_id": _s(item_id, 40),
                "target_unit": _s(uc.get("target_unit"), 50),
                "conversion_rate": _f(uc.get("conversion_rate"), 1.0),
            })

    if rows_to_insert:
        cur.executemany(sql, rows_to_insert)
    return len(rows_to_insert)


def main() -> None:
    parser = argparse.ArgumentParser(description="Populate raw masters into MariaDB")
    parser.add_argument("--database", default="zoho-koyson", help="Target MariaDB database name")
    args = parser.parse_args()

    print(f"Connecting to database: {args.database} ...")
    conn = get_connection(args.database)

    try:
        with conn.cursor() as cur:
            # Disable FK checks during master bulk loads
            cur.execute("SET FOREIGN_KEY_CHECKS = 0;")

            print("Populating organization ...")
            org_count = populate_organization(cur)
            print(f"  -> {org_count} organization row(s) upserted.")

            print("Populating accounts ...")
            acc_count = populate_accounts(cur)
            print(f"  -> {acc_count} account row(s) upserted.")

            print("Populating items ...")
            item_count = populate_items(cur)
            print(f"  -> {item_count} item row(s) upserted.")

            print("Populating item_units ...")
            units_count = populate_item_units(cur)
            print(f"  -> {units_count} item_unit row(s) upserted.")

            cur.execute("SET FOREIGN_KEY_CHECKS = 1;")
            conn.commit()
            print("Successfully populated all tables and committed transaction.")
    except Exception as e:
        conn.rollback()
        print(f"Error during population: {e}", file=sys.stderr)
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
