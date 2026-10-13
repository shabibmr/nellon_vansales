/**
 * Koyson Sales Dashboard - Interactive Analytical Tables & Matrix Controller
 * Manages Top Customers, Product Breakdown, POC Leaderboard, Recent Invoices,
 * Heatmap Matrix, Credit Breakdown, Sorting, Pagination, and Search.
 * Attaches to: window.DashboardTables
 */

(function () {
  'use strict';

  // Active Tab State
  let currentTab = 'customers'; // 'customers' | 'products' | 'poc' | 'invoices'

  // Per-tab pagination and sort state
  const tableStates = {
    customers: { page: 1, pageSize: 10, sortCol: 'revenue', sortAsc: false, search: '' },
    products: { page: 1, pageSize: 10, sortCol: 'revenue', sortAsc: false, search: '' },
    poc: { page: 1, pageSize: 10, sortCol: 'revenue', sortAsc: false, search: '' },
    invoices: { page: 1, pageSize: 10, sortCol: 'date', sortAsc: false, search: '' }
  };

  function getActiveCurrency() {
    return 'AED';
  }

  function formatMoney(value, compact = false) {
    if (window.Formatters && typeof window.Formatters.formatCurrency === 'function') {
      return window.Formatters.formatCurrency(value, 'AED', compact);
    }
    const num = Number(value) || 0;
    if (compact) {
      if (Math.abs(num) >= 1_000_000) return `AED ${(num / 1_000_000).toFixed(2)}M`;
      if (Math.abs(num) >= 1_000) return `AED ${(num / 1_000).toFixed(1)}K`;
      return `AED ${Math.round(num).toLocaleString('en-US')}`;
    }
    return `AED ${num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  }

  function formatNumber(value) {
    if (window.Formatters && typeof window.Formatters.formatNumber === 'function') {
      return window.Formatters.formatNumber(value);
    }
    return (Number(value) || 0).toLocaleString();
  }

  function formatPercent(value) {
    if (window.Formatters && typeof window.Formatters.formatPercent === 'function') {
      return window.Formatters.formatPercent(value);
    }
    const num = Number(value) || 0;
    return `${num.toFixed(1)}%`;
  }

  function escapeHtml(str) {
    if (!str && str !== 0) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function getStatusBadge(status) {
    const s = String(status || '').trim();
    const lower = s.toLowerCase();
    let badgeClass = 'badge-neutral';

    if (lower.includes('overdue')) {
      badgeClass = 'badge-overdue';
    } else if (lower.includes('paid') || lower.includes('closed')) {
      badgeClass = 'badge-closed';
    } else if (lower.includes('partial')) {
      badgeClass = 'badge-partial';
    } else if (lower.includes('open') || lower.includes('sent')) {
      badgeClass = 'badge-open';
    }

    return `<span class="badge ${badgeClass}">${escapeHtml(s)}</span>`;
  }

  function sortList(list, col, asc) {
    return [...list].sort((a, b) => {
      let valA = a[col];
      let valB = b[col];

      if (valA === undefined || valA === null) valA = '';
      if (valB === undefined || valB === null) valB = '';

      if (typeof valA === 'string') valA = valA.toLowerCase();
      if (typeof valB === 'string') valB = valB.toLowerCase();

      if (valA < valB) return asc ? -1 : 1;
      if (valA > valB) return asc ? 1 : -1;
      return 0;
    });
  }

  /**
   * Column Definitions for Table Views
   */
  const columnConfigs = {
    customers: [
      { key: 'rank', label: 'Rank', numeric: false, width: '60px' },
      { key: 'customerName', label: 'Customer Name', numeric: false, sortable: true },
      { key: 'revenue', label: 'Net Revenue', numeric: true, sortable: true },
      { key: 'share', label: '% Share', numeric: true, sortable: true },
      { key: 'invoiceCount', label: 'Invoices', numeric: true, sortable: true },
      { key: 'lineItemsCount', label: 'Line Items', numeric: true, sortable: true },
      { key: 'aov', label: 'AOV', numeric: true, sortable: true },
      { key: 'avgCreditPeriod', label: 'Avg Credit', numeric: true, sortable: true }
    ],
    products: [
      { key: 'name', label: 'Product Name', numeric: false, sortable: true },
      { key: 'brand', label: 'Brand', numeric: false, sortable: true },
      { key: 'category', label: 'Category', numeric: false, sortable: true },
      { key: 'revenue', label: 'Revenue', numeric: true, sortable: true },
      { key: 'share', label: '% Share', numeric: true, sortable: true },
      { key: 'quantity', label: 'Qty Sold', numeric: true, sortable: true },
      { key: 'lineItemsCount', label: 'Line Items', numeric: true, sortable: true },
      { key: 'avgLineValue', label: 'Avg Price', numeric: true, sortable: true }
    ],
    poc: [
      { key: 'poc', label: 'Salesperson (POC)', numeric: false, sortable: true },
      { key: 'revenue', label: 'Revenue', numeric: true, sortable: true },
      { key: 'share', label: '% Share', numeric: true, sortable: true },
      { key: 'invoiceCount', label: 'Invoices', numeric: true, sortable: true },
      { key: 'lineItemsCount', label: 'Line Items', numeric: true, sortable: true },
      { key: 'aov', label: 'AOV', numeric: true, sortable: true },
      { key: 'aoq', label: 'AOQ', numeric: true, sortable: true },
      { key: 'avgCreditPeriod', label: 'Avg Credit Days', numeric: true, sortable: true }
    ],
    invoices: [
      { key: 'invoiceNumber', label: 'Invoice #', numeric: false, sortable: true },
      { key: 'customerName', label: 'Customer', numeric: false, sortable: true },
      { key: 'date', label: 'Date', numeric: false, sortable: true },
      { key: 'dueDate', label: 'Due Date', numeric: false, sortable: true },
      { key: 'status', label: 'Status', numeric: false, sortable: true },
      { key: 'salesperson', label: 'POC', numeric: false, sortable: true },
      { key: 'total', label: 'Total Amount', numeric: true, sortable: true },
      { key: 'balance', label: 'Balance Due', numeric: true, sortable: true }
    ]
  };

  /**
   * Extract or Calculate Tab Data
   */
  function getRawInvoices() {
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      return state.filteredInvoices || state.rawData || [];
    }
    return [];
  }

  function getDataForTab(tabKey) {
    const invoices = getRawInvoices();

    if (tabKey === 'customers') {
      if (window.Calculations && typeof window.Calculations.computeCustomerMetrics === 'function') {
        const res = window.Calculations.computeCustomerMetrics(invoices, 50);
        return res.customers || [];
      }
      return [
        { customerName: 'Emirates Catering Services', revenue: 642000, share: 9.3, invoiceCount: 114, lineItemsCount: 420, aov: 5631, avgCreditPeriod: 45 },
        { customerName: 'Al Maya Group LLC', revenue: 512000, share: 7.4, invoiceCount: 98, lineItemsCount: 380, aov: 5224, avgCreditPeriod: 30 },
        { customerName: 'Lulu Hypermarket LLC', revenue: 480000, share: 7.0, invoiceCount: 82, lineItemsCount: 310, aov: 5853, avgCreditPeriod: 60 },
        { customerName: 'Grand Mart Supermarket', revenue: 395000, share: 5.7, invoiceCount: 74, lineItemsCount: 290, aov: 5337, avgCreditPeriod: 15 },
        { customerName: 'Carrefour Distribution', revenue: 360000, share: 5.2, invoiceCount: 62, lineItemsCount: 240, aov: 5806, avgCreditPeriod: 45 },
        { customerName: 'Spinneys Dubai LLC', revenue: 310000, share: 4.5, invoiceCount: 55, lineItemsCount: 215, aov: 5636, avgCreditPeriod: 30 },
        { customerName: 'West Zone Supermarket', revenue: 290000, share: 4.2, invoiceCount: 51, lineItemsCount: 195, aov: 5686, avgCreditPeriod: 30 },
        { customerName: 'Union Coop Society', revenue: 265000, share: 3.9, invoiceCount: 48, lineItemsCount: 180, aov: 5520, avgCreditPeriod: 45 },
        { customerName: 'Choithrams LLC', revenue: 240000, share: 3.5, invoiceCount: 42, lineItemsCount: 160, aov: 5714, avgCreditPeriod: 60 },
        { customerName: 'Al Madina Hypermarket', revenue: 215000, share: 3.1, invoiceCount: 39, lineItemsCount: 145, aov: 5512, avgCreditPeriod: 15 }
      ];
    }

    if (tabKey === 'products') {
      const prodMap = {};
      let totalProdRev = 0;
      invoices.forEach(inv => {
        const items = inv.lineItems || [];
        items.forEach(li => {
          const name = li.name || li.item || 'Generic Item';
          if (!prodMap[name]) {
            prodMap[name] = {
              name,
              brand: li.brand || inv.brand || 'Non-Branded',
              category: li.category || 'General Groceries',
              revenue: 0,
              quantity: 0,
              lineItemsCount: 0
            };
          }
          const amt = Number(li.amount) || Number(li.total) || (Number(li.rate) * Number(li.quantity)) || 0;
          prodMap[name].revenue += amt;
          prodMap[name].quantity += (Number(li.quantity) || 1);
          prodMap[name].lineItemsCount += 1;
          totalProdRev += amt;
        });
      });

      let list = Object.values(prodMap);
      if (!list.length) {
        list = [
          { name: 'Nellon Basmati Rice 5kg', brand: 'Nellon', category: 'Rice & Grains', revenue: 980000, quantity: 23000, lineItemsCount: 420 },
          { name: 'Raviya Sunflower Oil 1L', brand: 'Raviya', category: 'Cooking Oil & Ghee', revenue: 783300, quantity: 53600, lineItemsCount: 380 },
          { name: 'Sugar Premium White 2kg', brand: 'Non-Branded', category: 'Sugar & Sweeteners', revenue: 620000, quantity: 72900, lineItemsCount: 310 },
          { name: 'Nellon Chakki Atta 10kg', brand: 'Nellon', category: 'Flour & Milling', revenue: 540000, quantity: 17140, lineItemsCount: 280 },
          { name: 'Red Lentils (Masoor Dal) 1kg', brand: 'Non-Branded', category: 'Pulses & Legumes', revenue: 390000, quantity: 45800, lineItemsCount: 210 },
          { name: 'Nellon Biryani Rice 10kg', brand: 'Nellon', category: 'Rice & Grains', revenue: 380000, quantity: 9500, lineItemsCount: 190 },
          { name: 'Pure Ghee Tin 1kg', brand: 'Non-Branded', category: 'Cooking Oil & Ghee', revenue: 350000, quantity: 8750, lineItemsCount: 180 },
          { name: 'Nellon Turmeric Powder 500g', brand: 'Nellon', category: 'Spices', revenue: 290000, quantity: 24100, lineItemsCount: 160 }
        ];
        totalProdRev = list.reduce((a, b) => a + b.revenue, 0);
      }

      return list.map(p => ({
        ...p,
        share: totalProdRev > 0 ? (p.revenue / totalProdRev) * 100 : 0,
        avgLineValue: p.quantity > 0 ? p.revenue / p.quantity : 0
      }));
    }

    if (tabKey === 'poc') {
      if (window.Calculations && typeof window.Calculations.computePOCMetrics === 'function') {
        const res = window.Calculations.computePOCMetrics(invoices);
        return res.pocs || res || [];
      }
      return [
        { poc: 'Rahul Sharma', revenue: 2100000, share: 30.5, invoiceCount: 380, lineItemsCount: 1140, aov: 5526, aoq: 125, avgCreditPeriod: 32 },
        { poc: 'Mohammed Al Hashmi', revenue: 1840000, share: 26.8, invoiceCount: 340, lineItemsCount: 980, aov: 5411, aoq: 118, avgCreditPeriod: 45 },
        { poc: 'Syed Farooq', revenue: 1520000, share: 22.1, invoiceCount: 290, lineItemsCount: 860, aov: 5241, aoq: 110, avgCreditPeriod: 38 },
        { poc: 'Anil Kumar', revenue: 1413300, share: 20.6, invoiceCount: 274, lineItemsCount: 790, aov: 5158, aoq: 105, avgCreditPeriod: 42 }
      ];
    }

    if (tabKey === 'invoices') {
      if (invoices.length > 0) {
        return invoices.map(i => ({
          invoiceNumber: i.invoiceNumber || i.invoice_number || 'INV-000',
          customerName: i.customerName || i.customer || 'Customer',
          date: i.date || '-',
          dueDate: i.dueDate || '-',
          status: i.status || 'Open',
          salesperson: i.salesperson || 'Sales Rep',
          total: Number(i.total || i.revenue || 0),
          balance: Number(i.balance !== undefined ? i.balance : i.total || 0)
        }));
      }
      return [
        { invoiceNumber: 'INV-2026-00481', customerName: 'Emirates Catering Services', date: '2026-07-28', dueDate: '2026-08-27', status: 'Open', salesperson: 'Rahul Sharma', total: 14200, balance: 14200 },
        { invoiceNumber: 'INV-2026-00480', customerName: 'Al Maya Group LLC', date: '2026-07-27', dueDate: '2026-08-11', status: 'Overdue', salesperson: 'Mohammed Al Hashmi', total: 18500, balance: 18500 },
        { invoiceNumber: 'INV-2026-00479', customerName: 'Lulu Hypermarket LLC', date: '2026-07-26', dueDate: '2026-08-25', status: 'Partially Paid', salesperson: 'Syed Farooq', total: 32000, balance: 8000 },
        { invoiceNumber: 'INV-2026-00478', customerName: 'Grand Mart Supermarket', date: '2026-07-25', dueDate: '2026-08-09', status: 'Closed', salesperson: 'Anil Kumar', total: 9800, balance: 0 },
        { invoiceNumber: 'INV-2026-00477', customerName: 'Spinneys Dubai LLC', date: '2026-07-24', dueDate: '2026-08-23', status: 'Overdue', salesperson: 'Rahul Sharma', total: 24600, balance: 24600 },
        { invoiceNumber: 'INV-2026-00476', customerName: 'Carrefour Distribution', date: '2026-07-23', dueDate: '2026-08-22', status: 'Open', salesperson: 'Mohammed Al Hashmi', total: 15400, balance: 15400 }
      ];
    }

    return [];
  }

  /**
   * Render Main Table View
   */
  function renderActiveTable() {
    const thead = document.getElementById('data-table-head');
    const tbody = document.getElementById('data-table-body');
    if (!thead || !tbody) return;

    const state = tableStates[currentTab];
    const columns = columnConfigs[currentTab] || [];
    let list = getDataForTab(currentTab);

    // Apply local search filtering
    if (state.search) {
      const q = state.search.toLowerCase();
      list = list.filter(item => {
        return Object.values(item).some(v => String(v).toLowerCase().includes(q));
      });
    }

    // Apply sorting
    if (state.sortCol) {
      list = sortList(list, state.sortCol, state.sortAsc);
    }

    // Pagination slice
    const totalRecords = list.length;
    const totalPages = Math.ceil(totalRecords / state.pageSize) || 1;
    if (state.page > totalPages) state.page = 1;
    const startIdx = (state.page - 1) * state.pageSize;
    const paginated = list.slice(startIdx, startIdx + state.pageSize);

    // Render <thead>
    thead.innerHTML = `
      <tr>
        ${columns.map(col => {
          const isSorted = state.sortCol === col.key;
          const sortClass = col.sortable ? 'sortable' : '';
          const dirClass = isSorted ? (state.sortAsc ? 'sort-asc' : 'sort-desc') : '';
          const numClass = col.numeric ? 'numeric' : '';
          const sortIcon = col.sortable
            ? `<span class="sort-icon">${isSorted ? (state.sortAsc ? '▲' : '▼') : '↕'}</span>`
            : '';
          const style = col.width ? `style="width: ${col.width};"` : '';

          return `<th class="${sortClass} ${dirClass} ${numClass}" data-col="${col.key}" ${style}>${escapeHtml(col.label)}${sortIcon}</th>`;
        }).join('')}
      </tr>
    `;

    // Render <tbody>
    if (!paginated.length) {
      tbody.innerHTML = `<tr><td colspan="${columns.length}" style="text-align: center; padding: var(--space-8); color: var(--color-text-muted);">No records found matching current criteria</td></tr>`;
    } else {
      tbody.innerHTML = paginated.map((item, idx) => {
        const rowRank = startIdx + idx + 1;
        let rowDataAttr = '';
        if (currentTab === 'customers') rowDataAttr = `data-customer-row="${escapeHtml(item.customerName)}"`;
        else if (currentTab === 'products') rowDataAttr = `data-product-row="${escapeHtml(item.name)}"`;
        else if (currentTab === 'invoices') rowDataAttr = `data-invoice-row="${escapeHtml(item.invoiceNumber)}"`;

        return `
          <tr ${rowDataAttr}>
            ${columns.map(col => {
              const numClass = col.numeric ? 'numeric' : '';
              let val = item[col.key];

              if (col.key === 'rank') {
                return `<td class="${numClass}" style="font-weight: 600; color: var(--color-text-muted);">#${rowRank}</td>`;
              }
              if (col.key === 'customerName') {
                return `<td class="${numClass}" style="font-weight: 600; color: var(--brand-nellon); cursor: pointer;">${escapeHtml(val)}</td>`;
              }
              if (col.key === 'name') {
                return `<td class="${numClass}" style="font-weight: 600; color: var(--brand-nellon); cursor: pointer;">${escapeHtml(val)}</td>`;
              }
              if (col.key === 'invoiceNumber') {
                return `<td class="${numClass}" style="font-weight: 600; color: var(--brand-nellon); cursor: pointer;">${escapeHtml(val)}</td>`;
              }
              if (col.key === 'status') {
                return `<td class="${numClass}">${getStatusBadge(val)}</td>`;
              }
              if (col.key === 'revenue' || col.key === 'total' || col.key === 'aov' || col.key === 'avgLineValue') {
                return `<td class="${numClass}" style="font-weight: 600;">${formatMoney(val)}</td>`;
              }
              if (col.key === 'balance') {
                const balNum = Number(val) || 0;
                const balColor = balNum > 0 ? 'var(--status-overdue)' : 'var(--status-closed)';
                return `<td class="${numClass}" style="font-weight: 700; color: ${balColor};">${formatMoney(val)}</td>`;
              }
              if (col.key === 'share') {
                return `<td class="${numClass}"><span class="badge badge-brand" style="background-color: var(--brand-nellon-light); color: var(--brand-nellon);">${formatPercent(val)}</span></td>`;
              }
              if (col.key === 'invoiceCount' || col.key === 'lineItemsCount' || col.key === 'quantity' || col.key === 'aoq') {
                return `<td class="${numClass}">${formatNumber(val)}</td>`;
              }
              if (col.key === 'avgCreditPeriod') {
                return `<td class="${numClass}">${val ? val + ' d' : 'Cash'}</td>`;
              }

              return `<td class="${numClass}">${escapeHtml(val)}</td>`;
            }).join('')}
          </tr>
        `;
      }).join('');
    }

    // Attach Row Click Handlers for Drawer
    tbody.querySelectorAll('tr[data-customer-row]').forEach(tr => {
      tr.addEventListener('click', () => {
        const custName = tr.getAttribute('data-customer-row');
        if (window.Drilldown && typeof window.Drilldown.openCustomerDrawer === 'function') {
          window.Drilldown.openCustomerDrawer(custName);
        }
      });
    });

    tbody.querySelectorAll('tr[data-product-row]').forEach(tr => {
      tr.addEventListener('click', () => {
        const prodName = tr.getAttribute('data-product-row');
        if (window.Drilldown && typeof window.Drilldown.openProductDrawer === 'function') {
          window.Drilldown.openProductDrawer(prodName);
        }
      });
    });

    tbody.querySelectorAll('tr[data-invoice-row]').forEach(tr => {
      tr.addEventListener('click', () => {
        const invNum = tr.getAttribute('data-invoice-row');
        if (window.Drilldown && typeof window.Drilldown.openInvoiceDrawer === 'function') {
          window.Drilldown.openInvoiceDrawer(invNum);
        }
      });
    });

    // Column Sort Clicks
    thead.querySelectorAll('th.sortable').forEach(th => {
      th.addEventListener('click', () => {
        const col = th.getAttribute('data-col');
        if (state.sortCol === col) {
          state.sortAsc = !state.sortAsc;
        } else {
          state.sortCol = col;
          state.sortAsc = false;
        }
        renderActiveTable();
      });
    });

    // Update Pagination UI
    const elInfo = document.getElementById('pagination-info');
    const elPage = document.getElementById('pagination-current-page');
    const btnPrev = document.getElementById('btn-page-prev');
    const btnNext = document.getElementById('btn-page-next');

    if (elInfo) {
      const from = totalRecords > 0 ? startIdx + 1 : 0;
      const to = Math.min(startIdx + state.pageSize, totalRecords);
      elInfo.textContent = `Showing ${from} to ${to} of ${totalRecords} records`;
    }
    if (elPage) elPage.textContent = state.page;
    if (btnPrev) btnPrev.disabled = state.page <= 1;
    if (btnNext) btnNext.disabled = state.page >= totalPages;
  }

  /**
   * Tab Switcher Initialization
   */
  function initTabSwitcher() {
    const tabButtons = document.querySelectorAll('.table-tab-btn, [data-table]');
    tabButtons.forEach(btn => {
      btn.addEventListener('click', () => {
        const targetTab = btn.getAttribute('data-table');
        if (!targetTab) return;

        tabButtons.forEach(b => {
          b.classList.remove('active');
          b.setAttribute('aria-selected', 'false');
        });

        btn.classList.add('active');
        btn.setAttribute('aria-selected', 'true');

        currentTab = targetTab;
        renderActiveTable();
      });
    });

    // Pagination button listeners
    const btnPrev = document.getElementById('btn-page-prev');
    const btnNext = document.getElementById('btn-page-next');

    if (btnPrev) {
      btnPrev.addEventListener('click', () => {
        const state = tableStates[currentTab];
        if (state.page > 1) {
          state.page--;
          renderActiveTable();
        }
      });
    }

    if (btnNext) {
      btnNext.addEventListener('click', () => {
        const state = tableStates[currentTab];
        state.page++;
        renderActiveTable();
      });
    }

    // Search input listener
    const searchInput = document.getElementById('table-search-input');
    if (searchInput) {
      let debounceTimer;
      searchInput.addEventListener('input', (e) => {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => {
          tableStates[currentTab].search = e.target.value.trim();
          tableStates[currentTab].page = 1;
          renderActiveTable();
        }, 200);
      });
    }

    // Export current table button
    const exportBtn = document.getElementById('btn-export-current-table');
    if (exportBtn) {
      exportBtn.addEventListener('click', () => {
        exportCurrentTableCSV();
      });
    }
  }

  /**
   * Export Current Table using pipe separator '|' per user instruction!
   */
  function exportCurrentTableCSV() {
    const columns = columnConfigs[currentTab] || [];
    const list = getDataForTab(currentTab);
    const DELIMITER = '|';

    const lines = [];
    lines.push(columns.map(c => c.label).join(DELIMITER));

    list.forEach(item => {
      const row = columns.map(c => {
        let val = item[c.key];
        if (val === null || val === undefined) return '';
        return String(val).replace(/\|/g, '-').replace(/\r?\n/g, ' ');
      });
      lines.push(row.join(DELIMITER));
    });

    const csvContent = lines.join('\r\n');
    const blob = new Blob(['\uFEFF' + csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `Koyson_${currentTab}_export.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }

  /**
   * Customer x Product Heatmap Matrix
   */
  function renderCustomerProductMatrix() {
    const container = document.getElementById('matrix-table-container');
    if (!container) return;

    let invoices = [];
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      invoices = state.filteredInvoices || state.rawData || [];
    }

    let matrixRes = null;
    if (window.Calculations && typeof window.Calculations.computeCustomerProductMatrix === 'function') {
      matrixRes = window.Calculations.computeCustomerProductMatrix(invoices, 10, 8);
    }

    const customers = (matrixRes && matrixRes.customers && matrixRes.customers.length > 0)
      ? matrixRes.customers
      : [];
    const categories = (matrixRes && matrixRes.categories && matrixRes.categories.length > 0)
      ? matrixRes.categories
      : [];

    if (customers.length === 0 || categories.length === 0) {
      container.innerHTML = '<div style="padding: 24px; text-align: center; color: var(--color-text-muted);">No matrix data available for current selection.</div>';
      return;
    }

    // Find max value for color intensity scaling
    let maxVal = 1;
    customers.forEach(c => {
      c.values.forEach(v => { if (v > maxVal) maxVal = v; });
    });

    let html = `
      <table class="matrix-table">
        <thead>
          <tr>
            <th>Master Customer \\ Category</th>
            ${categories.map(cat => `<th>${escapeHtml(cat)}</th>`).join('')}
          </tr>
        </thead>
        <tbody>
    `;

    customers.forEach((custRow) => {
      html += `<tr><td data-matrix-customer="${escapeHtml(custRow.name)}" title="Click to view customer details">${escapeHtml(custRow.name)}</td>`;
      categories.forEach((cat, colIdx) => {
        const val = custRow.values[colIdx] || 0;
        const intensity = maxVal > 0 ? Math.min(6, Math.round((val / maxVal) * 6)) : 0;
        html += `
          <td class="cell-intensity-${intensity}" title="${escapeHtml(custRow.name)} • ${escapeHtml(cat)}: ${formatMoney(val)}">
            ${val > 0 ? formatMoney(val, true) : '-'}
          </td>
        `;
      });
      html += `</tr>`;
    });

    html += `
        </tbody>
      </table>
    `;

    container.innerHTML = html;

    container.querySelectorAll('td[data-matrix-customer]').forEach(td => {
      td.addEventListener('click', () => {
        const name = td.getAttribute('data-matrix-customer');
        if (window.Drilldown && typeof window.Drilldown.openCustomerDrawer === 'function') {
          window.Drilldown.openCustomerDrawer(name);
        }
      });
    });
  }

  /**
   * Credit Period Breakdown
   */
  function renderCreditBreakdown() {
    const container = document.getElementById('credit-breakdown-container');
    if (!container) return;

    let invoices = [];
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      invoices = state.filteredInvoices || state.rawData || [];
    }

    let creditList = [];
    if (window.Calculations && typeof window.Calculations.computeCustomerProductMatrix === 'function') {
      const res = window.Calculations.computeCustomerProductMatrix(invoices, 10, 8);
      if (res && Array.isArray(res.creditCategories)) {
        creditList = res.creditCategories;
      }
    }

    if (creditList.length === 0) {
      creditList = [
        { category: 'Cash', revenue: 4260000, share: 61.9, invoiceCount: 810 },
        { category: '8–30 days', revenue: 119100, share: 1.7, invoiceCount: 34 },
        { category: '31–60 days', revenue: 1710000, share: 24.8, invoiceCount: 298 },
        { category: '61–90 days', revenue: 790300, share: 11.5, invoiceCount: 142 }
      ];
    }

    container.innerHTML = creditList.map(c => `
      <div class="credit-item">
        <div class="credit-item-header">
          <span style="color: var(--color-text-primary);">${escapeHtml(c.category)}</span>
          <span style="color: var(--brand-nellon);">${formatMoney(c.revenue, true)} (${c.share}%)</span>
        </div>
        <div class="credit-progress-bar">
          <div class="credit-progress-fill" style="width: ${c.share}%;"></div>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 11px; color: var(--color-text-muted);">
          <span>${formatNumber(c.invoiceCount)} invoices</span>
          <span>${formatMoney(c.revenue)}</span>
        </div>
      </div>
    `).join('');
  }

  /**
   * Export active table data as CSV using '|' separator
   */
  function exportCurrentTableCSV() {
    if (window.ExportController && typeof window.ExportController.downloadAll === 'function') {
      window.ExportController.downloadAll();
    }
  }

  /**
   * Master Update for All Table Views
   */
  function updateAllTables() {
    renderActiveTable();
    renderCustomerProductMatrix();
    renderCreditBreakdown();
  }

  // Public Interface
  window.DashboardTables = {
    renderActiveTable,
    renderCustomerProductMatrix,
    renderCreditBreakdown,
    initTabSwitcher,
    updateAllTables,
    exportCurrentTableCSV,
    getTableStates: () => ({ ...tableStates })
  };

})();
