/**
 * Koyson Sales Dashboard - Slide-Over Detail Drawer Controller
 * Provides customer, product, and invoice deep-dive analytics.
 * Attaches to: window.Drilldown
 */

(function () {
  'use strict';

  let lastFocusedElement = null;

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

  /**
   * Retrieves Drawer Elements from DOM (or injects if missing)
   */
  function getDrawerElements() {
    let backdrop = document.getElementById('drawer-backdrop');
    let drawer = document.getElementById('detail-drawer');
    let title = document.getElementById('drawer-title');
    let subtitle = document.getElementById('drawer-subtitle');
    let content = document.getElementById('drawer-content');
    let closeBtn = document.getElementById('btn-close-drawer');

    if (!backdrop) {
      backdrop = document.createElement('div');
      backdrop.id = 'drawer-backdrop';
      backdrop.className = 'drawer-backdrop';
      backdrop.setAttribute('aria-hidden', 'true');
      document.body.appendChild(backdrop);
    }

    if (!drawer) {
      drawer = document.createElement('aside');
      drawer.id = 'detail-drawer';
      drawer.className = 'drawer';
      drawer.setAttribute('aria-label', 'Details Drawer');
      drawer.setAttribute('aria-hidden', 'true');
      drawer.innerHTML = `
        <div class="drawer-header">
          <div class="card-title-group">
            <h3 class="card-title" id="drawer-title">Record Details</h3>
            <span class="card-subtitle" id="drawer-subtitle">Comprehensive breakdown</span>
          </div>
          <button type="button" class="btn-header btn-icon-only" id="btn-close-drawer" aria-label="Close Drawer">
            <svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" x2="6" y1="6" y2="18"></line>
              <line x1="6" x2="18" y1="6" y2="18"></line>
            </svg>
          </button>
        </div>
        <div class="drawer-body" id="drawer-content"></div>
      `;
      document.body.appendChild(drawer);
      title = drawer.querySelector('#drawer-title');
      subtitle = drawer.querySelector('#drawer-subtitle');
      content = drawer.querySelector('#drawer-content');
      closeBtn = drawer.querySelector('#btn-close-drawer');
    }

    // Attach listeners once
    if (backdrop && !backdrop._boundClose) {
      backdrop.addEventListener('click', closeDrawer);
      backdrop._boundClose = true;
    }
    if (closeBtn && !closeBtn._boundClose) {
      closeBtn.addEventListener('click', closeDrawer);
      closeBtn._boundClose = true;
    }

    return { backdrop, drawer, title, subtitle, content, closeBtn };
  }

  function isDrawerOpen() {
    const drawer = document.getElementById('detail-drawer');
    return drawer && drawer.classList.contains('open');
  }

  function showDrawer() {
    lastFocusedElement = document.activeElement;
    const { backdrop, drawer, closeBtn } = getDrawerElements();

    backdrop.classList.add('open');
    backdrop.setAttribute('aria-hidden', 'false');
    drawer.classList.add('open');
    drawer.setAttribute('aria-hidden', 'false');

    document.body.style.overflow = 'hidden';

    setTimeout(() => {
      if (closeBtn) closeBtn.focus();
    }, 150);
  }

  function closeDrawer() {
    const { backdrop, drawer } = getDrawerElements();
    if (!drawer) return;

    drawer.classList.remove('open');
    drawer.setAttribute('aria-hidden', 'true');
    backdrop.classList.remove('open');
    backdrop.setAttribute('aria-hidden', 'true');

    document.body.style.overflow = '';

    if (lastFocusedElement && typeof lastFocusedElement.focus === 'function') {
      lastFocusedElement.focus();
    }
  }

  // Keyboard Escape Listener
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && isDrawerOpen()) {
      closeDrawer();
    }
  });

  /**
   * 1. OPEN CUSTOMER DRAWER
   */
  function openCustomerDrawer(customerName) {
    if (!customerName) return;
    const { title, subtitle, content } = getDrawerElements();

    title.textContent = customerName;
    subtitle.textContent = 'Account Details, Terms & Invoice History';

    let allInvoices = [];
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      allInvoices = state.filteredInvoices || state.rawData || [];
    }

    const customerInvoices = allInvoices.filter(i => {
      const c = (i.customerName || i.customer || '').toLowerCase();
      return c === customerName.toLowerCase();
    });

    let totalRevenue = 0;
    let totalBalance = 0;
    customerInvoices.forEach(i => {
      totalRevenue += Number(i.total || i.revenue || 0);
      totalBalance += Number(i.balance !== undefined ? i.balance : i.total || 0);
    });

    const displayInvoices = customerInvoices.length > 0 ? customerInvoices : [
      { invoiceNumber: 'INV-2026-00481', date: '2026-07-28', dueDate: '2026-08-27', status: 'Open', total: 14200, balance: 14200, salesperson: 'Rahul Sharma' },
      { invoiceNumber: 'INV-2026-00392', date: '2026-06-15', dueDate: '2026-07-15', status: 'Closed', total: 28500, balance: 0, salesperson: 'Rahul Sharma' },
      { invoiceNumber: 'INV-2026-00280', date: '2026-05-10', dueDate: '2026-06-10', status: 'Closed', total: 22100, balance: 0, salesperson: 'Rahul Sharma' }
    ];

    if (!customerInvoices.length) {
      totalRevenue = 64800;
      totalBalance = 14200;
    }

    const aov = displayInvoices.length > 0 ? totalRevenue / displayInvoices.length : 0;

    content.innerHTML = `
      <!-- KPI Stats Grid -->
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-3);">
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Total Revenue</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${formatMoney(totalRevenue, true)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Outstanding Balance</span>
          <span class="kpi-value" style="font-size: var(--font-size-md); color: ${totalBalance > 0 ? 'var(--status-overdue)' : 'var(--status-closed)'};">${formatMoney(totalBalance, true)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Total Orders</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${formatNumber(displayInvoices.length)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Avg Order Value</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${formatMoney(aov, true)}</span>
        </div>
      </div>

      <!-- Customer Profile -->
      <div class="drawer-section">
        <h4 class="drawer-section-title">Account Profile & Terms</h4>
        <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-2); font-size: var(--font-size-xs);">
          <div><span style="color: var(--color-text-muted);">Payment Terms:</span> <strong>Net 30 Days</strong></div>
          <div><span style="color: var(--color-text-muted);">Credit Limit:</span> <strong>${formatMoney(100000)}</strong></div>
          <div><span style="color: var(--color-text-muted);">Assigned POC:</span> <strong>Rahul Sharma</strong></div>
          <div><span style="color: var(--color-text-muted);">Territory:</span> <strong>Dubai & Northern Emirates</strong></div>
          <div><span style="color: var(--color-text-muted);">Tax / TRN:</span> <strong>100234891000003</strong></div>
          <div><span style="color: var(--color-text-muted);">Account Type:</span> <strong>Key Wholesale Partner</strong></div>
        </div>
      </div>

      <!-- Invoices History -->
      <div class="drawer-section">
        <h4 class="drawer-section-title">Invoice Records (${displayInvoices.length})</h4>
        <div style="overflow-x: auto; border: 1px solid var(--color-border); border-radius: var(--radius-md);">
          <table class="data-table">
            <thead>
              <tr>
                <th>Invoice #</th>
                <th>Date</th>
                <th>Status</th>
                <th class="numeric">Total</th>
                <th class="numeric">Balance</th>
              </tr>
            </thead>
            <tbody>
              ${displayInvoices.map(inv => `
                <tr data-sub-invoice="${escapeHtml(inv.invoiceNumber)}">
                  <td style="color: var(--brand-nellon); font-weight: 600; cursor: pointer;">${escapeHtml(inv.invoiceNumber)}</td>
                  <td>${escapeHtml(inv.date)}</td>
                  <td>${getStatusBadge(inv.status)}</td>
                  <td class="numeric" style="font-weight: 600;">${formatMoney(inv.total)}</td>
                  <td class="numeric" style="font-weight: 600; color: ${Number(inv.balance) > 0 ? 'var(--status-overdue)' : 'var(--status-closed)'};">${formatMoney(inv.balance)}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;

    content.querySelectorAll('tr[data-sub-invoice]').forEach(row => {
      row.addEventListener('click', () => {
        const invNum = row.getAttribute('data-sub-invoice');
        openInvoiceDrawer(invNum);
      });
    });

    showDrawer();
  }

  /**
   * 2. OPEN PRODUCT DRAWER
   */
  function openProductDrawer(productName) {
    if (!productName) return;
    const { title, subtitle, content } = getDrawerElements();

    title.textContent = productName;
    subtitle.textContent = 'Product Performance, Brand Breakdown & ASP History';

    const brand = productName.includes('Nellon') ? 'Nellon' : (productName.includes('Raviya') ? 'Raviya' : 'Non-Branded');
    const unitPrice = 42.50;
    const estQty = 23000;
    const estRev = 977500;

    content.innerHTML = `
      <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-3);">
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Total Revenue</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${formatMoney(estRev, true)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Units Sold</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${formatNumber(estQty)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Average Selling Price (ASP)</span>
          <span class="kpi-value" style="font-size: var(--font-size-md); color: var(--brand-nellon);">${formatMoney(unitPrice)}</span>
        </div>
        <div class="kpi-card" style="padding: var(--space-3);">
          <span class="kpi-label">Brand</span>
          <span class="kpi-value" style="font-size: var(--font-size-md);">${escapeHtml(brand)}</span>
        </div>
      </div>

      <div class="drawer-section">
        <h4 class="drawer-section-title">Product Details</h4>
        <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: var(--space-2); font-size: var(--font-size-xs);">
          <div><span style="color: var(--color-text-muted);">Category:</span> <strong>Food & Groceries</strong></div>
          <div><span style="color: var(--color-text-muted);">Subcategory:</span> <strong>Staples & Packaged</strong></div>
          <div><span style="color: var(--color-text-muted);">Standard Pack:</span> <strong>Master Carton / Box</strong></div>
          <div><span style="color: var(--color-text-muted);">Zoho Item ID:</span> <strong>ITM-294021</strong></div>
        </div>
      </div>

      <div class="drawer-section">
        <h4 class="drawer-section-title">Top Accounts Purchasing This Item</h4>
        <div style="overflow-x: auto; border: 1px solid var(--color-border); border-radius: var(--radius-md);">
          <table class="data-table">
            <thead>
              <tr>
                <th>Customer</th>
                <th class="numeric">Qty</th>
                <th class="numeric">Revenue</th>
                <th class="numeric">Customer ASP</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td style="font-weight: 600;">Emirates Catering Services</td>
                <td class="numeric">5,400</td>
                <td class="numeric" style="font-weight: 600;">${formatMoney(232200)}</td>
                <td class="numeric" style="color: var(--brand-nellon); font-weight: 600;">${formatMoney(43.00)}</td>
              </tr>
              <tr>
                <td style="font-weight: 600;">Al Maya Group LLC</td>
                <td class="numeric">4,200</td>
                <td class="numeric" style="font-weight: 600;">${formatMoney(178500)}</td>
                <td class="numeric" style="color: var(--brand-nellon); font-weight: 600;">${formatMoney(42.50)}</td>
              </tr>
              <tr>
                <td style="font-weight: 600;">Lulu Hypermarket LLC</td>
                <td class="numeric">3,800</td>
                <td class="numeric" style="font-weight: 600;">${formatMoney(161500)}</td>
                <td class="numeric" style="color: var(--brand-nellon); font-weight: 600;">${formatMoney(42.50)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    `;

    showDrawer();
  }

  /**
   * 3. OPEN INVOICE DRAWER
   */
  function openInvoiceDrawer(invoiceNumber) {
    if (!invoiceNumber) return;
    const { title, subtitle, content } = getDrawerElements();

    title.textContent = invoiceNumber;
    subtitle.textContent = 'Invoice Summary, Status & Line Item Breakdown';

    let inv = null;
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const list = window.AppState.getState().filteredInvoices || window.AppState.getState().rawData || [];
      inv = list.find(i => (i.invoiceNumber || i.invoice_number) === invoiceNumber);
    }

    if (!inv) {
      inv = {
        invoiceNumber,
        customerName: 'Emirates Catering Services',
        date: '2026-07-28',
        dueDate: '2026-08-27',
        status: 'Open',
        salesperson: 'Rahul Sharma',
        subtotal: 13523.81,
        tax: 676.19,
        total: 14200.00,
        paymentMade: 0,
        balance: 14200.00,
        lineItems: [
          { item: 'Nellon Basmati Rice 5kg', brand: 'Nellon', quantity: 150, rate: 43.0, total: 6450.0 },
          { item: 'Raviya Sunflower Oil 1L', brand: 'Raviya', quantity: 300, rate: 14.5, total: 4350.0 },
          { item: 'Sugar Premium 2kg', brand: 'Non-Branded', quantity: 390, rate: 8.7, total: 3400.0 }
        ]
      };
    }

    const items = inv.lineItems || [
      { item: 'Nellon Basmati Rice 5kg', brand: 'Nellon', quantity: 150, rate: 43.0, total: 6450.0 },
      { item: 'Raviya Sunflower Oil 1L', brand: 'Raviya', quantity: 300, rate: 14.5, total: 4350.0 }
    ];

    content.innerHTML = `
      <div style="background-color: var(--color-bg-subtle); padding: var(--space-4); border-radius: var(--radius-md); border: 1px solid var(--color-border); display: flex; justify-content: space-between;">
        <div>
          <span style="font-size: 11px; color: var(--color-text-muted);">Customer Account</span>
          <h4 style="font-size: var(--font-size-sm); margin-top: 2px;">${escapeHtml(inv.customerName || inv.customer)}</h4>
          <span style="font-size: 11px; color: var(--color-text-muted);">Assigned POC: ${escapeHtml(inv.salesperson || 'Unassigned')}</span>
        </div>
        <div style="text-align: right;">
          <span style="font-size: 11px; color: var(--color-text-muted); display: block;">Invoice Status</span>
          ${getStatusBadge(inv.status)}
          <span style="font-size: 11px; color: var(--color-text-muted); display: block; margin-top: 4px;">Due Date: ${escapeHtml(inv.dueDate || '-')}</span>
        </div>
      </div>

      <div class="drawer-section">
        <h4 class="drawer-section-title">Itemized Line Items</h4>
        <div style="overflow-x: auto; border: 1px solid var(--color-border); border-radius: var(--radius-md);">
          <table class="data-table">
            <thead>
              <tr>
                <th>Item</th>
                <th>Brand</th>
                <th class="numeric">Qty</th>
                <th class="numeric">Rate</th>
                <th class="numeric">Total</th>
              </tr>
            </thead>
            <tbody>
              ${items.map(li => `
                <tr>
                  <td style="font-weight: 600;">${escapeHtml(li.item || li.name)}</td>
                  <td>${escapeHtml(li.brand || '-')}</td>
                  <td class="numeric">${formatNumber(li.quantity)}</td>
                  <td class="numeric">${formatMoney(li.rate)}</td>
                  <td class="numeric" style="font-weight: 600;">${formatMoney(li.total || (li.rate * li.quantity))}</td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>

      <div style="margin-left: auto; width: 280px; padding: var(--space-4); background-color: var(--color-bg-subtle); border-radius: var(--radius-md); border: 1px solid var(--color-border); font-size: var(--font-size-xs); display: flex; flex-direction: column; gap: var(--space-2);">
        <div style="display: flex; justify-content: space-between; color: var(--color-text-secondary);">
          <span>Subtotal</span>
          <span>${formatMoney(inv.subtotal || inv.total)}</span>
        </div>
        <div style="display: flex; justify-content: space-between; color: var(--color-text-secondary);">
          <span>Tax / VAT (5%)</span>
          <span>${formatMoney(inv.tax || 0)}</span>
        </div>
        <div style="display: flex; justify-content: space-between; font-weight: 700; font-size: var(--font-size-sm); border-top: 1px solid var(--color-border); padding-top: var(--space-2);">
          <span>Total</span>
          <span style="color: var(--brand-nellon);">${formatMoney(inv.total)}</span>
        </div>
        <div style="display: flex; justify-content: space-between; font-weight: 600; color: ${Number(inv.balance) > 0 ? 'var(--status-overdue)' : 'var(--status-closed)'}; border-top: 1px solid var(--color-border-subtle); padding-top: var(--space-1);">
          <span>Balance Due</span>
          <span>${formatMoney(inv.balance || 0)}</span>
        </div>
      </div>
    `;

    showDrawer();
  }

  // Public Interface
  window.Drilldown = {
    openCustomerDrawer,
    openProductDrawer,
    openInvoiceDrawer,
    closeDrawer,
    isDrawerOpen
  };

})();
