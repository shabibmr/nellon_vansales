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
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'AED GL-reconciled; sales_lines.cogs add up to it',
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
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED reducing COGS; GL-reconciled',
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
        `cogs`                     DECIMAL(18,2) NOT NULL DEFAULT 0.00 COMMENT 'Positive AED increasing COGS; GL-reconciled when a ledger row exists',
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

MARGIN_DIMENSIONS = {
    "item": "l.item_name",
    "customer": "i.customer_name",
    "salesperson": "i.salesperson_name",
    "van": "CASE WHEN v.location_id IS NULL THEN '(warehouse)' ELSE l.location_name END",
    "location": "l.location_name",
}
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


# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Dated store: range-replace writes (the Zoho list for a date range is authoritative)
# ---------------------------------------------------------------------------

COVERAGE_DATASETS = {"sales", "purchases"}


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


# ---------------------------------------------------------------------------
# Reads (web viewer)
# ---------------------------------------------------------------------------


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
