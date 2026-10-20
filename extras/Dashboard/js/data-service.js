/**
 * Koyson Sales Dashboard - Unified Data Service
 * Orchestrates data loading from Zoho Books ZFWidget API, SheetJS file upload (Excel/CSV),
 * and reference demo dataset. Handles data normalization, sanitization, and CSV export.
 * Follows user rule: Always use '|' as separator when creating CSV files.
 * Compatible with Browser (window.DataService) and Node.js.
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define(['./calculations.js', './state.js', './zoho-service.js', './demo-data.js'], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory(
      require('./calculations.js'),
      require('./state.js'),
      require('./zoho-service.js'),
      require('./demo-data.js')
    );
  } else {
    root.DataService = factory(root.Calculations, root.AppState, root.ZohoService, root.DEMO_DATA);
  }
})(typeof self !== 'undefined' ? self : this, function (Calculations, AppState, ZohoService, DEMO_DATA) {
  'use strict';

  /**
   * Helper to clean strings.
   */
  function cleanStr(val) {
    if (val === null || val === undefined) return '';
    return String(val).trim();
  }

  /**
   * Helper to parse numeric values safely.
   */
  function parseNum(val, fallback = 0) {
    if (typeof val === 'number') return isNaN(val) ? fallback : val;
    if (!val) return fallback;
    const cleaned = String(val).replace(/[^0-9.-]+/g, '');
    const n = parseFloat(cleaned);
    return isNaN(n) ? fallback : n;
  }

  /**
   * Normalize an ISO date string or Excel numeric serial date.
   */
  function normalizeDate(rawDate) {
    if (!rawDate) return '';
    // Handle Excel serial date numbers (e.g. 46180)
    if (typeof rawDate === 'number' && rawDate > 25569) {
      const d = new Date(Math.round((rawDate - 25569) * 86400 * 1000));
      return d.toISOString().split('T')[0];
    }
    if (rawDate instanceof Date) {
      return rawDate.toISOString().split('T')[0];
    }
    const s = cleanStr(rawDate);
    // If standard YYYY-MM-DD
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
    // Try standard JS Date parsing
    const d = new Date(s);
    if (!isNaN(d.getTime())) {
      const y = d.getFullYear();
      const m = String(d.getMonth() + 1).padStart(2, '0');
      const day = String(d.getDate()).padStart(2, '0');
      return `${y}-${m}-${day}`;
    }
    return s;
  }

  /**
   * Standardize invoice status into one of: 'Open', 'Overdue', 'Partially Paid', 'Closed'.
   */
  function normalizeStatus(rawStatus, dueDateStr, balance) {
    const s = cleanStr(rawStatus).toLowerCase();
    if (s.includes('overdue')) return 'Overdue';
    if (s.includes('partial')) return 'Partially Paid';
    if (s.includes('paid') || s.includes('closed')) return 'Closed';
    if (s.includes('open') || s.includes('sent') || s.includes('unpaid')) {
      // Check if past due date
      if (dueDateStr) {
        const due = new Date(dueDateStr);
        const today = new Date();
        if (!isNaN(due.getTime()) && due < today && (balance === undefined || balance > 0)) {
          return 'Overdue';
        }
      }
      return 'Open';
    }
    return 'Open';
  }

  /**
   * Determine credit category based on credit days.
   */
  function categorizeCreditDays(days, paymentTerms) {
    const terms = cleanStr(paymentTerms).toLowerCase();
    if (days === 0 || terms === 'cash' || terms.includes('immediate')) {
      return 'Cash';
    }
    if (days <= 30) return '8–30 days';
    if (days <= 60) return '31–60 days';
    return '61–90 days';
  }

  /**
   * Normalize an arbitrary raw record/row into the standard dashboard invoice schema.
   * Handles column name variations from Zoho Books, Excel, CSV, or third-party exports.
   * @param {Object} raw - Raw key-value object
   * @param {number} rowIndex - Index fallback
   * @returns {Object} Normalized invoice item
   */
  function normalizeRecord(raw, rowIndex = 0) {
    if (!raw || typeof raw !== 'object') {
      return null;
    }

    // Lookup case-insensitively across possible alias keys
    function findVal(aliases) {
      const keys = Object.keys(raw);
      for (let alias of aliases) {
        const lower = alias.toLowerCase().replace(/[^a-z0-9]/g, '');
        for (let k of keys) {
          if (k.toLowerCase().replace(/[^a-z0-9]/g, '') === lower) {
            return raw[k];
          }
        }
      }
      return undefined;
    }

    const invoiceNumber = cleanStr(
      findVal(['invoice_number', 'invoice number', 'invoicenumber', 'invoice #', 'inv no', 'invoice_no']) ||
      `INV-UPLOAD-${1000 + rowIndex}`
    );

    const invoiceId = cleanStr(findVal(['invoice_id', 'invoice id', 'id']) || invoiceNumber);

    const customerName = cleanStr(
      findVal(['customer_name', 'customer name', 'customer', 'client_name', 'client', 'company_name', 'contact_name']) ||
      'General Customer'
    );

    const customerId = cleanStr(findVal(['customer_id', 'customer id', 'client_id']) || `CUST-${customerName.replace(/\s+/g, '-').toUpperCase()}`);

    const rawDate = findVal(['date', 'invoice_date', 'invoice date', 'invoicedate', 'inv_date']);
    const dateStr = normalizeDate(rawDate) || '2026-06-01';

    const rawDueDate = findVal(['due_date', 'due date', 'duedate', 'payment_due_date']);
    let dueDateStr = normalizeDate(rawDueDate);

    const paymentTerms = cleanStr(findVal(['payment_terms', 'payment terms', 'terms', 'credit_terms', 'credit terms']) || '30 days');

    // Credit days calculation
    let creditDays = parseNum(findVal(['credit_days', 'credit days', 'creditdays']));
    if (!creditDays && dateStr && dueDateStr) {
      const d1 = new Date(dateStr);
      const d2 = new Date(dueDateStr);
      if (!isNaN(d1.getTime()) && !isNaN(d2.getTime())) {
        const diffMs = d2.getTime() - d1.getTime();
        creditDays = Math.max(0, Math.round(diffMs / (1000 * 60 * 60 * 24)));
      }
    }
    if (!creditDays && paymentTerms) {
      const m = paymentTerms.match(/(\d+)/);
      if (m) creditDays = parseInt(m[1], 10);
      else if (paymentTerms.toLowerCase() === 'cash') creditDays = 0;
      else creditDays = 30;
    }

    if (!dueDateStr && dateStr) {
      const d = new Date(`${dateStr}T00:00:00Z`);
      d.setDate(d.getDate() + creditDays);
      dueDateStr = d.toISOString().split('T')[0];
    }

    const rawAmount = findVal(['total', 'invoice total', 'invoicetotal', 'amount', 'net total', 'grand_total']);
    const rawSubtotal = findVal(['subtotal', 'sub total', 'sub_total', 'item_total']);
    const total = parseNum(rawAmount !== undefined ? rawAmount : rawSubtotal, 0);
    const subtotal = parseNum(rawSubtotal !== undefined ? rawSubtotal : rawAmount, total);

    const paymentMade = parseNum(findVal(['payment_made', 'payment made', 'paid_amount', 'paid']), 0);
    const balance = parseNum(findVal(['balance', 'outstanding', 'due_amount']), Math.max(0, total - paymentMade));

    const rawStatus = findVal(['status', 'invoice_status', 'invoice status', 'state']);
    const status = normalizeStatus(rawStatus, dueDateStr, balance);

    // Brand normalization
    let rawBrand = cleanStr(findVal(['brand', 'brand_name', 'brand name', 'item_brand']));
    let brand = 'Non-Branded';
    if (rawBrand.toLowerCase().includes('nellon')) brand = 'Nellon';
    else if (rawBrand.toLowerCase().includes('raviya')) brand = 'Raviya';
    else if (rawBrand.toLowerCase().includes('non-brand') || rawBrand.toLowerCase().includes('unbranded')) brand = 'Non-Branded';
    else if (rawBrand) brand = rawBrand;

    // Salesperson / POC
    const salesperson = cleanStr(
      findVal(['salesperson', 'salesperson_name', 'sales person', 'poc', 'agent', 'sales_rep', 'rep']) ||
      'Unassigned'
    );

    // Fiscal Year & Month (Financial Period: Jan to Dec)
    const dateParts = dateStr.split('-');
    let fiscalYear = 'FY 2026';
    let monthKey = '2026-06';
    let monthLabel = 'Jun 2026';

    if (dateParts.length >= 2) {
      const y = parseInt(dateParts[0], 10);
      const m = parseInt(dateParts[1], 10);
      monthKey = `${y}-${String(m).padStart(2, '0')}`;
      const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      monthLabel = `${mNames[m - 1] || 'Jun'} ${y}`;
      fiscalYear = `FY ${y}`;
    }

    // Line items (if invoice row itself contains line item fields)
    const itemName = cleanStr(findVal(['item_name', 'item name', 'product_name', 'product', 'description', 'item']));
    const category = cleanStr(findVal(['category', 'category_name', 'item_category', 'product_category']) || 'Rice & Grains');
    const sku = cleanStr(findVal(['sku', 'item_sku', 'item_code', 'product_code']) || (itemName ? `SKU-${itemName.substring(0, 4).toUpperCase()}` : 'SKU-GEN-001'));
    const rate = parseNum(findVal(['rate', 'price', 'unit_price', 'item_rate']), total);
    const quantity = parseNum(findVal(['quantity', 'qty', 'units']), 1);

    const lineItems = raw.line_items || raw.lineItems;
    let finalLineItems = [];
    const rawLineAmount = findVal(['line_amount', 'line amount']);
    const lineAmount = rawLineAmount !== undefined && rawLineAmount !== '' ? parseNum(rawLineAmount, 0) : null;

    if (Array.isArray(lineItems) && lineItems.length > 0) {
      finalLineItems = lineItems.map((li, idx) => ({
        itemId: li.item_id || `ITEM-${idx + 1}`,
        sku: cleanStr(li.sku || li.item_code || `SKU-${idx + 1}`),
        name: cleanStr(li.name || li.item_name || `Product ${idx + 1}`),
        brand: cleanStr(li.brand || brand),
        category: cleanStr(li.category || category),
        rate: parseNum(li.rate, 0),
        quantity: parseNum(li.quantity || li.qty, 1),
        amount: parseNum(li.amount || li.line_amount || li.total, parseNum(li.rate, 0) * parseNum(li.quantity, 1))
      }));
    } else if (itemName) {
      finalLineItems.push({
        itemId: 'ITEM-1',
        sku: sku,
        name: itemName,
        brand: brand,
        category: category,
        rate: rate,
        quantity: quantity,
        amount: lineAmount !== null ? lineAmount : total
      });
    }

    return {
      invoiceId,
      invoiceNumber,
      customerName,
      customerId,
      date: dateStr,
      dueDate: dueDateStr,
      fiscalYear,
      monthKey,
      monthLabel,
      status,
      paymentTerms,
      creditDays,
      creditCategory: categorizeCreditDays(creditDays, paymentTerms),
      brand,
      salesperson,
      subtotal,
      tax: parseNum(findVal(['tax', 'tax_amount', 'vat']), 0),
      total,
      paymentMade,
      balance,
      creditsApplied: parseNum(findVal(['credits_applied', 'credits']), 0),
      currency: 'AED',
      lineItems: finalLineItems
    };
  }

  /**
   * Group flat row items (from CSV/Excel with multiple rows per invoice) into parent invoices.
   */
  function groupRowsIntoInvoices(flatRows = []) {
    const invoiceMap = {};

    flatRows.forEach((row, idx) => {
      const normalized = normalizeRecord(row, idx);
      if (!normalized) return;

      const key = normalized.invoiceNumber || normalized.invoiceId;
      if (!invoiceMap[key]) {
        invoiceMap[key] = {
          ...normalized,
          lineItems: [...normalized.lineItems]
        };
      } else {
        // Append line item and sum totals if row has distinct item
        if (normalized.lineItems.length > 0) {
          invoiceMap[key].lineItems.push(...normalized.lineItems);
        }
      }
    });

    return Object.values(invoiceMap);
  }

  /**
   * Parse uploaded file (Excel .xlsx, .xls or CSV) via SheetJS.
   * @param {File} file - Browser File object
   * @returns {Promise<{ success: boolean, count: number, fileName: string }>}
   */
  function parseUploadedFile(file) {
    return new Promise((resolve, reject) => {
      if (!file) {
        reject(new Error('No file provided for upload.'));
        return;
      }

      const reader = new FileReader();

      reader.onload = function (e) {
        try {
          const data = new Uint8Array(e.target.result);

          // Check if XLSX library is available globally (SheetJS)
          if (typeof window !== 'undefined' && typeof window.XLSX !== 'undefined') {
            const workbook = window.XLSX.read(data, { type: 'array', cellDates: true });
            const firstSheetName = workbook.SheetNames[0];
            const worksheet = workbook.Sheets[firstSheetName];
            const rawJson = window.XLSX.utils.sheet_to_json(worksheet, { defval: '' });

            if (!Array.isArray(rawJson) || rawJson.length === 0) {
              throw new Error('The uploaded file contains no readable rows or sheets.');
            }

            const invoices = groupRowsIntoInvoices(rawJson);

            if (AppState && AppState.setState) {
              AppState.setState({
                rawData: invoices,
                dataSourceLabel: file.name,
                isLoading: false
              });
            }

            resolve({ success: true, count: invoices.length, fileName: file.name });
          } else {
            // Fallback for CSV if SheetJS is not loaded
            const textDecoder = new TextDecoder('utf-8');
            const textContent = textDecoder.decode(data);
            const lines = textContent.split(/\r?\n/).filter((l) => l.trim().length > 0);

            if (lines.length < 2) {
              throw new Error('CSV file must have at least a header row and one data row.');
            }

            // Check delimiter: pipe '|' or comma ','
            const firstLine = lines[0];
            const delimiter = firstLine.includes('|') ? '|' : ',';
            const headers = firstLine.split(delimiter).map((h) => cleanStr(h));

            const rawJson = [];
            for (let i = 1; i < lines.length; i++) {
              const cols = lines[i].split(delimiter);
              const rowObj = {};
              headers.forEach((h, hIdx) => {
                rowObj[h] = cols[hIdx] ? cleanStr(cols[hIdx]) : '';
              });
              rawJson.push(rowObj);
            }

            const invoices = groupRowsIntoInvoices(rawJson);

            if (AppState && AppState.setState) {
              AppState.setState({
                rawData: invoices,
                dataSourceLabel: file.name,
                isLoading: false
              });
            }

            resolve({ success: true, count: invoices.length, fileName: file.name });
          }
        } catch (err) {
          console.error('File parsing failed:', err);
          reject(new Error(`Failed to parse ${file.name}: ${err.message}`));
        }
      };

      reader.onerror = function () {
        reject(new Error(`File read error while reading ${file.name}`));
      };

      reader.readAsArrayBuffer(file);
    });
  }

  /**
   * Load initial application dataset.
   * Checks Zoho Books environment first via ZohoService.
   * If not inside Zoho, falls back smoothly to DEMO_DATA reference dataset.
   * @returns {Promise<{ source: 'zoho'|'demo', count: number }>}
   */
  async function loadInitialData() {
    if (AppState && AppState.setState) {
      AppState.setState({ isLoading: true });
    }

    try {
      // 1. Try Zoho Books first
      if (ZohoService && typeof ZohoService.init === 'function') {
        const zohoStatus = await ZohoService.init();
        if (zohoStatus && zohoStatus.isZoho) {
          const zohoInvoices = await ZohoService.fetchInvoices();
          const normalized = (zohoInvoices || []).map((inv, idx) => normalizeRecord(inv, idx));

          if (AppState && AppState.setState) {
            AppState.setState({
              rawData: normalized,
              isZohoEnv: true,
              dataSourceLabel: 'Zoho Books API',
              isLoading: false
            });
          }
          return { source: 'zoho', count: normalized.length };
        }
      }
    } catch (err) {
      console.warn('Zoho Books loading failed or not in Zoho environment. Falling back to invoice_clean.xlsx.', err);
    }

    // 2. Published workbook beside this page. Demo data is only the last resort.
    try {
      if (typeof window !== 'undefined' && window.XLSX && typeof fetch === 'function') {
        const res = await fetch('invoice_clean.xlsx', { cache: 'no-store' });
        if (res.ok) {
          const buf = await res.arrayBuffer();
          const workbook = window.XLSX.read(buf, { type: 'array', cellDates: true });
          const sheet = workbook.Sheets[workbook.SheetNames[0]];
          const rawJson = window.XLSX.utils.sheet_to_json(sheet, { defval: '' });
          const invoices = groupRowsIntoInvoices(rawJson);
          if (invoices.length) {
            if (AppState && AppState.setState) {
              AppState.setState({
                rawData: invoices,
                isZohoEnv: false,
                dataSourceLabel: 'invoice_clean.xlsx',
                isLoading: false
              });
            }
            return { source: 'file', count: invoices.length };
          }
        }
      }
    } catch (err) {
      console.warn('invoice_clean.xlsx could not be loaded. Falling back to reference demo data.', err);
    }

    // 3. Fallback to reference demo data
    const demo = DEMO_DATA || (typeof window !== 'undefined' ? window.DEMO_DATA : null);
    if (demo && Array.isArray(demo.invoices)) {
      if (AppState && AppState.setState) {
        AppState.setState({
          rawData: demo.invoices,
          previousPeriodInvoices: demo.previousPeriodInvoices || [],
          isZohoEnv: false,
          dataSourceLabel: demo.metadata && demo.metadata.dataSourceLabel ? demo.metadata.dataSourceLabel : 'invoice_clean.xlsx',
          isLoading: false
        });
      }
      return { source: 'demo', count: demo.invoices.length };
    }

    if (AppState && AppState.setState) {
      AppState.setState({ isLoading: false });
    }
    return { source: 'none', count: 0 };
  }

  /**
   * Export tabular data to CSV adhering strictly to the user requirement:
   * "Always use '|' as a separator when creating CSV files."
   * @param {Array<Object>} rows - Array of row objects
   * @param {string} filename - Target filename e.g. "Koyson_Sales_Invoices.csv"
   */
  function exportToCSV(rows = [], filename = 'Koyson_Sales_Export.csv') {
    if (!Array.isArray(rows) || rows.length === 0) {
      console.warn('No data rows available to export.');
      return;
    }

    const headers = Object.keys(rows[0]);
    const DELIMITER = '|'; // Enforced by user rule: Always use '|' as separator

    const lines = [];
    // Header line
    lines.push(headers.join(DELIMITER));

    // Data lines
    rows.forEach((row) => {
      const line = headers.map((h) => {
        let val = row[h];
        if (val === null || val === undefined) return '';
        if (typeof val === 'object') return JSON.stringify(val).replace(/\|/g, '-');
        return String(val).replace(/\|/g, '-').replace(/\r?\n/g, ' ');
      }).join(DELIMITER);
      lines.push(line);
    });

    const csvContent = lines.join('\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });

    if (typeof window !== 'undefined' && window.document) {
      const url = URL.createObjectURL(blob);
      const a = window.document.createElement('a');
      a.href = url;
      a.download = filename;
      window.document.body.appendChild(a);
      a.click();
      window.document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }

    return csvContent;
  }

  return {
    loadInitialData,
    parseUploadedFile,
    normalizeRecord,
    groupRowsIntoInvoices,
    exportToCSV
  };
});
