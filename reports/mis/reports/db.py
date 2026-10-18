"""MariaDB storage for processed MIS data.

Config (reports/mis/.env, git-ignored):

    MIS_DB_HOST=127.0.0.1  MIS_DB_PORT=3306  MIS_DB_USER=…  MIS_DB_PASSWORD=…  MIS_DB_NAME=zoho-koyson

SCHEMA is the proposed tables in proposal/DB-Schema-Proposed.sql, plus
sync_coverage and the four cashflow tables. Change both copies together.
Dev uses zoho-koyson. Prod stays on nellon_mis until cut-over.

The web viewer reads only from here — it never calls Zoho.
"""

from __future__ import annotations

import json
import os
import time
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Iterator

from dotenv import load_dotenv

from reports import periods

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS `organization` (
        `organization_id`          VARCHAR(40)   NOT NULL,
        `name`                     VARCHAR(255)  NOT NULL DEFAULT '',
        `currency_id`              VARCHAR(40)   NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT '',
        `currency_symbol`          VARCHAR(20)   NOT NULL DEFAULT '',
        `currency_format`          VARCHAR(40)   NOT NULL DEFAULT '',
        `fiscal_year_start_month`  TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '1 to 12. January is 1',
        `time_zone`                VARCHAR(64)   NOT NULL DEFAULT '',
        `country`                  VARCHAR(64)   NOT NULL DEFAULT '',
        `country_code`             VARCHAR(10)   NOT NULL DEFAULT '',
        `is_tax_registered`        TINYINT(1)    NOT NULL DEFAULT 0,
        `synced_at`                DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`organization_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `accounts` (
        `account_id`               VARCHAR(40)   NOT NULL,
        `account_code`             VARCHAR(50)   NOT NULL DEFAULT '',
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `account_type`             VARCHAR(50)   NOT NULL DEFAULT '',
        `parent_account_id`        VARCHAR(40)   NULL DEFAULT NULL,
        `parent_account_name`      VARCHAR(255)  NOT NULL DEFAULT '',
        `group_ledger`             VARCHAR(20)   NOT NULL DEFAULT '' COMMENT 'Group or Ledger',
        `is_active`                TINYINT(1)    NOT NULL DEFAULT 1,
        `pl_bs`                    VARCHAR(10)   NOT NULL DEFAULT '' COMMENT 'PL or BS',
        `category`                 VARCHAR(120)  NOT NULL DEFAULT '',
        `sub_category`             VARCHAR(255)  NOT NULL DEFAULT '',
        `source`                   VARCHAR(20)   NOT NULL DEFAULT '' COMMENT 'override, rule, type, or review',
        `note`                     VARCHAR(500)  NOT NULL DEFAULT '',
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`account_id`),
        KEY `ix_acc_code` (`account_code`),
        KEY `ix_acc_parent` (`parent_account_id`),
        KEY `ix_acc_pl_bs_cat` (`pl_bs`, `category`),
        KEY `ix_acc_type` (`account_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `locations` (
        `location_id`              VARCHAR(40)   NOT NULL,
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `is_primary`               TINYINT(1)    NOT NULL DEFAULT 0,
        `address`                  TEXT          NULL,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`location_id`),
        KEY `ix_loc_name` (`location_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `salespersons` (
        `salesperson_id`           VARCHAR(40)   NOT NULL,
        `salesperson_name`         VARCHAR(255)  NOT NULL DEFAULT '',
        `email`                    VARCHAR(255)  NOT NULL DEFAULT '',
        `phone`                    VARCHAR(50)   NOT NULL DEFAULT '',
        `status`                   VARCHAR(20)   NOT NULL DEFAULT 'active',
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`salesperson_id`),
        KEY `ix_sp_name` (`salesperson_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `customers` (
        `customer_id`              VARCHAR(40)   NOT NULL,
        `contact_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `company_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `customer_sub_type`        VARCHAR(50)   NOT NULL DEFAULT '',
        `status`                   VARCHAR(20)   NOT NULL DEFAULT 'active',
        `email`                    VARCHAR(255)  NOT NULL DEFAULT '',
        `phone`                    VARCHAR(50)   NOT NULL DEFAULT '',
        `tax_treatment`            VARCHAR(50)   NOT NULL DEFAULT '',
        `tax_reg_no`               VARCHAR(50)   NOT NULL DEFAULT '',
        `payment_terms`            INT           NOT NULL DEFAULT 0,
        `payment_terms_label`      VARCHAR(100)  NOT NULL DEFAULT '',
        `credit_limit`             DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`customer_id`),
        KEY `ix_cust_name` (`contact_name`),
        KEY `ix_cust_company` (`company_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `vendors` (
        `vendor_id`                VARCHAR(40)   NOT NULL,
        `contact_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `company_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `status`                   VARCHAR(20)   NOT NULL DEFAULT 'active',
        `email`                    VARCHAR(255)  NOT NULL DEFAULT '',
        `phone`                    VARCHAR(50)   NOT NULL DEFAULT '',
        `tax_treatment`            VARCHAR(50)   NOT NULL DEFAULT '',
        `tax_reg_no`               VARCHAR(50)   NOT NULL DEFAULT '',
        `payment_terms`            INT           NOT NULL DEFAULT 0,
        `payment_terms_label`      VARCHAR(100)  NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`vendor_id`),
        KEY `ix_vend_name` (`contact_name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `vans` (
        `location_id`              VARCHAR(40)   NOT NULL,
        `salesperson_id`           VARCHAR(40)   NULL DEFAULT NULL,
        `voucher_prefix`           VARCHAR(30)   NOT NULL DEFAULT '',
        `cash_account_id`          VARCHAR(40)   NULL DEFAULT NULL,
        `cash_account_name`        VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (`location_id`),
        KEY `ix_vans_salesperson` (`salesperson_id`),
        KEY `ix_vans_cash_account` (`cash_account_id`),
        CONSTRAINT `fk_vans_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE CASCADE,
        CONSTRAINT `fk_vans_salesperson` FOREIGN KEY (`salesperson_id`) REFERENCES `salespersons` (`salesperson_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_vans_cash_account` FOREIGN KEY (`cash_account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `items` (
        `item_id`                  VARCHAR(40)   NOT NULL,
        `name`                     VARCHAR(255)  NOT NULL DEFAULT '',
        `sku`                      VARCHAR(100)  NOT NULL DEFAULT '',
        `status`                   VARCHAR(20)   NOT NULL DEFAULT 'active',
        `item_type`                VARCHAR(50)   NOT NULL DEFAULT '',
        `product_type`             VARCHAR(50)   NOT NULL DEFAULT '',
        `unit`                     VARCHAR(40)   NOT NULL DEFAULT '' COMMENT 'Base unit, e.g. kg, pcs',
        `purchase_rate`            DECIMAL(18,4) NOT NULL DEFAULT 0.0000 COMMENT 'Per base unit',
        `rate`                     DECIMAL(18,4) NOT NULL DEFAULT 0.0000 COMMENT 'Per base unit',
        `account_id`               VARCHAR(40)   NULL DEFAULT NULL,
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `purchase_account_id`      VARCHAR(40)   NULL DEFAULT NULL,
        `purchase_account_name`    VARCHAR(255)  NOT NULL DEFAULT '',
        `tax_id`                   VARCHAR(40)   NOT NULL DEFAULT '',
        `tax_name`                 VARCHAR(100)  NOT NULL DEFAULT '',
        `tax_percentage`           DECIMAL(8,4)  NOT NULL DEFAULT 0.0000,
        `brand`                    VARCHAR(100)  NOT NULL DEFAULT '',
        `track_inventory`          TINYINT(1)    NOT NULL DEFAULT 0,
        `can_be_sold`              TINYINT(1)    NOT NULL DEFAULT 1,
        `can_be_purchased`         TINYINT(1)    NOT NULL DEFAULT 1,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`item_id`),
        KEY `ix_items_name` (`name`),
        KEY `ix_items_sku` (`sku`),
        KEY `ix_items_account` (`account_id`),
        KEY `ix_items_purchase_account` (`purchase_account_id`),
        CONSTRAINT `fk_items_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_items_purchase_account` FOREIGN KEY (`purchase_account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `item_units` (
        `unit_conversion_id`       VARCHAR(40)   NOT NULL,
        `item_id`                  VARCHAR(40)   NOT NULL,
        `target_unit`              VARCHAR(50)   NOT NULL DEFAULT '' COMMENT 'Sale/purchase unit, e.g. 40 KG BAG',
        `conversion_rate`          DECIMAL(18,6) NOT NULL DEFAULT 1.000000 COMMENT 'Base units per target unit',
        PRIMARY KEY (`item_id`, `unit_conversion_id`),
        KEY `ix_item_units_conversion` (`unit_conversion_id`),
        KEY `ix_item_units_item` (`item_id`),
        CONSTRAINT `fk_item_units_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`item_id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `sales_invoices` (
        `invoice_id`               VARCHAR(40)   NOT NULL,
        `invoice_number`           VARCHAR(60)   NOT NULL DEFAULT '',
        `date`                     DATE          NOT NULL,
        `due_date`                 DATE          NULL DEFAULT NULL,
        `status`                   VARCHAR(30)   NOT NULL DEFAULT '',
        `customer_id`              VARCHAR(40)   NULL DEFAULT NULL,
        `customer_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `salesperson_id`           VARCHAR(40)   NULL DEFAULT NULL,
        `salesperson_name`         VARCHAR(255)  NOT NULL DEFAULT '',
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Company header location',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `exchange_rate`            DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `sub_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `discount_total`           DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `shipping_charge`          DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `adjustment`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `total`                    DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `balance`                  DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED after discount, excl tax',
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED sum of sales_lines.cogs',
        `flagged_lines`            INT UNSIGNED  NOT NULL DEFAULT 0,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`invoice_id`),
        KEY `ix_si_date` (`date`),
        KEY `ix_si_number` (`invoice_number`),
        KEY `ix_si_customer` (`customer_id`),
        KEY `ix_si_salesperson` (`salesperson_id`),
        KEY `ix_si_location` (`location_id`),
        KEY `ix_si_status` (`status`),
        CONSTRAINT `fk_si_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_si_salesperson` FOREIGN KEY (`salesperson_id`) REFERENCES `salespersons` (`salesperson_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_si_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `sales_lines` (
        `line_item_id`             VARCHAR(40)   NOT NULL,
        `invoice_id`               VARCHAR(40)   NOT NULL,
        `date`                     DATE          NOT NULL,
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Van or warehouse location on line',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `item_id`                  VARCHAR(40)   NULL DEFAULT NULL,
        `item_name`                VARCHAR(255)  NOT NULL DEFAULT '',
        `sku`                      VARCHAR(100)  NOT NULL DEFAULT '',
        `account_id`               VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Income account',
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `quantity`                 DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `unit`                     VARCHAR(40)   NOT NULL DEFAULT '',
        `base_unit`                VARCHAR(40)   NOT NULL DEFAULT '',
        `conversion_rate`          DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `base_quantity`            DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `rate`                     DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `line_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax',
        `invoice_discount`         DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax prorated share',
        `item_total`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_amount`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax after discounts',
        `purchase_price`           DECIMAL(18,4) NOT NULL DEFAULT 0.0000 COMMENT 'Zoho raw line price',
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Computed COGS in AED',
        `flag`                     VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (`line_item_id`),
        KEY `ix_sl_invoice` (`invoice_id`),
        KEY `ix_sl_date` (`date`),
        KEY `ix_sl_location` (`location_id`),
        KEY `ix_sl_item` (`item_id`),
        KEY `ix_sl_account` (`account_id`),
        CONSTRAINT `fk_sl_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `sales_invoices` (`invoice_id`) ON DELETE CASCADE,
        CONSTRAINT `fk_sl_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_sl_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`item_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_sl_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `purchase_docs` (
        `kind`                     VARCHAR(20)   NOT NULL COMMENT 'bill or purchase_order',
        `doc_id`                   VARCHAR(40)   NOT NULL COMMENT 'bill_id or purchaseorder_id',
        `number`                   VARCHAR(60)   NOT NULL DEFAULT '',
        `date`                     DATE          NOT NULL,
        `due_date`                 DATE          NULL DEFAULT NULL,
        `expected_delivery_date`   DATE          NULL DEFAULT NULL,
        `status`                   VARCHAR(30)   NOT NULL DEFAULT '',
        `billed_status`            VARCHAR(30)   NOT NULL DEFAULT '',
        `received_status`          VARCHAR(30)   NOT NULL DEFAULT '',
        `vendor_id`                VARCHAR(40)   NULL DEFAULT NULL,
        `vendor_name`              VARCHAR(255)  NOT NULL DEFAULT '',
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL,
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `exchange_rate`            DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `reference_number`         VARCHAR(100)  NOT NULL DEFAULT '',
        `sub_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `discount_total`           DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `adjustment`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `total`                    DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `balance`                  DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `amount`                   DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Purchase amount in AED, after discount, excl tax',
        `flagged_lines`            INT UNSIGNED  NOT NULL DEFAULT 0,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`kind`, `doc_id`),
        KEY `ix_pd_date` (`date`),
        KEY `ix_pd_number` (`number`),
        KEY `ix_pd_vendor` (`vendor_id`),
        KEY `ix_pd_location` (`location_id`),
        KEY `ix_pd_status` (`status`),
        CONSTRAINT `fk_pd_vendor` FOREIGN KEY (`vendor_id`) REFERENCES `vendors` (`vendor_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_pd_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `purchase_lines` (
        `line_item_id`             VARCHAR(40)   NOT NULL,
        `kind`                     VARCHAR(20)   NOT NULL,
        `doc_id`                   VARCHAR(40)   NOT NULL,
        `date`                     DATE          NOT NULL,
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL,
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `item_id`                  VARCHAR(40)   NULL DEFAULT NULL,
        `item_name`                VARCHAR(255)  NOT NULL DEFAULT '',
        `sku`                      VARCHAR(100)  NOT NULL DEFAULT '',
        `account_id`               VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Purchase account',
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `quantity`                 DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `unit`                     VARCHAR(40)   NOT NULL DEFAULT '',
        `quantity_received`        DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `quantity_billed`          DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `base_unit`                VARCHAR(40)   NOT NULL DEFAULT '',
        `conversion_rate`          DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `base_quantity`            DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `rate`                     DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `line_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax',
        `doc_discount`             DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax prorated share',
        `item_total`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_amount`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `amount`                   DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax after discounts',
        `purchaseorder_item_id`    VARCHAR(40)   NOT NULL DEFAULT '',
        `flag`                     VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (`line_item_id`),
        KEY `ix_pl_doc` (`kind`, `doc_id`),
        KEY `ix_pl_date` (`date`),
        KEY `ix_pl_location` (`location_id`),
        KEY `ix_pl_item` (`item_id`),
        KEY `ix_pl_account` (`account_id`),
        CONSTRAINT `fk_pl_doc` FOREIGN KEY (`kind`, `doc_id`) REFERENCES `purchase_docs` (`kind`, `doc_id`) ON DELETE CASCADE,
        CONSTRAINT `fk_pl_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_pl_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`item_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_pl_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `credit_notes` (
        `creditnote_id`            VARCHAR(40)   NOT NULL,
        `creditnote_number`        VARCHAR(60)   NOT NULL DEFAULT '',
        `date`                     DATE          NOT NULL,
        `status`                   VARCHAR(30)   NOT NULL DEFAULT '',
        `customer_id`              VARCHAR(40)   NULL DEFAULT NULL,
        `customer_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `salesperson_id`           VARCHAR(40)   NULL DEFAULT NULL,
        `salesperson_name`         VARCHAR(255)  NOT NULL DEFAULT '',
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Company header location',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `invoice_id`               VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Referenced invoice',
        `invoice_number`           VARCHAR(60)   NOT NULL DEFAULT '',
        `reference_number`         VARCHAR(100)  NOT NULL DEFAULT '',
        `reason`                   VARCHAR(255)  NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `exchange_rate`            DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `sub_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `discount_total`           DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `adjustment`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `total`                    DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `balance`                  DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED reducing revenue',
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED reducing COGS',
        `flagged_lines`            INT UNSIGNED  NOT NULL DEFAULT 0,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`creditnote_id`),
        KEY `ix_cn_date` (`date`),
        KEY `ix_cn_number` (`creditnote_number`),
        KEY `ix_cn_customer` (`customer_id`),
        KEY `ix_cn_salesperson` (`salesperson_id`),
        KEY `ix_cn_location` (`location_id`),
        KEY `ix_cn_invoice` (`invoice_id`),
        KEY `ix_cn_status` (`status`),
        CONSTRAINT `fk_cn_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_cn_salesperson` FOREIGN KEY (`salesperson_id`) REFERENCES `salespersons` (`salesperson_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_cn_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_cn_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `sales_invoices` (`invoice_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `credit_note_lines` (
        `line_item_id`             VARCHAR(40)   NOT NULL,
        `creditnote_id`            VARCHAR(40)   NOT NULL,
        `invoice_id`               VARCHAR(40)   NULL DEFAULT NULL,
        `invoice_item_id`          VARCHAR(40)   NULL DEFAULT NULL,
        `date`                     DATE          NOT NULL,
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Van or warehouse location on line',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `item_id`                  VARCHAR(40)   NULL DEFAULT NULL,
        `item_name`                VARCHAR(255)  NOT NULL DEFAULT '',
        `sku`                      VARCHAR(100)  NOT NULL DEFAULT '',
        `account_id`               VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Income account',
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `quantity`                 DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `unit`                     VARCHAR(40)   NOT NULL DEFAULT '',
        `base_unit`                VARCHAR(40)   NOT NULL DEFAULT '',
        `conversion_rate`          DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `base_quantity`            DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `rate`                     DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `line_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax',
        `note_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax prorated share',
        `item_total`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_amount`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED reducing revenue',
        `purchase_price`           DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED reducing COGS',
        `flag`                     VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (`line_item_id`),
        KEY `ix_cnl_cn` (`creditnote_id`),
        KEY `ix_cnl_date` (`date`),
        KEY `ix_cnl_location` (`location_id`),
        KEY `ix_cnl_item` (`item_id`),
        KEY `ix_cnl_account` (`account_id`),
        KEY `ix_cnl_inv` (`invoice_id`),
        CONSTRAINT `fk_cnl_cn` FOREIGN KEY (`creditnote_id`) REFERENCES `credit_notes` (`creditnote_id`) ON DELETE CASCADE,
        CONSTRAINT `fk_cnl_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_cnl_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`item_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_cnl_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `debit_notes` (
        `debit_note_id`            VARCHAR(40)   NOT NULL,
        `debit_note_number`        VARCHAR(60)   NOT NULL DEFAULT '',
        `date`                     DATE          NOT NULL,
        `due_date`                 DATE          NULL DEFAULT NULL,
        `status`                   VARCHAR(30)   NOT NULL DEFAULT '',
        `customer_id`              VARCHAR(40)   NULL DEFAULT NULL,
        `customer_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `salesperson_id`           VARCHAR(40)   NULL DEFAULT NULL,
        `salesperson_name`         VARCHAR(255)  NOT NULL DEFAULT '',
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Company header location',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `reference_invoice_id`     VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Original invoice adjusted',
        `reference_invoice_number` VARCHAR(60)   NOT NULL DEFAULT '',
        `reference_number`         VARCHAR(100)  NOT NULL DEFAULT '',
        `reason`                   VARCHAR(255)  NOT NULL DEFAULT '',
        `currency_code`            VARCHAR(10)   NOT NULL DEFAULT 'AED',
        `exchange_rate`            DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `sub_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `discount_total`           DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_total`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `shipping_charge`          DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `adjustment`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `total`                    DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `balance`                  DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED increasing revenue',
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED increasing COGS',
        `flagged_lines`            INT UNSIGNED  NOT NULL DEFAULT 0,
        `last_modified_time`       DATETIME      NULL DEFAULT NULL,
        PRIMARY KEY (`debit_note_id`),
        KEY `ix_dn_date` (`date`),
        KEY `ix_dn_number` (`debit_note_number`),
        KEY `ix_dn_customer` (`customer_id`),
        KEY `ix_dn_salesperson` (`salesperson_id`),
        KEY `ix_dn_location` (`location_id`),
        KEY `ix_dn_ref_invoice` (`reference_invoice_id`),
        KEY `ix_dn_status` (`status`),
        CONSTRAINT `fk_dn_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_dn_salesperson` FOREIGN KEY (`salesperson_id`) REFERENCES `salespersons` (`salesperson_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_dn_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_dn_ref_invoice` FOREIGN KEY (`reference_invoice_id`) REFERENCES `sales_invoices` (`invoice_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `debit_note_lines` (
        `line_item_id`             VARCHAR(40)   NOT NULL,
        `debit_note_id`            VARCHAR(40)   NOT NULL,
        `date`                     DATE          NOT NULL,
        `location_id`              VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Van or warehouse location on line',
        `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
        `item_id`                  VARCHAR(40)   NULL DEFAULT NULL,
        `item_name`                VARCHAR(255)  NOT NULL DEFAULT '',
        `sku`                      VARCHAR(100)  NOT NULL DEFAULT '',
        `account_id`               VARCHAR(40)   NULL DEFAULT NULL COMMENT 'Income account',
        `account_name`             VARCHAR(255)  NOT NULL DEFAULT '',
        `quantity`                 DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `unit`                     VARCHAR(40)   NOT NULL DEFAULT '',
        `base_unit`                VARCHAR(40)   NOT NULL DEFAULT '',
        `conversion_rate`          DECIMAL(18,6) NOT NULL DEFAULT 1.000000,
        `base_quantity`            DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `rate`                     DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `line_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax',
        `note_discount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED excl tax prorated share',
        `item_total`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `tax_amount`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `net_sales`                DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED increasing revenue',
        `purchase_price`           DECIMAL(18,4) NOT NULL DEFAULT 0.0000,
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED increasing COGS',
        `flag`                     VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (`line_item_id`),
        KEY `ix_dnl_dn` (`debit_note_id`),
        KEY `ix_dnl_date` (`date`),
        KEY `ix_dnl_location` (`location_id`),
        KEY `ix_dnl_item` (`item_id`),
        KEY `ix_dnl_account` (`account_id`),
        CONSTRAINT `fk_dnl_dn` FOREIGN KEY (`debit_note_id`) REFERENCES `debit_notes` (`debit_note_id`) ON DELETE CASCADE,
        CONSTRAINT `fk_dnl_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_dnl_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`item_id`) ON DELETE SET NULL,
        CONSTRAINT `fk_dnl_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS `gl_journals` (
        `account_id`                  VARCHAR(40)   NOT NULL,
        `categorized_transaction_id`  VARCHAR(40)   NOT NULL,
        `account_name`                VARCHAR(255)  NOT NULL DEFAULT '',
        `account_code`                VARCHAR(50)   NOT NULL DEFAULT '',
        `transaction_id`              VARCHAR(40)   NOT NULL DEFAULT '',
        `transaction_type`            VARCHAR(80)   NOT NULL DEFAULT '',
        `transaction_type_formatted`  VARCHAR(100)  NOT NULL DEFAULT '',
        `transaction_date`            DATE          NOT NULL,
        `entry_number`                VARCHAR(60)   NOT NULL DEFAULT '',
        `reference_number`            VARCHAR(100)  NOT NULL DEFAULT '',
        `customer_id`                 VARCHAR(40)   NOT NULL DEFAULT '',
        `payee`                       VARCHAR(255)  NOT NULL DEFAULT '',
        `description`                 TEXT          NULL,
        `debit_or_credit`             VARCHAR(10)   NOT NULL DEFAULT '',
        `debit_amount`                DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `credit_amount`               DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `amount`                      DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'debit_amount - credit_amount (debit-positive)',
        `fcy_debit_amount`            DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `fcy_credit_amount`           DECIMAL(18,2) NOT NULL DEFAULT 0.00,
        `currency_id`                 VARCHAR(40)   NOT NULL DEFAULT '',
        `currency_code`               VARCHAR(10)   NOT NULL DEFAULT '',
        `offset_account_name`         VARCHAR(255)  NOT NULL DEFAULT '',
        `raw_json`                    LONGTEXT      NULL,
        `fetched_at`                  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`account_id`, `categorized_transaction_id`),
        KEY `ix_glj_date` (`transaction_date`),
        KEY `ix_glj_trans` (`transaction_id`),
        KEY `ix_glj_type` (`transaction_type`),
        KEY `ix_glj_entry` (`entry_number`),
        CONSTRAINT `fk_glj_account` FOREIGN KEY (`account_id`) REFERENCES `accounts` (`account_id`) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_runs (
        id                BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        as_of             DATE         NOT NULL,
        organization_id   VARCHAR(32)  NOT NULL DEFAULT '',
        organization_name VARCHAR(200) NOT NULL DEFAULT '',
        currency_code     VARCHAR(8)   NOT NULL DEFAULT '',
        opening           DECIMAL(18,2) NOT NULL DEFAULT 0,
        ar_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        ap_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        po_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        so_total          DECIMAL(18,2) NOT NULL DEFAULT 0,
        counts_json       TEXT         NOT NULL,
        notes             TEXT         NOT NULL,
        api_calls         INT          NOT NULL DEFAULT 0,
        source            VARCHAR(255) NOT NULL DEFAULT '',
        created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY ix_cf_asof (as_of)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_accounts (
        run_id       BIGINT UNSIGNED NOT NULL,
        line_no      INT UNSIGNED  NOT NULL,
        account_name VARCHAR(255)  NOT NULL,
        account_type VARCHAR(20)   NOT NULL,
        balance      DECIMAL(18,2) NOT NULL,
        PRIMARY KEY (run_id, line_no),
        CONSTRAINT fk_cfa_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_events (
        run_id      BIGINT UNSIGNED NOT NULL,
        line_no     INT UNSIGNED  NOT NULL,
        cash_date   DATE          NOT NULL,
        source_date DATE          NULL,
        overdue     TINYINT(1)    NOT NULL DEFAULT 0,
        kind        VARCHAR(8)    NOT NULL,
        amount      DECIMAL(18,2) NOT NULL,
        party       VARCHAR(255)  NOT NULL DEFAULT '',
        number      VARCHAR(60)   NOT NULL DEFAULT '',
        label       VARCHAR(120)  NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        KEY ix_cfe_date (run_id, cash_date),
        CONSTRAINT fk_cfe_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS cashflow_unscheduled (
        run_id  BIGINT UNSIGNED NOT NULL,
        line_no INT UNSIGNED  NOT NULL,
        kind    VARCHAR(8)    NOT NULL,
        number  VARCHAR(60)   NOT NULL DEFAULT '',
        party   VARCHAR(255)  NOT NULL DEFAULT '',
        amount  DECIMAL(18,2) NOT NULL,
        reason  VARCHAR(255)  NOT NULL DEFAULT '',
        PRIMARY KEY (run_id, line_no),
        CONSTRAINT fk_cfu_run FOREIGN KEY (run_id) REFERENCES cashflow_runs (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS sync_coverage (
        dataset   VARCHAR(40) NOT NULL,
        from_date DATE        NOT NULL,
        to_date   DATE        NOT NULL,
        synced_at DATETIME    NOT NULL,
        source    VARCHAR(20) NOT NULL DEFAULT '',
        PRIMARY KEY (dataset, from_date)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
]

MARGIN_DB_COLUMNS = [
    "month", "date", "invoice_id", "invoice_number", "customer_name", "salesperson_name", "van",
    "item_id", "item_name", "sku", "unit", "quantity", "conversion_rate", "base_quantity", "rate",
    "gross_amount", "line_discount", "invoice_discount", "net_sales", "cost_rate", "cost_of_sales",
    "gross_margin", "flag", "cost_source",
]
MARGIN_INVOICE_DB_COLUMNS = [
    "invoice_id", "invoice_number", "month", "date", "due_date", "status", "customer_id", "customer_name",
    "salesperson_name", "van", "currency_code", "exchange_rate", "sub_total", "discount_total", "tax_total",
    "total", "balance", "line_count", "base_quantity", "net_sales", "cost_of_sales", "gross_margin",
    "flagged_lines", "cost_source",
]
# Report rows (CSV / JSON / UI) call it `cost`; the tables call it `cost_of_sales`.
_ROW_KEY = {"cost_of_sales": "cost"}
_DATE_COLUMNS = {"date", "due_date"}
MARGIN_DIMENSIONS = {
    "item": "l.item_name",
    "customer": "i.customer_name",
    "salesperson": "i.salesperson_name",
    "van": "CASE WHEN v.location_id IS NULL THEN '(warehouse)' ELSE l.location_name END",
    "location": "l.location_name",
}
PURCHASE_DB_COLUMNS = [
    "month", "date", "kind", "number", "vendor_name", "status", "item_id", "item_name", "sku", "unit",
    "quantity", "rate", "amount", "doc_id",
]
PURCHASE_DIMENSIONS = {"vendor": "d.vendor_name", "item": "pl.item_name", "kind": "pl.kind"}
PURCHASE_MEASURES = {"amount", "quantity", "documents"}
MARGIN_MEASURES = {"net_sales", "cost", "gross_margin", "base_quantity", "gm_pct"}

CATEGORY_DB_COLUMNS = [
    "account_id", "account_code", "ledger_name", "entity_name", "group_ledger", "pl_bs", "category",
    "sub_category", "source", "note", "account_type", "parent_account_name", "path",
    "current_balance", "is_active",
]


def config() -> dict[str, Any] | None:
    """DB settings from env, or None when MIS_DB_NAME isn't configured."""
    name = os.getenv("MIS_DB_NAME")
    if not name:
        return None
    return {
        "host": os.getenv("MIS_DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("MIS_DB_PORT", "3306")),
        "user": os.getenv("MIS_DB_USER", ""),
        "password": os.getenv("MIS_DB_PASSWORD", ""),
        "database": name,
    }


def enabled() -> bool:
    return config() is not None


@contextmanager
def connect(*, database: bool = True) -> Iterator[Any]:
    import pymysql

    cfg = config()
    if cfg is None:
        raise RuntimeError("MariaDB not configured — set MIS_DB_* in reports/mis/.env")
    if not database:
        cfg = {k: v for k, v in cfg.items() if k != "database"}
    conn = pymysql.connect(**cfg, charset="utf8mb4", autocommit=False,
                           cursorclass=pymysql.cursors.DictCursor)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_schema() -> str:
    """Create the database (if missing) and all tables. Idempotent."""
    cfg = config()
    if cfg is None:
        raise RuntimeError("MariaDB not configured — set MIS_DB_* in reports/mis/.env")
    name = cfg["database"]
    # Hyphen is allowed so `zoho-koyson` passes. The name is always backtick-quoted.
    if not name.replace("_", "").replace("-", "").isalnum():
        raise ValueError(f"unsafe database name {name!r}")
    with connect(database=False) as conn, conn.cursor() as cur:
        cur.execute(
            f"CREATE DATABASE IF NOT EXISTS `{name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
        )
    with connect() as conn, conn.cursor() as cur:
        for ddl in SCHEMA:
            cur.execute(ddl)
    return name


def _migrate_margin(cur: Any) -> None:
    """Bring a pre-header database up to date, then give old runs their invoice header rows. Idempotent."""
    cur.execute("SELECT COLUMN_NAME FROM information_schema.COLUMNS "
                "WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='margin_lines'")
    cols = {r["COLUMN_NAME"] for r in cur.fetchall()}
    if "cost" in cols:
        cur.execute("ALTER TABLE margin_lines CHANGE COLUMN cost cost_of_sales DECIMAL(18,2) NOT NULL DEFAULT 0")
    if "cost_source" not in cols:
        cur.execute("ALTER TABLE margin_lines ADD COLUMN cost_source VARCHAR(20) NOT NULL DEFAULT ''")
    cur.execute("SHOW INDEX FROM margin_lines WHERE Key_name='ix_margin_invoice'")
    if not cur.fetchall():
        cur.execute("ALTER TABLE margin_lines ADD KEY ix_margin_invoice (run_id, invoice_id)")
    cur.execute("""SELECT DISTINCT l.run_id FROM margin_lines l
                   LEFT JOIN margin_invoices i ON i.run_id=l.run_id WHERE i.run_id IS NULL""")
    for r in cur.fetchall():
        _backfill_invoice_headers(cur, r["run_id"])
    cur.execute("SELECT 1 FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA=DATABASE() "
                "AND TABLE_NAME='margin_lines' AND CONSTRAINT_NAME='fk_ml_invoice'")
    if not cur.fetchall():
        cur.execute("""INSERT INTO margin_invoices (run_id, invoice_id, month)
                       SELECT run_id, invoice_id, MIN(month) FROM margin_lines l
                       WHERE NOT EXISTS (SELECT 1 FROM margin_invoices i
                                         WHERE i.run_id=l.run_id AND i.invoice_id=l.invoice_id)
                       GROUP BY run_id, invoice_id""")
        cur.execute("ALTER TABLE margin_lines ADD CONSTRAINT fk_ml_invoice FOREIGN KEY (run_id, invoice_id) "
                    "REFERENCES margin_invoices (run_id, invoice_id) ON DELETE CASCADE")


def _backfill_invoice_headers(cur: Any, run_id: int) -> None:
    """Header rows for a run saved before headers existed: sums of its lines (Zoho-only fields stay blank)."""
    cur.execute(
        """INSERT INTO margin_invoices
             (run_id, invoice_id, invoice_number, month, date, customer_name, salesperson_name, van,
              line_count, base_quantity, net_sales, cost_of_sales, gross_margin, flagged_lines, cost_source)
           SELECT run_id, invoice_id, MAX(invoice_number), MIN(month), MIN(date), MAX(customer_name),
                  MAX(salesperson_name), MAX(van), COUNT(*), SUM(base_quantity), SUM(net_sales),
                  SUM(cost_of_sales), SUM(gross_margin), SUM(flag <> ''),
                  CASE WHEN SUM(cost_source='booked')=COUNT(*) THEN 'booked'
                       WHEN SUM(cost_source='purchase_rate')=COUNT(*) THEN 'purchase_rate'
                       WHEN MAX(cost_source)='' THEN '' ELSE 'mixed' END
           FROM margin_lines WHERE run_id=%s GROUP BY run_id, invoice_id""",
        (run_id,),
    )


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------


def _new_run(cur: Any, kind: str, summary: dict[str, Any], months: list[str], source: str) -> int:
    cur.execute(
        """INSERT INTO report_runs
           (kind, organization_id, organization_name, currency_code, from_date, to_date,
            fiscal_year_start, months, summary, source)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        (
            kind,
            str(summary.get("organization_id") or ""),
            summary.get("organization_name") or "",
            summary.get("currency_code") or "",
            summary["from_date"],
            summary["to_date"],
            summary.get("fiscal_year_start") or None,
            json.dumps(months),
            json.dumps(summary),
            source[:255],
        ),
    )
    return int(cur.lastrowid)


def save_financials_run(
    tb_rows: list[dict[str, Any]],
    summary: dict[str, Any],
    statements: list[Any],
    *,
    source: str,
) -> int:
    months = list(summary.get("months") or [])
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "financials", summary, months, source)
        cur.executemany(
            """INSERT INTO tb_accounts
               (run_id, account_id, account_code, account_name, account_type, parent_account_name,
                group_ledger, pl_bs, category, sub_category, category_source,
                opening, period_debit, period_credit, movement, closing)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            [
                (run_id, r["account_id"], r.get("account_code", ""), r.get("account_name", ""),
                 r.get("account_type", ""), r.get("parent_account_name", ""), r.get("group_ledger", ""),
                 r.get("pl_bs", ""), r.get("category", ""), r.get("sub_category", ""),
                 r.get("category_source", ""), r.get("opening", 0), r.get("period_debit", 0),
                 r.get("period_credit", 0), r.get("movement", 0), r.get("closing", 0))
                for r in tb_rows
            ],
        )
        cur.executemany(
            "INSERT INTO tb_monthly (run_id, account_id, month, amount) VALUES (%s,%s,%s,%s)",
            [(run_id, r["account_id"], m, r.get(m, 0) or 0) for r in tb_rows for m in months
             if abs(float(r.get(m, 0) or 0)) >= 0.005],
        )
        line_rows, value_rows = [], []
        for st in statements:
            for line_no, ln in enumerate(st.lines, 1):
                line_rows.append((run_id, st.name, line_no, ln.label[:255], ln.kind))
                for order, col in enumerate(st.columns):
                    if col in ln.values:
                        value_rows.append((run_id, st.name, line_no, col, order, ln.values[col]))
        cur.executemany(
            "INSERT INTO statement_lines (run_id, statement, line_no, label, kind) VALUES (%s,%s,%s,%s,%s)",
            line_rows,
        )
        cur.executemany(
            """INSERT INTO statement_values (run_id, statement, line_no, col, col_order, amount)
               VALUES (%s,%s,%s,%s,%s,%s)""",
            value_rows,
        )
    return run_id


def _db_value(r: dict[str, Any], col: str) -> Any:
    v = r.get(_ROW_KEY.get(col, col))
    if col in _DATE_COLUMNS:
        return v or None
    return "" if v is None else v


def save_margin_run(rows: list[dict[str, Any]], summary: dict[str, Any], *, source: str,
                    invoices: list[dict[str, Any]] | None = None) -> int:
    """Store a margin run: invoice header rows in margin_invoices, line rows in margin_lines.

    `invoices` (header rows) may be omitted for older JSON files; they are then rebuilt from the lines.
    """
    months = sorted({r["month"] for r in rows if r.get("month")})
    cols = ", ".join(MARGIN_DB_COLUMNS)
    marks = ", ".join(["%s"] * (len(MARGIN_DB_COLUMNS) + 2))
    icols = ", ".join(MARGIN_INVOICE_DB_COLUMNS)
    imarks = ", ".join(["%s"] * (len(MARGIN_INVOICE_DB_COLUMNS) + 1))
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "margin", summary, months, source)
        if not invoices:  # headers are rebuilt from the lines below, so lines go in first
            cur.execute("SET FOREIGN_KEY_CHECKS=0")
        if invoices:
            cur.executemany(
                f"INSERT INTO margin_invoices (run_id, {icols}) VALUES ({imarks})",
                [(run_id, *[_db_value(r, c) for c in MARGIN_INVOICE_DB_COLUMNS]) for r in invoices],
            )
        cur.executemany(
            f"INSERT INTO margin_lines (run_id, line_no, {cols}) VALUES ({marks})",
            [(run_id, n, *[_db_value(r, c) for c in MARGIN_DB_COLUMNS]) for n, r in enumerate(rows, 1)],
        )
        if not invoices:
            _backfill_invoice_headers(cur, run_id)
            cur.execute("SET FOREIGN_KEY_CHECKS=1")
    return run_id


def save_purchases_run(rows: list[dict[str, Any]], summary: dict[str, Any], *, source: str) -> int:
    months = sorted({r["month"] for r in rows if r.get("month")})
    cols = ", ".join(PURCHASE_DB_COLUMNS)
    marks = ", ".join(["%s"] * (len(PURCHASE_DB_COLUMNS) + 2))
    with connect() as conn, conn.cursor() as cur:
        run_id = _new_run(cur, "purchases", summary, months, source)
        cur.executemany(
            f"INSERT INTO purchase_lines (run_id, line_no, {cols}) VALUES ({marks})",
            [
                (run_id, n, *[(r.get(c) or None) if c == "date" else r.get(c, "") for c in PURCHASE_DB_COLUMNS])
                for n, r in enumerate(rows, 1)
            ],
        )
    return run_id


# ---------------------------------------------------------------------------
# Dated store: range-replace writes (the Zoho list for a date range is authoritative)
# ---------------------------------------------------------------------------

PURCHASE_KINDS = ("bill", "purchase_order")
COVERAGE_DATASETS = {"sales", "purchases"}
_SALES_HEADER_SUMS = ("base_quantity", "net_sales", "cost", "gross_margin")
_ZOHO_ONLY_TOTALS = ("sub_total", "discount_total", "tax_total", "total", "balance")


def _in_chunks(values: list[Any], size: int = 500) -> Iterator[list[Any]]:
    for i in range(0, len(values), size):
        yield values[i:i + size]


def _set_coverage(cur: Any, dataset: str, start: date, end: date, source: str, synced_at: Any) -> None:
    """Record [start, end] as loaded; older rows it overlaps are trimmed (their outside parts survive)."""
    cur.execute("SELECT from_date, to_date, synced_at, source FROM sync_coverage "
                "WHERE dataset=%s AND from_date<=%s AND to_date>=%s", (dataset, end, start))
    keep = []
    for r in cur.fetchall():
        cur.execute("DELETE FROM sync_coverage WHERE dataset=%s AND from_date=%s", (dataset, r["from_date"]))
        if r["from_date"] < start:
            keep.append((r["from_date"], start - timedelta(days=1), r["synced_at"], r["source"]))
        if r["to_date"] > end:
            keep.append((end + timedelta(days=1), r["to_date"], r["synced_at"], r["source"]))
    cur.executemany("INSERT INTO sync_coverage (dataset, from_date, to_date, synced_at, source) "
                    "VALUES (%s,%s,%s,%s,%s)",
                    [(dataset, *k) for k in keep] + [(dataset, start, end, synced_at, source[:20])])


def _headers_from_lines(rows: list[dict[str, Any]], known: set[str]) -> list[dict[str, Any]]:
    """Invoice headers for lines whose invoice has none (older JSON files): sums of the lines."""
    out: dict[str, dict[str, Any]] = {}
    for r in rows:
        iid = str(r.get("invoice_id") or "")
        if iid in known:
            continue
        h = out.setdefault(iid, {"invoice_id": iid, "line_count": 0, "flagged_lines": 0, "_src": set(),
                                 "exchange_rate": 1, **dict.fromkeys(_ZOHO_ONLY_TOTALS, 0),
                                 **{k: r.get(k) for k in ("invoice_number", "month", "date", "customer_name",
                                                          "salesperson_name", "van")},
                                 **{k: 0.0 for k in _SALES_HEADER_SUMS}})
        h["line_count"] += 1
        h["flagged_lines"] += 1 if r.get("flag") else 0
        h["_src"].add(r.get("cost_source") or "")
        for k in _SALES_HEADER_SUMS:
            h[k] += float(r.get(k) or 0)
    for h in out.values():
        src = h.pop("_src")
        h["cost_source"] = src.pop() if len(src) == 1 else "mixed"
    return list(out.values())


def _replace_sales(cur: Any, start: date, end: date, invoices: list[dict[str, Any]],
                   rows: list[dict[str, Any]], source: str, synced_at: Any) -> dict[str, int]:
    invoices = list(invoices or [])
    invoices += _headers_from_lines(rows, {str(i["invoice_id"]) for i in invoices})
    ids = [str(i["invoice_id"]) for i in invoices]
    deleted = cur.execute("DELETE FROM sales_invoices WHERE date BETWEEN %s AND %s", (start, end))
    for chunk in _in_chunks(ids):  # invoices whose date moved into this range from elsewhere
        deleted += cur.execute(f"DELETE FROM sales_invoices WHERE invoice_id IN ({','.join(['%s'] * len(chunk))})",
                               chunk)
    icols = ", ".join(MARGIN_INVOICE_DB_COLUMNS)
    cur.executemany(
        f"INSERT INTO sales_invoices ({icols}, fetched_at) VALUES ({', '.join(['%s'] * (len(MARGIN_INVOICE_DB_COLUMNS) + 1))})",
        [(*[_db_value(r, c) for c in MARGIN_INVOICE_DB_COLUMNS], synced_at) for r in invoices],
    )
    line_no: dict[str, int] = {}
    values = []
    for r in rows:
        iid = str(r.get("invoice_id") or "")
        line_no[iid] = line_no.get(iid, 0) + 1
        values.append((line_no[iid], *[_db_value(r, c) for c in MARGIN_DB_COLUMNS]))
    cols = ", ".join(MARGIN_DB_COLUMNS)
    cur.executemany(
        f"INSERT INTO sales_lines (line_no, {cols}) VALUES ({', '.join(['%s'] * (len(MARGIN_DB_COLUMNS) + 1))})",
        values,
    )
    _set_coverage(cur, "sales", start, end, source, synced_at)
    return {"invoices": len(invoices), "lines": len(values), "replaced_invoices": deleted}


def _purchase_datasets(kinds: list[str] | tuple[str, ...]) -> list[str]:
    return ["purchases"] if set(kinds) == set(PURCHASE_KINDS) else [f"purchases:{k}" for k in kinds]


def _replace_purchases(cur: Any, start: date, end: date, rows: list[dict[str, Any]],
                       kinds: list[str] | tuple[str, ...], source: str, synced_at: Any) -> dict[str, int]:
    """Only the given kinds are replaced, so `--kind bill` leaves purchase orders alone."""
    if not kinds or set(kinds) - set(PURCHASE_KINDS):
        raise ValueError(f"kinds must be from {PURCHASE_KINDS}")
    marks = ",".join(["%s"] * len(kinds))
    deleted = cur.execute(f"DELETE FROM purchase_doc_lines WHERE kind IN ({marks}) AND date BETWEEN %s AND %s",
                          (*kinds, start, end))
    for kind in kinds:
        ids = sorted({str(r["doc_id"]) for r in rows if r.get("kind") == kind})
        for chunk in _in_chunks(ids):
            deleted += cur.execute(
                f"DELETE FROM purchase_doc_lines WHERE kind=%s AND doc_id IN ({','.join(['%s'] * len(chunk))})",
                (kind, *chunk))
    line_no: dict[tuple[str, str], int] = {}
    values = []
    for r in rows:
        if r.get("kind") not in kinds:
            continue
        key = (r["kind"], str(r.get("doc_id") or ""))
        line_no[key] = line_no.get(key, 0) + 1
        values.append((line_no[key], *[(r.get(c) or None) if c == "date" else r.get(c, "")
                                       for c in PURCHASE_DB_COLUMNS], synced_at))
    cols = ", ".join(PURCHASE_DB_COLUMNS)
    cur.executemany(
        f"INSERT INTO purchase_doc_lines (line_no, {cols}, fetched_at) "
        f"VALUES ({', '.join(['%s'] * (len(PURCHASE_DB_COLUMNS) + 2))})",
        values,
    )
    for ds in _purchase_datasets(kinds):
        _set_coverage(cur, ds, start, end, source, synced_at)
    return {"documents": len(line_no), "lines": len(values), "replaced_lines": deleted}


def sync_sales(from_date: Any, to_date: Any, invoices: list[dict[str, Any]] | None,
               rows: list[dict[str, Any]], *, source: str) -> dict[str, int]:
    """Make the dated sales tables hold exactly this fetch for [from_date, to_date] (one transaction).

    `source` is 'zoho' or 'cache' (an offline run never learns about deleted invoices)."""
    start, end = periods.parse_range(from_date, to_date)
    with connect() as conn, conn.cursor() as cur:
        return _replace_sales(cur, start, end, invoices or [], rows, source, datetime.now())


def sync_purchases(from_date: Any, to_date: Any, rows: list[dict[str, Any]], *, source: str,
                   kinds: list[str] | None = None) -> dict[str, int]:
    start, end = periods.parse_range(from_date, to_date)
    with connect() as conn, conn.cursor() as cur:
        return _replace_purchases(cur, start, end, rows, kinds or PURCHASE_KINDS, source, datetime.now())


def run_purchase_kinds(summary: dict[str, Any]) -> list[str]:
    kinds = summary.get("kinds") or list(summary.get("documents") or {}) or list(PURCHASE_KINDS)
    return [k for k in PURCHASE_KINDS if k in kinds]


def migrate_runs_to_dated() -> list[dict[str, Any]]:
    """Replay stored margin / purchases runs into the dated tables, oldest first, so the newest run wins
    where runs overlap. No Zoho calls; idempotent (replaying again gives the same tables)."""
    out = []
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT id, kind, from_date, to_date, summary, created_at FROM report_runs "
                    "WHERE kind IN ('margin', 'purchases') ORDER BY created_at, id")
        for run in cur.fetchall():
            start, end, rid = run["from_date"], run["to_date"], run["id"]
            if run["kind"] == "margin":
                cur.execute("SELECT * FROM margin_invoices WHERE run_id=%s", (rid,))
                invoices = cur.fetchall()
                cur.execute("SELECT * FROM margin_lines WHERE run_id=%s ORDER BY invoice_id, line_no", (rid,))
                lines = cur.fetchall()
                for r in invoices + lines:
                    r["cost"] = r.pop("cost_of_sales")
                res = _replace_sales(cur, start, end, invoices, lines, "migrated", run["created_at"])
            else:
                cur.execute("SELECT * FROM purchase_lines WHERE run_id=%s ORDER BY line_no", (rid,))
                kinds = run_purchase_kinds(json.loads(run["summary"] or "{}"))
                res = _replace_purchases(cur, start, end, cur.fetchall(), kinds, "migrated", run["created_at"])
            out.append({"run_id": rid, "kind": run["kind"], "from": str(start), "to": str(end), **res})
    return out


def _sql_date(value: Any) -> str | None:
    text = str(value or "")[:10]
    return text if len(text) == 10 and text[4] == "-" else None


def save_cashflow_run(
    payload: dict[str, Any],
    *,
    organization_id: str,
    api_calls: int,
    source: str,
) -> int:
    """Store one forecast. Returns cashflow_runs.id."""
    totals = payload.get("totals") or {}
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """INSERT INTO cashflow_runs
               (as_of, organization_id, organization_name, currency_code, opening,
                ar_total, ap_total, po_total, so_total, counts_json, notes, api_calls, source)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            (
                payload["as_of"],
                organization_id,
                payload.get("organization") or "",
                payload.get("currency") or "",
                payload.get("opening") or 0,
                totals.get("ar") or 0,
                totals.get("ap") or 0,
                totals.get("po") or 0,
                totals.get("so") or 0,
                json.dumps(payload.get("counts") or {}),
                json.dumps(payload.get("notes") or []),
                api_calls,
                source[:255],
            ),
        )
        run_id = int(cur.lastrowid)
        accounts = [
            (run_id, n, (row.get("name") or "")[:255], (row.get("type") or "")[:20], row.get("balance") or 0)
            for n, row in enumerate(payload.get("accounts") or [], 1)
        ]
        if accounts:
            cur.executemany(
                """INSERT INTO cashflow_accounts (run_id, line_no, account_name, account_type, balance)
                   VALUES (%s,%s,%s,%s,%s)""",
                accounts,
            )
        events = [
            (
                run_id, n, row["date"], _sql_date(row.get("source_date")), 1 if row.get("overdue") else 0,
                (row.get("kind") or "")[:8], row.get("amount") or 0,
                (row.get("party") or "")[:255], (row.get("number") or "")[:60], (row.get("label") or "")[:120],
            )
            for n, row in enumerate(payload.get("events") or [], 1)
        ]
        if events:
            cur.executemany(
                """INSERT INTO cashflow_events
                   (run_id, line_no, cash_date, source_date, overdue, kind, amount, party, number, label)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                events,
            )
        pending = [
            (
                run_id, n, (row.get("kind") or "")[:8], (row.get("number") or "")[:60],
                (row.get("party") or "")[:255], row.get("amount") or 0, (row.get("reason") or "")[:255],
            )
            for n, row in enumerate(payload.get("unscheduled") or [], 1)
        ]
        if pending:
            cur.executemany(
                """INSERT INTO cashflow_unscheduled (run_id, line_no, kind, number, party, amount, reason)
                   VALUES (%s,%s,%s,%s,%s,%s,%s)""",
                pending,
            )
    return run_id


def _account_path(by_id: dict[str, dict[str, Any]], row: dict[str, Any]) -> str:
    """Ancestor names from the root down to `row`, joined with ' > ' (cycle-safe)."""
    names, seen, cur = [], set(), row
    while cur and cur["account_id"] not in seen:
        seen.add(cur["account_id"])
        names.append((cur.get("account_name") or "").strip())
        cur = by_id.get(str(cur.get("parent_account_id") or ""))
    return " > ".join(reversed(names))


def category_rows_from_accounts(accounts: list[dict[str, Any]], entity: str) -> list[dict[str, Any]]:
    """`accounts` rows → Category Master rows (the keys `category_master.build_category_master` emits)."""
    by_id = {str(a["account_id"]): a for a in accounts}
    rows = []
    for a in accounts:
        name = (a.get("account_name") or "").strip()
        rows.append({
            "account_id": str(a["account_id"]),
            "account_code": a.get("account_code") or "",
            "ledger_name": name,
            "entity_name": entity,
            "concate": f"{name}{entity}",
            "group_ledger": a.get("group_ledger") or "",
            "pl_bs": a.get("pl_bs") or "",
            "category": a.get("category") or "",
            "sub_category": a.get("sub_category") or "",
            "source": a.get("source") or "",
            "note": a.get("note") or "",
            "account_type": a.get("account_type") or "",
            "parent_account_name": a.get("parent_account_name") or "",
            "path": _account_path(by_id, a),
            "current_balance": 0.0,
            "is_active": bool(a.get("is_active", 1)),
        })
    rows.sort(key=lambda r: (r["pl_bs"] != "BS", r["path"].lower()))
    return rows


def _select_accounts() -> list[dict[str, Any]]:
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT account_id, account_code, account_name, account_type, parent_account_id, "
                    "parent_account_name, group_ledger, is_active, pl_bs, category, sub_category, source, note "
                    "FROM accounts")
        return list(cur.fetchall())


def get_category_master() -> list[dict[str, Any]]:
    """Ledger → category mapping, read from `accounts` (the seeder owns the rows)."""
    return category_rows_from_accounts(_select_accounts(), get_organization().get("name") or "")


def save_category_master(rows: list[dict[str, Any]]) -> int:
    """Write the MIS columns back to `accounts`. Updates only: no inserts, no deletes."""
    with connect() as conn, conn.cursor() as cur:
        cur.executemany(
            "UPDATE accounts SET group_ledger=%s, pl_bs=%s, category=%s, sub_category=%s, source=%s, note=%s "
            "WHERE account_id=%s",
            [(r.get("group_ledger", ""), r.get("pl_bs", ""), r.get("category", ""), r.get("sub_category", ""),
              r.get("source", ""), (r.get("note") or "")[:500], r["account_id"]) for r in rows],
        )
    return len(rows)


_SNAPSHOT_TTL = 60.0
_snapshot_cache: tuple[float, dict[str, Any]] | None = None


def snapshot_from_db(accounts: list[dict[str, Any]], org: dict[str, Any]) -> dict[str, Any]:
    """Same shape as output/coa_snapshot.json, plus `categories` (the stored MIS columns)."""
    name = org.get("name") or org.get("organization_id") or ""
    return {
        "organization_id": org.get("organization_id", ""),
        "organization_name": name,
        "currency_code": org.get("currency_code") or "",
        "fiscal_year_start_month": org.get("fiscal_year_start_month") or None,
        "synced_at": org.get("synced_at", ""),
        "accounts": [
            {"account_id": str(a["account_id"]), "account_code": a.get("account_code") or "",
             "account_name": a.get("account_name") or "", "account_type": a.get("account_type") or "",
             "parent_account_id": a.get("parent_account_id") or "",
             "parent_account_name": a.get("parent_account_name") or "",
             "is_active": bool(a.get("is_active", 1)), "current_balance": 0}
            for a in accounts
        ],
        "categories": category_rows_from_accounts(accounts, name),
    }


def coa_snapshot(*, refresh: bool = False) -> dict[str, Any]:
    """Chart + organization from the database, cached in-process for 60 s."""
    global _snapshot_cache
    now = time.monotonic()
    if not refresh and _snapshot_cache and now - _snapshot_cache[0] < _SNAPSHOT_TTL:
        return _snapshot_cache[1]
    snap = snapshot_from_db(_select_accounts(), get_organization())
    _snapshot_cache = (now, snap)
    return snap


def delete_run(run_id: int) -> bool:
    with connect() as conn, conn.cursor() as cur:
        return cur.execute("DELETE FROM report_runs WHERE id = %s", (run_id,)) > 0


# ---------------------------------------------------------------------------
# Reads (web viewer)
# ---------------------------------------------------------------------------


def _jsonable(v: Any) -> Any:
    if isinstance(v, date):
        return v.isoformat()
    if hasattr(v, "is_finite"):  # Decimal
        return float(v)
    return v


def _clean(row: dict[str, Any]) -> dict[str, Any]:
    return {k: _jsonable(v) for k, v in row.items()}


# ---------------------------------------------------------------------------
# Organization (company profile synced from Zoho; the web UI reads currency/name from here)
# ---------------------------------------------------------------------------

_ORG_TEXT = ("name", "currency_id", "currency_code", "currency_symbol", "currency_format",
             "time_zone", "country", "country_code")


def save_organization(org: dict[str, Any]) -> None:
    """Upsert the Zoho organization profile. `fiscal_year_start_month` is stored 1-12 (Zoho reads 0 = January)."""
    from reports.category_master import _fy_start_month

    vals = [str(org.get(k) or "")[:255] for k in _ORG_TEXT]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""INSERT INTO organization (organization_id, {", ".join(_ORG_TEXT)},
                    fiscal_year_start_month, is_tax_registered)
                VALUES (%s, {", ".join(["%s"] * len(_ORG_TEXT))}, %s, %s)
                ON DUPLICATE KEY UPDATE {", ".join(f"{k}=VALUES({k})" for k in _ORG_TEXT)},
                    fiscal_year_start_month=VALUES(fiscal_year_start_month),
                    is_tax_registered=VALUES(is_tax_registered)""",
            (str(org["organization_id"]), *vals, _fy_start_month(org.get("fiscal_year_start_month")) or 1,
             1 if org.get("is_tax_registered") else 0),
        )


def get_organization() -> dict[str, Any]:
    """The organization row, or {} if the seeder / `org-sync` has not loaded it."""
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT organization_id, name, currency_code, currency_symbol, fiscal_year_start_month, "
                    "time_zone, country, synced_at FROM organization ORDER BY synced_at DESC LIMIT 1")
        r = cur.fetchone()
    if not r:
        return {}
    r["synced_at"] = str(r["synced_at"])
    return r


def list_runs(kind: str | None = None, limit: int = 100) -> list[dict[str, Any]]:
    sql = """SELECT id, kind, organization_name, currency_code, from_date, to_date, fiscal_year_start,
                    months, source, created_at
             FROM report_runs {where} ORDER BY id DESC LIMIT %s"""
    params: list[Any] = []
    where = ""
    if kind:
        where, params = "WHERE kind = %s", [kind]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql.format(where=where), [*params, limit])
        out = []
        for r in cur.fetchall():
            r = _clean(r)
            r["months"] = json.loads(r["months"] or "[]")
            r["created_at"] = str(r["created_at"])
            out.append(r)
        return out


def get_run(run_id: int) -> dict[str, Any] | None:
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM report_runs WHERE id = %s", (run_id,))
        r = cur.fetchone()
    if not r:
        return None
    r = _clean(r)
    r["months"] = json.loads(r["months"] or "[]")
    r["summary"] = json.loads(r["summary"] or "{}")
    r["created_at"] = str(r["created_at"])
    return r


def get_statement(run_id: int, statement: str) -> dict[str, Any]:
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT line_no, label, kind FROM statement_lines WHERE run_id=%s AND statement=%s ORDER BY line_no",
            (run_id, statement),
        )
        lines = {r["line_no"]: {"label": r["label"], "kind": r["kind"], "values": {}} for r in cur.fetchall()}
        cur.execute(
            """SELECT line_no, col, col_order, amount FROM statement_values
               WHERE run_id=%s AND statement=%s ORDER BY col_order""",
            (run_id, statement),
        )
        columns: dict[str, int] = {}
        for r in cur.fetchall():
            columns.setdefault(r["col"], r["col_order"])
            if r["line_no"] in lines:
                lines[r["line_no"]]["values"][r["col"]] = float(r["amount"])
    return {
        "statement": statement,
        "columns": sorted(columns, key=columns.get),
        "lines": [lines[k] for k in sorted(lines)],
    }


def get_statement_tree(run_id: int, statement: str) -> list[dict[str, Any]]:
    """Expandable P&L / Executive Summary rebuilt from the run's stored TB (the same rows the
    saved statement was built from, so the totals tie out). [] for other statements."""
    from reports import financials

    if statement not in ("PL", "Executive Summary"):
        return []
    run = get_run(run_id)
    tb = get_trial_balance(run_id)
    if not run or not tb["rows"]:
        return []
    summary = {**run["summary"], "months": tb["months"],
               "from_date": run["from_date"], "to_date": run["to_date"]}
    pl, figures = financials.build_profit_and_loss(tb["rows"], summary)
    stmt = pl if statement == "PL" else financials.build_executive_summary(figures, summary)
    return [n.as_dict() for n in stmt.tree]


def get_trial_balance(run_id: int) -> dict[str, Any]:
    run = get_run(run_id)
    months = run["months"] if run else []
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT account_id, account_code, account_name, account_type, pl_bs, category, sub_category,
                      category_source, opening, period_debit, period_credit, movement, closing
               FROM tb_accounts WHERE run_id=%s
               ORDER BY pl_bs DESC, category, account_code, account_name""",
            (run_id,),
        )
        rows = {r["account_id"]: _clean(r) for r in cur.fetchall()}
        cur.execute("SELECT account_id, month, amount FROM tb_monthly WHERE run_id=%s", (run_id,))
        for r in cur.fetchall():
            if r["account_id"] in rows:
                rows[r["account_id"]][r["month"]] = float(r["amount"])
    for r in rows.values():
        for m in months:
            r.setdefault(m, 0.0)
    return {"months": months, "rows": list(rows.values())}


def get_margin_pivot(run_id: int, dimension: str, measure: str) -> dict[str, Any]:
    """Rows = dimension values, columns = months + Total."""
    if dimension not in MARGIN_DIMENSIONS or measure not in MARGIN_MEASURES:
        raise ValueError("unknown dimension or measure")
    col = MARGIN_DIMENSIONS[dimension]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""SELECT {col} AS dim, month,
                       SUM(net_sales) AS net_sales, SUM(cost_of_sales) AS cost,
                       SUM(gross_margin) AS gross_margin, SUM(base_quantity) AS base_quantity,
                       SUM(flag <> '') AS flagged
                FROM margin_lines WHERE run_id=%s GROUP BY {col}, month""",
            (run_id,),
        )
        data = cur.fetchall()

    def value(agg: dict[str, float]) -> float:
        if measure == "gm_pct":
            return round(agg["gross_margin"] / agg["net_sales"], 4) if agg["net_sales"] else 0.0
        return round(agg[measure], 4)

    months = sorted({r["month"] for r in data})
    by_dim: dict[str, dict[str, dict[str, float]]] = {}
    for r in data:
        cell = {k: float(r[k] or 0) for k in ("net_sales", "cost", "gross_margin", "base_quantity", "flagged")}
        by_dim.setdefault(r["dim"] or "(none)", {})[r["month"]] = cell

    def total(cells: list[dict[str, float]]) -> dict[str, float]:
        keys = ("net_sales", "cost", "gross_margin", "base_quantity", "flagged")
        return {k: sum(c.get(k, 0.0) for c in cells) for k in keys}

    rows = []
    for dim, per_month in by_dim.items():
        t = total(list(per_month.values()))
        values = {m: value(per_month[m]) for m in per_month}
        values["Total"] = value(t)
        rows.append({"label": dim, "values": values, "net_sales": t["net_sales"], "flagged": int(t["flagged"])})
    rows.sort(key=lambda r: r["net_sales"], reverse=True)

    grand_by_month = {m: total([pm[m] for pm in by_dim.values() if m in pm]) for m in months}
    grand = {m: value(v) for m, v in grand_by_month.items()}
    grand["Total"] = value(total(list(grand_by_month.values())))
    return {"columns": months + ["Total"], "rows": rows, "total": grand,
            "dimension": dimension, "measure": measure}



def get_margin_detail(run_id: int, view: str) -> dict[str, Any]:
    """Margin as a flat list: one row per invoice line (`line`) or per invoice (`invoice`)."""
    if view == "line":
        sql = """SELECT date, invoice_number, customer_name, item_name, unit, quantity, rate,
                        net_sales, cost_rate, cost_of_sales AS cost, gross_margin, flag, cost_source
                 FROM margin_lines WHERE run_id=%s ORDER BY date, invoice_number, line_no"""
    elif view == "invoice":
        sql = """SELECT date, invoice_number, status, customer_name, salesperson_name, line_count,
                        net_sales, cost_of_sales AS cost, gross_margin, flagged_lines AS flagged,
                        cost_source, total, balance
                 FROM margin_invoices WHERE run_id=%s ORDER BY date, invoice_number"""
    else:
        raise ValueError("view must be line or invoice")
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, (run_id,))
        return _margin_detail(view, cur.fetchall())


def _margin_detail(view: str, rows: list[dict[str, Any]]) -> dict[str, Any]:
    for r in rows:
        r["date"] = r["date"].isoformat() if r["date"] else ""
        for k, v in r.items():
            if hasattr(v, "as_tuple"):  # Decimal
                r[k] = float(v)
        r["gm_pct"] = round(r["gross_margin"] / r["net_sales"], 4) if r["net_sales"] else 0.0
    t = {k: sum(r[k] for r in rows) for k in ("net_sales", "cost", "gross_margin")}
    t["gm_pct"] = round(t["gross_margin"] / t["net_sales"], 4) if t["net_sales"] else 0.0
    return {"view": view, "rows": rows, "total": t}


def get_purchase_pivot(run_id: int, dimension: str, measure: str) -> dict[str, Any]:
    """Rows = dimension values, columns = months + Total (same shape as the margin pivot)."""
    if dimension not in PURCHASE_DIMENSIONS or measure not in PURCHASE_MEASURES:
        raise ValueError("unknown dimension or measure")
    col = PURCHASE_DIMENSIONS[dimension]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            f"""SELECT {col} AS dim, month, SUM(amount) AS amount, SUM(quantity) AS quantity,
                       COUNT(DISTINCT kind, doc_id) AS documents
                FROM purchase_lines WHERE run_id=%s GROUP BY {col}, month""",
            (run_id,),
        )
        data = cur.fetchall()
        cur.execute(
            f"""SELECT {col} AS dim, SUM(amount) AS amount, SUM(quantity) AS quantity,
                       COUNT(DISTINCT kind, doc_id) AS documents
                FROM purchase_lines WHERE run_id=%s GROUP BY {col}""",
            (run_id,),
        )
        dim_totals = {(r["dim"] or "(none)"): r for r in cur.fetchall()}
        cur.execute(
            "SELECT SUM(amount) AS amount, SUM(quantity) AS quantity, COUNT(DISTINCT kind, doc_id) AS documents "
            "FROM purchase_lines WHERE run_id=%s",
            (run_id,),
        )
        grand_total = cur.fetchone() or {}
        cur.execute(
            "SELECT month, SUM(amount) AS amount, SUM(quantity) AS quantity, COUNT(DISTINCT kind, doc_id) AS documents "
            "FROM purchase_lines WHERE run_id=%s GROUP BY month",
            (run_id,),
        )
        month_totals = {r["month"]: r for r in cur.fetchall()}

    def val(r: dict[str, Any]) -> float:
        return round(float(r.get(measure) or 0), 4)

    months = sorted({r["month"] for r in data})
    by_dim: dict[str, dict[str, float]] = {}
    for r in data:
        by_dim.setdefault(r["dim"] or "(none)", {})[r["month"]] = val(r)
    rows = []
    for dim, values in by_dim.items():
        values["Total"] = val(dim_totals[dim])
        rows.append({"label": dim, "values": values, "amount": float(dim_totals[dim]["amount"] or 0)})
    rows.sort(key=lambda r: r["amount"], reverse=True)
    total = {m: val(month_totals[m]) for m in months}
    total["Total"] = val(grand_total)
    return {"columns": months + ["Total"], "rows": rows, "total": total, "dimension": dimension, "measure": measure}


# ---------------------------------------------------------------------------
# Dated store: reads by date range (columns come from the client's date filter)
# ---------------------------------------------------------------------------

_MARGIN_SOURCE = ("sales_lines l JOIN sales_invoices i ON i.invoice_id = l.invoice_id "
                  "LEFT JOIN vans v ON v.location_id = l.location_id")
_MARGIN_WHERE = "i.status NOT IN ('draft', 'void')"
_MARGIN_SUMS = {"net_sales": "l.net_sales", "cost": "l.cogs", "gross_margin": "l.net_sales - l.cogs",
                "base_quantity": "l.base_quantity", "flagged": "l.flag <> ''"}
_PURCHASE_SOURCE = "purchase_lines pl JOIN purchase_docs d ON d.kind = pl.kind AND d.doc_id = pl.doc_id"
_PURCHASE_WHERE = "d.status NOT IN ('draft', 'void', 'cancelled')"
_PURCHASE_SUMS = {"amount": "pl.amount", "quantity": "pl.quantity",
                  "documents": "DISTINCT CONCAT(pl.kind, ':', pl.doc_id)"}


def _bucketed(source: str, where: str, date_col: str, dim_col: str, cols: list[periods.Col],
              sums: dict[str, str]) -> list[dict[str, Any]]:
    """One row per dimension value plus the rollup row (dim None): `c{i}_{name}` per column, `c{i}_n` the
    row count (0 → no data in that column), `s_{name}` over the whole span. `source` is the FROM + joins,
    `where` the status filter, `date_col` the line's own (aliased) date column."""
    start, end = periods.span(cols)
    when = f"WHEN {date_col} BETWEEN %s AND %s THEN"
    parts, params = [], []
    for i, c in enumerate(cols):
        for name, expr in sums.items():
            if expr.startswith("DISTINCT "):
                parts.append(f"COUNT(DISTINCT CASE {when} {expr[9:]} END) AS c{i}_{name}")
            else:
                parts.append(f"SUM(CASE {when} {expr} END) AS c{i}_{name}")
            params += [c.start, c.end]
        parts.append(f"COUNT(CASE {when} 1 END) AS c{i}_n")
        params += [c.start, c.end]
    parts += [f"SUM({expr}) AS s_{name}" for name, expr in sums.items() if not expr.startswith("DISTINCT ")]
    with connect() as conn, conn.cursor() as cur:
        cur.execute(f"SELECT {dim_col} AS dim, {', '.join(parts)} FROM {source} "
                    f"WHERE {date_col} BETWEEN %s AND %s AND {where} GROUP BY {dim_col} WITH ROLLUP",
                    (*params, start, end))
        return cur.fetchall()


def _range_pivot(source: str, where: str, date_col: str, dim_col: str, cols: list[periods.Col],
                 sums: dict[str, str], value: Any, sort_key: str, extra: Any) -> dict[str, Any]:
    def cells(r: dict[str, Any]) -> dict[str, float]:
        return {c.key: value({n: float(r[f"c{i}_{n}"] or 0) for n in sums})
                for i, c in enumerate(cols) if r[f"c{i}_n"]}

    rows, grand = [], {}
    for r in _bucketed(source, where, date_col, dim_col, cols, sums):
        if r["dim"] is None:  # WITH ROLLUP total (dimension columns are NOT NULL, so no clash)
            grand = cells(r)
        else:
            rows.append({"label": r["dim"] or "(none)", "values": cells(r), **extra(r)})
    rows.sort(key=lambda x: x[sort_key], reverse=True)
    start, end = periods.span(cols)
    return {"columns": [c.key for c in cols], "rows": rows, "total": grand,
            "from": start.isoformat(), "to": end.isoformat()}


def get_margin_pivot_range(cols: list[periods.Col], dimension: str, measure: str) -> dict[str, Any]:
    """Rows = dimension values, columns = the given date ranges; gm % is a ratio of sums per column."""
    if dimension not in MARGIN_DIMENSIONS or measure not in MARGIN_MEASURES:
        raise ValueError("unknown dimension or measure")

    def value(agg: dict[str, float]) -> float:
        if measure == "gm_pct":
            return round(agg["gross_margin"] / agg["net_sales"], 4) if agg["net_sales"] else 0.0
        return round(agg[measure], 4)

    out = _range_pivot(_MARGIN_SOURCE, _MARGIN_WHERE, "l.date", MARGIN_DIMENSIONS[dimension], cols,
                       _MARGIN_SUMS, value, "net_sales",
                       lambda r: {"net_sales": float(r["s_net_sales"] or 0), "flagged": int(r["s_flagged"] or 0)})
    return {**out, "dimension": dimension, "measure": measure}


def get_purchase_pivot_range(cols: list[periods.Col], dimension: str, measure: str) -> dict[str, Any]:
    """Same shape as the margin pivot; `documents` counts distinct bills / POs per column."""
    if dimension not in PURCHASE_DIMENSIONS or measure not in PURCHASE_MEASURES:
        raise ValueError("unknown dimension or measure")
    out = _range_pivot(_PURCHASE_SOURCE, _PURCHASE_WHERE, "pl.date", PURCHASE_DIMENSIONS[dimension], cols,
                       _PURCHASE_SUMS, lambda agg: round(agg[measure], 4), "amount",
                       lambda r: {"amount": float(r["s_amount"] or 0)})
    return {**out, "dimension": dimension, "measure": measure}


def get_margin_detail_range(start: date, end: date, view: str) -> dict[str, Any]:
    """Margin as a flat list for [start, end]: one row per invoice line or per invoice."""
    if view == "line":
        sql = f"""SELECT l.date, i.invoice_number, i.customer_name, l.location_name, l.item_name, l.unit,
                         l.quantity, l.rate, l.net_sales, l.purchase_price, l.cogs AS cost,
                         l.net_sales - l.cogs AS gross_margin, l.flag
                  FROM sales_lines l JOIN sales_invoices i ON i.invoice_id = l.invoice_id
                  WHERE l.date BETWEEN %s AND %s AND {_MARGIN_WHERE}
                  ORDER BY l.date, i.invoice_number, l.line_item_id"""
    elif view == "invoice":
        sql = f"""SELECT i.date, i.invoice_number, i.status, i.customer_name, i.salesperson_name,
                         COUNT(l.line_item_id) AS line_count, i.net_sales, i.cogs AS cost,
                         i.net_sales - i.cogs AS gross_margin, i.flagged_lines AS flagged, i.total, i.balance
                  FROM sales_invoices i LEFT JOIN sales_lines l ON l.invoice_id = i.invoice_id
                  WHERE i.date BETWEEN %s AND %s AND {_MARGIN_WHERE}
                  GROUP BY i.invoice_id, i.date, i.invoice_number, i.status, i.customer_name,
                           i.salesperson_name, i.net_sales, i.cogs, i.flagged_lines, i.total, i.balance
                  ORDER BY i.date, i.invoice_number"""
    else:
        raise ValueError("view must be line or invoice")
    with connect() as conn, conn.cursor() as cur:
        cur.execute(sql, (start, end))
        return _margin_detail(view, cur.fetchall())


def get_coverage(dataset: str) -> dict[str, Any]:
    """Loaded date ranges for a dataset, plus the gaps between the first and last loaded day."""
    if dataset not in COVERAGE_DATASETS:
        raise ValueError(f"dataset must be one of {sorted(COVERAGE_DATASETS)}")
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT from_date, to_date, synced_at, source FROM sync_coverage WHERE dataset=%s "
                    "ORDER BY from_date", (dataset,))
        rows = cur.fetchall()
    spans = [(r["from_date"], r["to_date"]) for r in rows]
    lo, hi = (spans[0][0], max(b for _, b in spans)) if spans else (None, None)

    def iso(pairs: list[tuple[date, date]]) -> list[dict[str, str]]:
        return [{"from": a.isoformat(), "to": b.isoformat()} for a, b in pairs]

    return {
        "dataset": dataset,
        "ranges": [{"from": r["from_date"].isoformat(), "to": r["to_date"].isoformat(),
                    "synced_at": str(r["synced_at"]), "source": r["source"]} for r in rows],
        "merged": iso(periods.merge_ranges(spans)),
        "gaps": iso(periods.gaps(spans, lo, hi)) if spans else [],
        "min": lo.isoformat() if lo else None,
        "max": hi.isoformat() if hi else None,
    }
