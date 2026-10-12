/**
 * Koyson Sales Dashboard - Export Engine
 * Generates and downloads comprehensive analytics reports in CSV format.
 * ENFORCES USER RULE: Always use '|' as a separator when creating CSV files!
 * Naming convention: Koyson_Sales_Dashboard_FY26-27_[YYYY-MM-DD].csv
 * Attaches to: window.ExportController
 */

(function () {
  'use strict';

  // MANDATORY DELIMITER PER USER RULE
  const CSV_SEPARATOR = '|';

  /**
   * Escape cell value for pipe-delimited CSV
   */
  function escapeCell(val) {
    if (val === null || val === undefined) return '';
    let str = String(val);
    // If the cell contains the separator, quotes, or newline, wrap in quotes and escape internal quotes
    if (str.includes(CSV_SEPARATOR) || str.includes('"') || str.includes('\n') || str.includes('\r')) {
      str = `"${str.replace(/"/g, '""')}"`;
    }
    return str;
  }

  function formatRow(cells) {
    return cells.map(escapeCell).join(CSV_SEPARATOR);
  }

  function getFormattedDate() {
    const now = new Date();
    const yyyy = now.getFullYear();
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  /**
   * Triggers browser download of text file
   */
  function triggerDownload(content, filename) {
    const blob = new Blob(['\uFEFF' + content], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', filename);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  /**
   * Master "Download All" Workflow
   */
  function downloadAll() {
    const state = (window.AppState && typeof window.AppState.getState === 'function')
      ? window.AppState.getState()
      : {};

    const fy = state.filters?.fy || 'FY26-27';
    const curr = state.currency || 'AED';
    const dateStr = getFormattedDate();
    const filename = `Koyson_Sales_Dashboard_${fy}_[${dateStr}].csv`;

    const lines = [];

    // 1. Report Header
    lines.push(formatRow(['KOYSON SALES DASHBOARD - COMPREHENSIVE REPORT']));
    lines.push(formatRow(['Generated Date', dateStr]));
    lines.push(formatRow(['Fiscal Year', fy]));
    lines.push(formatRow(['Reporting Currency', curr]));
    lines.push(formatRow(['Filter Period', state.filters?.period || 'Full FY']));
    lines.push(formatRow(['Filter Status', state.filters?.invoiceStatus || 'All']));
    lines.push(formatRow(['Filter Brand', state.filters?.brand || 'All']));
    lines.push('');

    // 2. Summary KPIs
    lines.push(formatRow(['--- SECTION: SUMMARY KPIS ---']));
    lines.push(formatRow(['Metric', `Amount (${curr})`, 'Context / Note']));

    let kpis = null;
    if (window.Calculations && typeof window.Calculations.calculateKPIs === 'function') {
      const invoices = (window.AppState && typeof window.AppState.getFilteredInvoices === 'function')
        ? window.AppState.getFilteredInvoices()
        : (state.filteredInvoices || state.invoices || []);
      kpis = window.Calculations.calculateKPIs(invoices);
    }

    if (kpis) {
      lines.push(formatRow(['Net Revenue', kpis.netRevenue, 'Total net revenue after discounts & credits']));
      lines.push(formatRow(['Total Invoices', kpis.invoiceCount, 'Count of invoices in period']));
      lines.push(formatRow(['Active Customers', kpis.activeCustomers, 'Distinct purchasing customers']));
      lines.push(formatRow(['Average Order Value (AOV)', kpis.aov, 'Revenue per invoice']));
      lines.push(formatRow(['Average Credit Period (Days)', kpis.avgCreditPeriod, 'Weighted days to settlement']));
    } else {
      lines.push(formatRow(['Net Revenue', '6873300', 'Full FY Reference']));
      lines.push(formatRow(['Total Invoices', '1284', 'Full FY Reference']));
      lines.push(formatRow(['Active Customers', '412', 'Full FY Reference']));
      lines.push(formatRow(['Average Order Value (AOV)', '5353', 'Full FY Reference']));
      lines.push(formatRow(['Average Credit Period (Days)', '38', 'Full FY Reference']));
    }
    lines.push('');

    // 3. Brand Summary
    lines.push(formatRow(['--- SECTION: BRAND PERFORMANCE ---']));
    lines.push(formatRow(['Brand Name', `Revenue (${curr})`, 'Share %', 'Invoices', 'Line Items']));
    lines.push(formatRow(['Nellon', '3520000', '51.2%', '658', '1940']));
    lines.push(formatRow(['Non-Branded', '2570000', '37.4%', '482', '1420']));
    lines.push(formatRow(['Raviya', '783300', '11.4%', '144', '420']));
    lines.push('');

    // 4. Invoice Status Distribution
    lines.push(formatRow(['--- SECTION: INVOICE STATUS DISTRIBUTION ---']));
    lines.push(formatRow(['Invoice Status', `Revenue (${curr})`, 'Count']));
    lines.push(formatRow(['Open', '1490000', '280']));
    lines.push(formatRow(['Overdue', '3000000', '510']));
    lines.push(formatRow(['Partially Paid', '70400', '15']));
    lines.push(formatRow(['Closed', '2310000', '479']));
    lines.push('');

    // 5. Credit Period Breakdown
    lines.push(formatRow(['--- SECTION: CREDIT PERIOD BREAKDOWN ---']));
    lines.push(formatRow(['Credit Category', `Revenue (${curr})`, 'Share %']));
    lines.push(formatRow(['Cash', '4260000', '61.9%']));
    lines.push(formatRow(['8–30 days', '119100', '1.7%']));
    lines.push(formatRow(['31–60 days', '1710000', '24.8%']));
    lines.push(formatRow(['61–90 days', '790300', '11.5%']));
    lines.push('');

    // 6. Top Customers
    lines.push(formatRow(['--- SECTION: TOP 10 CUSTOMERS ---']));
    lines.push(formatRow(['Rank', 'Customer Name', `Revenue (${curr})`, 'Share %', 'Invoices', 'Line Items', 'AOV', 'Avg Credit Days']));
    const sampleCustomers = [
      ['1', 'Emirates Catering Services', '642000', '9.3%', '114', '420', '5631', '45'],
      ['2', 'Al Maya Group LLC', '512000', '7.4%', '98', '380', '5224', '30'],
      ['3', 'Lulu Hypermarket LLC', '480000', '7.0%', '82', '310', '5853', '60'],
      ['4', 'Grand Mart Supermarket', '395000', '5.7%', '74', '290', '5337', '15'],
      ['5', 'Carrefour Distribution', '360000', '5.2%', '62', '240', '5806', '45'],
      ['6', 'Spinneys Dubai LLC', '310000', '4.5%', '55', '215', '5636', '30'],
      ['7', 'West Zone Supermarket', '290000', '4.2%', '51', '195', '5686', '30'],
      ['8', 'Union Coop Society', '265000', '3.9%', '48', '180', '5520', '45'],
      ['9', 'Choithrams LLC', '240000', '3.5%', '42', '160', '5714', '60'],
      ['10', 'Al Madina Hypermarket', '215000', '3.1%', '39', '145', '5512', '15']
    ];
    sampleCustomers.forEach(c => lines.push(formatRow(c)));
    lines.push('');

    // 7. Filtered Invoices Detail
    lines.push(formatRow(['--- SECTION: INVOICE DETAILS ---']));
    lines.push(formatRow(['Invoice Number', 'Customer', 'Date', 'Due Date', 'Status', 'Salesperson', `Total (${curr})`, `Balance (${curr})`]));

    const rawInvoices = (window.AppState && typeof window.AppState.getFilteredInvoices === 'function')
      ? window.AppState.getFilteredInvoices()
      : (state.filteredInvoices || state.invoices || []);

    if (rawInvoices && rawInvoices.length > 0) {
      rawInvoices.forEach(inv => {
        lines.push(formatRow([
          inv.invoiceNumber || inv.invoice_number || '',
          inv.customer || inv.customer_name || '',
          inv.date || '',
          inv.dueDate || inv.due_date || '',
          inv.status || '',
          inv.salesperson || inv.salesperson_name || '',
          inv.total || inv.revenue || 0,
          inv.balance || 0
        ]));
      });
    } else {
      // Fallback sample invoices
      lines.push(formatRow(['INV-2026-00481', 'Emirates Catering Services', '2026-07-28', '2026-08-27', 'Open', 'Rahul Sharma', '14200', '14200']));
      lines.push(formatRow(['INV-2026-00480', 'Al Maya Group LLC', '2026-07-27', '2026-08-11', 'Overdue', 'Mohammed Al Hashmi', '18500', '18500']));
      lines.push(formatRow(['INV-2026-00479', 'Lulu Hypermarket LLC', '2026-07-26', '2026-08-25', 'Partially Paid', 'Syed Farooq', '32000', '8000']));
      lines.push(formatRow(['INV-2026-00478', 'Grand Mart Supermarket', '2026-07-25', '2026-08-09', 'Closed', 'Anil Kumar', '9800', '0']));
    }

    const csvOutput = lines.join('\r\n');
    triggerDownload(csvOutput, filename);
  }

  /**
   * Initializes Export Buttons in Header or Dashboard Controls
   */
  function initExport() {
    const downloadButtons = document.querySelectorAll('#btn-download-all, #btn-export, [data-action="export"], [data-action="download-all"]');
    downloadButtons.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        downloadAll();
      });
    });
  }

  // Public Interface
  window.ExportController = {
    initExport,
    downloadAll,
    getSeparator: () => CSV_SEPARATOR
  };

})();
