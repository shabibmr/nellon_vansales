-- ==============================================================================
-- Proposed Schema for Zoho Books MIS Database
-- copy of `reports/db.py` SCHEMA; change both
-- Source specification: proposal/DB-Schema-Proposed.md
-- Character set: utf8mb4 / utf8mb4_unicode_ci
-- ==============================================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------------------------
-- 1. organization: Company master configuration (single-row master)
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 2. accounts: Chart of accounts with MIS classification
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 3. locations: Warehouses and van locations
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `locations` (
    `location_id`              VARCHAR(40)   NOT NULL,
    `location_name`            VARCHAR(255)  NOT NULL DEFAULT '',
    `is_primary`               TINYINT(1)    NOT NULL DEFAULT 0,
    `address`                  TEXT          NULL,
    `last_modified_time`       DATETIME      NULL DEFAULT NULL,
    PRIMARY KEY (`location_id`),
    KEY `ix_loc_name` (`location_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------------------------
-- 4. salespersons: Sales agents
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 5. customers: Customers master (contact_type=customer)
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 6. vendors: Vendors master (contact_type=vendor)
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 7. vans: Sales vans (locations assigned to salespersons)
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 8. items: Master item list
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 9. item_units: Alternate unit conversions for items
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 10. sales_invoices: Sales invoice headers
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 11. sales_lines: Line items for sales invoices
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 12. purchase_docs: Purchase orders and bills headers
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 13. purchase_lines: Line items for bills and purchase orders
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 14. credit_notes: Customer credit note headers
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 15. credit_note_lines: Line items for credit notes
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 16. debit_notes: Customer debit note headers
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 17. debit_note_lines: Line items for debit notes
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 18. gl_journals: General Ledger postings (one row per account posting)
-- ------------------------------------------------------------------------------
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

SET FOREIGN_KEY_CHECKS = 1;
