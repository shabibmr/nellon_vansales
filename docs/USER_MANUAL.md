# Nellon Van Sales - Field Representative User Guide

Welcome to the **Nellon Van Sales Mobile Application**. This user manual is designed for Van Sales Representatives and Field Drivers to help you perform your daily sales, payment collection, stock management, and customer operations quickly and accurately—even when working offline without an active internet connection.

---

## Table of Contents
1. [Overview & Key Concepts](#1-overview--key-concepts)
2. [Start of Day Operations](#2-start-of-day-operations)
   - [2.1 Logging In & Device License Activation](#21-logging-in--device-license-activation)
   - [2.2 Syncing Master Data](#22-syncing-master-data)
   - [2.3 Selecting Active Route & Van Warehouse](#23-selecting-active-route--van-warehouse)
   - [2.4 Stock Allocation & Van Stock Transfers](#24-stock-allocation--van-stock-transfers)
3. [Customer & Field Operations](#3-customer--field-operations)
   - [3.1 Route Navigation & Customer Selection](#31-route-navigation--customer-selection)
   - [3.2 Checking Customer Balances & Ledger](#32-checking-customer-balances--ledger)
   - [3.3 Creating Direct Sales Invoices](#33-creating-direct-sales-invoices)
   - [3.4 Taking Sales Orders](#34-taking-sales-orders)
   - [3.5 Collecting Payments (Receipt Vouchers)](#35-collecting-payments-receipt-vouchers)
   - [3.6 Processing Sales Returns](#36-processing-sales-returns)
   - [3.7 Logging Daily Expenses](#37-logging-daily-expenses)
4. [Printing Vouchers & Receipts](#4-printing-vouchers--receipts)
   - [4.1 Setting Up Bluetooth Thermal Printer](#41-setting-up-bluetooth-thermal-printer)
   - [4.2 Printing Receipts (Thermal vs. A4 PDF)](#42-printing-receipts-thermal-vs-a4-pdf)
5. [Offline Mode & Data Synchronization](#5-offline-mode--data-synchronization)
   - [5.1 How Offline Mode Works](#51-how-offline-mode-works)
   - [5.2 Managing the Sync Queue](#52-managing-the-sync-queue)
6. [Reports & End of Day Reconciliation](#6-reports--end-of-day-reconciliation)
   - [6.1 Viewing Field Reports](#61-viewing-field-reports)
   - [6.2 End of Day Checklist](#62-end-of-day-checklist)
7. [Troubleshooting & FAQ](#7-troubleshooting--faq)

---

## 1. Overview & Key Concepts

The Nellon Van Sales app enables you to record transactions directly on your mobile device while visiting customer locations.

* **Offline-First Capabilities**: All invoices, receipts, returns, and expenses are saved locally on your mobile device first. When internet connectivity is available, the app automatically uploads them to Zoho Books.
* **Master Data**: Customers, items, prices, tax rules, and routes are stored safely on your device for fast access during customer visits.
* **Relational Sync Queue**: If you add a new customer while offline, any invoices or receipts created for that customer will wait in the queue until the new customer profile is synced to Zoho Books.

---

## 2. Start of Day Operations

Follow these steps before heading out on your daily route.

### 2.1 Logging In & Device License Activation
1. Launch the **Nellon Van Sales** app on your handheld device.
2. Enter your **Phone Number / Email** and **Password** or verification PIN.
3. If logging in on a new device, the **Device License Gate** will automatically verify your device ID. If prompted, contact your administrator to authorize the device.

### 2.2 Syncing Master Data
Upon first login or when requested by system updates, the app displays the **Masters Sync Screen**.
1. Ensure your device has an active Wi-Fi or cellular data connection.
2. Tap **Download Master Data** (or **Sync Masters**).
3. Wait for items, customer profiles, price lists, and route maps to finish downloading.
4. Once completed, a green checkmark will indicate that master data is up to date.

> [!TIP]
> Always perform Master Data Sync while connected to high-speed internet at the main depot or warehouse before starting your route.

### 2.3 Selecting Active Route & Van Warehouse
1. On the **Route Selection Screen**, select your assigned sales route for the day (e.g., *Route 5 - Downtown Retail*).
2. Confirm your assigned **Van Warehouse / Location**.
3. Tap **Start Route** to proceed to your main dashboard.

### 2.4 Stock Allocation & Van Stock Transfers
Before leaving the depot, ensure your physical van inventory matches the app inventory:
1. Open the side navigation drawer and tap **Stock Transfer**.
2. Tap **New Issue-to-Van Transfer** to log stock moved from the Main Depot into your Van Warehouse.
3. Select the items and quantities loaded into your vehicle.
4. Save the transfer. This updates your local van stock balance.

---

## 3. Customer & Field Operations

### 3.1 Route Navigation & Customer Selection
1. From the **Dashboard**, tap **My Customers** or view the interactive **Route List**.
2. Filter or search by Customer Name, Phone Number, or Address.
3. Tap on a customer name to open their **Customer Details & Action Menu**.

### 3.2 Checking Customer Balances & Ledger
1. Within the customer detail view, review the **Outstanding Balance** displayed at the top.
2. Tap **View Customer Ledger** to see previous transaction history, paid invoices, and unpaid statements fetched from Zoho Books.

### 3.3 Creating Direct Sales Invoices
Use this when delivering products and collecting/billing immediately at the customer site.

1. Select **New Sales Invoice** from the customer action menu.
2. **Add Line Items**:
   - Search for products using name, SKU, or barcode.
   - Adjust quantities, discounts, and unit prices as authorized.
3. **Review Summary**:
   - Verify subtotal, tax amounts (VAT/GST), discounts, and final total.
4. **Payment Terms**:
   - Mark as **Cash**, **Credit**, or **Cheque**.
5. Tap **Save & Generate Invoice**.
6. (Optional) Print a thermal receipt or export an A4 PDF for the customer.

### 3.4 Taking Sales Orders
Use this when taking advance orders for future warehouse fulfillment or delivery.

1. Select **New Sales Order** from the customer action menu.
2. Choose items and quantities requested by the customer.
3. Set the expected **Delivery Date**.
4. Tap **Submit Sales Order**. The order will be saved and queued for sync.

### 3.5 Collecting Payments (Receipt Vouchers)
Use this when receiving cash, cheques, or bank transfers for unpaid invoices.

1. Select **Collect Payment / Receipt** from the customer profile.
2. Enter the **Total Amount Received**.
3. Select the **Payment Mode**: Cash, Cheque, or Bank Transfer.
4. **Invoice Allocation**:
   - The app lists all open unpaid invoices for this customer.
   - Tap **Auto-Allocate** to pay off the oldest invoices first, or manually enter amounts against specific invoices.
5. Tap **Save Receipt**.

### 3.6 Processing Sales Returns
Use this when a customer returns damaged or expired stock.

1. Select **Sales Return** from the customer action menu.
2. Pick the original invoice reference (if applicable) or select return items directly.
3. Specify the **Return Quantity** and **Reason for Return** (e.g., Damaged, Expired, Wrong Item).
4. Tap **Process Return**. This credits the customer's account and updates return records.

### 3.7 Logging Daily Expenses
Log field expenses such as fuel, toll fees, vehicle parking, or client meals.

1. Open the navigation menu and select **Expense Log**.
2. Tap **Add Expense**.
3. Select the **Expense Category** (e.g., Fuel, Toll, Vehicle Maintenance, Meals).
4. Enter the **Amount** and optional notes/description.
5. Tap **Save Expense**.

---

## 4. Printing Vouchers & Receipts

### 4.1 Setting Up Bluetooth Thermal Printer
The app supports 2-inch and 4-inch portable Bluetooth ESC/POS receipt printers (e.g., Nigachi NC-MTP500 series).

1. Turn on your Bluetooth printer.
2. On your mobile device, go to **Settings > Bluetooth Thermal Printer**.
3. Tap **Scan for Devices** and select your printer from the list.
4. Select your paper width: **2-inch (58mm)** or **4-inch (80mm)**.
5. Tap **Test Print** to verify the connection.

### 4.2 Printing Receipts (Thermal vs. A4 PDF)
When completing an Invoice, Receipt, or Sales Return:
* **Thermal Print**: Tap the **Print Receipt** (Bluetooth icon) button for an instant compact thermal receipt.
* **A4 PDF / Share**: Tap the **PDF Preview** button to generate an official A4 document that can be shared via WhatsApp, Email, or printed via system print service.

---

## 5. Offline Mode & Data Synchronization

### 5.1 How Offline Mode Works
You can continue issuing invoices, taking orders, collecting payments, and logging expenses even without cellular signal. All transactions are queued locally with a status of `Pending`.

### 5.2 Managing the Sync Queue
1. Open the navigation menu and select **Sync Center / Offline Queue**.
2. View the status of queued items:
   - **Pending (Yellow)**: Waiting to upload.
   - **Synced (Green)**: Successfully posted to Zoho Books.
   - **Failed (Red)**: Failed due to a network error or missing master data.
3. Tap **Sync Now** to manually trigger an immediate synchronization.
4. If an item fails, tap on the item card to view the error reason or retry the upload.

> [!IMPORTANT]
> **New Offline Customers**: If you register a new customer while offline, all invoices and payment receipts for that customer will remain pending until the customer profile syncs first. Do not clear app cache while items are pending!

---

## 6. Reports & End of Day Reconciliation

### 6.1 Viewing Field Reports
Access real-time summaries of your day's work from the **Reports** section:
* **Daily Sales Summary**: Total invoices, sales value, and discounts.
* **Collections Summary**: Cash and cheque payments collected.
* **Itemwise Sales Report**: Quantities sold per product.
* **Van Stock Report**: Remaining inventory in your vehicle.
* **Receivables Aging Report**: Customer overdue balances.

You can export any report as a **PDF** or **CSV** file.

### 6.2 End of Day Checklist
Before ending your shift:
1. Go to **Sync Center** and verify that all pending transactions show **Synced**.
2. Compare physical cash/cheques collected against the **Collections Summary Report**.
3. Check remaining van stock against the **Van Stock Report**.
4. Log any final vehicle fuel or parking expenses.
5. Tap **End Route / Logout**.

---

## 7. Troubleshooting & FAQ

| Problem | Cause | Solution |
| :--- | :--- | :--- |
| **Printer fails to connect** | Bluetooth is turned off or device unpaired | Turn Bluetooth on, go to Printer Settings, and tap **Scan & Reconnect**. Ensure printer battery is charged. |
| **Transactions stuck in Pending status** | No internet connection or server unreachable | Move to an area with mobile signal or connect to Wi-Fi. Tap **Sync Now** in Sync Center. |
| **"Customer ID not resolved" in Queue** | Customer was created offline and hasn't synced yet | Connect to internet and tap **Sync Now**. The app will sync the customer first, then automatically update pending invoices. |
| **Cannot see newly added items or prices** | Master data is outdated | Go to main menu, select **Master Data Sync**, and tap **Download Master Data**. |
| **App prompts "License Invalid or Expired"** | Device registration state changed | Contact your Administrator with your Device ID to re-authorize your device license. |

---

*For technical support or assistance, please contact your System Administrator or Operations Manager.*
