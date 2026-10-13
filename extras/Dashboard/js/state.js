/**
 * Koyson Sales Dashboard - Reactive State Store
 * Centralized pub/sub state manager for filters, data slices, currency, and drill-downs.
 * Automatically handles filter recalculations without full-page reloads.
 * Compatible with Browser (window.AppState) and Node.js.
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.AppState = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DEFAULT_SKUS = ['SKU-BASMATI-5KG', 'SKU-OIL-1.8L', 'SKU-TEA-400G'];

  const DEFAULT_FILTERS = {
    status: 'all', // 'all' | 'Open' | 'Overdue' | 'Partially Paid' | 'Closed'
    brand: 'all', // 'all' | 'Nellon' | 'Non-Branded' | 'Raviya'
    fy: 'FY 2026', // 'FY 2026' | 'FY 2025' (Jan - Dec)
    period: 'Full FY', // 'Full FY' | 'Q1' | 'Q2' | 'Q3' | 'Q4' | 'H1' | 'H2'
    month: 'all', // 'all' | 'Jan 2026' .. 'Dec 2026'
    comparePeriod: false, // boolean
    search: '' // search term string
  };

  const state = {
    rawData: [],
    filteredInvoices: [],
    previousPeriodInvoices: [],
    filters: { ...DEFAULT_FILTERS },
    currency: 'AED', // Strictly AED
    exchangeRate: 22.8,
    activeTab: 'customers', // 'customers' | 'categories' | 'poc' | 'products' | 'matrix' | 'invoices'
    selectedCustomer: null,
    selectedProduct: null,
    selectedSKUs: [...DEFAULT_SKUS],
    isZohoEnv: false,
    isLoading: false,
    dataSourceLabel: 'invoice_clean.xlsx',
    error: null
  };

  const listeners = {};

  /**
   * Subscribe to state change events.
   * @param {string} event - Event name ('*' for all events, 'dataChanged', 'filtersChanged', etc.)
   * @param {Function} callback - Callback function receiving (data, stateSnapshot)
   * @returns {Function} Unsubscribe function
   */
  function subscribe(event, callback) {
    if (!listeners[event]) {
      listeners[event] = [];
    }
    listeners[event].push(callback);
    return function unsubscribe() {
      listeners[event] = (listeners[event] || []).filter((cb) => cb !== callback);
    };
  }

  /**
   * Notify registered listeners of an event.
   * @param {string} event
   * @param {*} data
   */
  function notify(event, data) {
    const snapshot = getState();
    if (listeners[event]) {
      listeners[event].forEach((cb) => {
        try {
          cb(data, snapshot);
        } catch (err) {
          console.error(`Error in subscriber for event "${event}":`, err);
        }
      });
    }
    if (event !== '*' && listeners['*']) {
      listeners['*'].forEach((cb) => {
        try {
          cb({ event, data }, snapshot);
        } catch (err) {
          console.error('Error in wildcard subscriber:', err);
        }
      });
    }
  }

  /**
   * Get an immutable snapshot copy of current state.
   */
  function getState() {
    return {
      ...state,
      filters: { ...state.filters },
      selectedSKUs: [...state.selectedSKUs]
    };
  }

  /**
   * Filter raw invoices according to current filter state.
   */
  function applyFilters() {
    const { rawData, filters } = state;
    if (!Array.isArray(rawData) || rawData.length === 0) {
      state.filteredInvoices = [];
      return;
    }

    const { status, brand, fy, period, month, search } = filters;
    const searchLower = (search || '').trim().toLowerCase();

    state.filteredInvoices = rawData.filter((inv) => {
      // 1. Fiscal Year (Jan to Dec)
      if (fy && fy !== 'all' && fy !== 'All') {
        const invYear = inv.date ? inv.date.substring(0, 4) : '2026';
        const invFY = inv.fiscalYear || `FY ${invYear}`;

        const normalizeFY = (val) => {
          if (!val) return '';
          const s = String(val).trim();
          if (s.includes('2026') || s === 'FY26-27' || s === 'FY26') return '2026';
          if (s.includes('2025') || s === 'FY25-26' || s === 'FY25') return '2025';
          return s;
        };

        const targetNorm = normalizeFY(fy);
        const invNorm = normalizeFY(invFY) || normalizeFY(invYear);
        if (targetNorm && invNorm && targetNorm !== invNorm) {
          return false;
        }
      }

      // 2. Invoice Status
      if (status && status !== 'all') {
        const invStatus = (inv.status || 'Open').toLowerCase();
        const targetStatus = status.toLowerCase();
        if (targetStatus === 'overdue' && !invStatus.includes('overdue')) return false;
        if (targetStatus === 'open' && invStatus !== 'open') return false;
        if (targetStatus === 'partially paid' && !invStatus.includes('partial')) return false;
        if (targetStatus === 'closed' && !invStatus.includes('closed') && !invStatus.includes('paid')) return false;
      }

      // 3. Brand
      if (brand && brand !== 'all') {
        const targetBrand = brand.toLowerCase();
        const mainBrand = (inv.brand || '').toLowerCase();
        let matchesBrand = mainBrand === targetBrand;
        if (!matchesBrand && Array.isArray(inv.lineItems)) {
          matchesBrand = inv.lineItems.some((li) => (li.brand || '').toLowerCase() === targetBrand);
        }
        if (!matchesBrand) return false;
      }

      // 4. Period (Financial Period: Jan to Dec)
      // Q1: Jan - Mar (1..3)
      // Q2: Apr - Jun (4..6)
      // Q3: Jul - Sep (7..9)
      // Q4: Oct - Dec (10..12)
      // H1: Jan - Jun (1..6)
      // H2: Jul - Dec (7..12)
      if (period && period !== 'Full FY' && period !== 'all' && period !== 'All') {
        const dStr = inv.date || '';
        const mNum = parseInt(dStr.split('-')[1], 10);
        if (!isNaN(mNum)) {
          if ((period === 'Q1' || period.startsWith('Q1')) && !(mNum >= 1 && mNum <= 3)) return false;
          if ((period === 'Q2' || period.startsWith('Q2')) && !(mNum >= 4 && mNum <= 6)) return false;
          if ((period === 'Q3' || period.startsWith('Q3')) && !(mNum >= 7 && mNum <= 9)) return false;
          if ((period === 'Q4' || period.startsWith('Q4')) && !(mNum >= 10 && mNum <= 12)) return false;
          if ((period === 'H1' || period.startsWith('H1')) && !(mNum >= 1 && mNum <= 6)) return false;
          if ((period === 'H2' || period.startsWith('H2')) && !(mNum >= 7 && mNum <= 12)) return false;
        }
      }

      // 5. Month (Jan to Dec)
      if (month && month !== 'all' && month !== 'All') {
        const label = inv.monthLabel || '';
        const key = inv.monthKey || '';
        const dStr = inv.date || '';
        const parts = dStr.split('-');
        const mNum = parts.length >= 2 ? parseInt(parts[1], 10) : NaN;
        const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        const mName = !isNaN(mNum) ? mNames[mNum - 1] : '';
        const invFullMonth = !isNaN(mNum) ? `${mName} ${parts[0]}` : '';

        const match = label === month ||
                      key === month ||
                      mName === month ||
                      invFullMonth === month ||
                      (month.startsWith(mName) && (!month.includes(' ') || month.includes(parts[0])));
        if (!match) return false;
      }

      // 6. Search
      if (searchLower) {
        const cust = (inv.customerName || '').toLowerCase();
        const invNum = (inv.invoiceNumber || '').toLowerCase();
        const poc = (inv.salesperson || '').toLowerCase();
        let matchesSearch = cust.includes(searchLower) || invNum.includes(searchLower) || poc.includes(searchLower);

        if (!matchesSearch && Array.isArray(inv.lineItems)) {
          matchesSearch = inv.lineItems.some((li) => {
            return (
              (li.name || '').toLowerCase().includes(searchLower) ||
              (li.sku || '').toLowerCase().includes(searchLower) ||
              (li.category || '').toLowerCase().includes(searchLower)
            );
          });
        }
        if (!matchesSearch) return false;
      }

      return true;
    });
  }

  /**
   * Update application state.
   * Dispatches targeted events based on what changed.
   * @param {Object} updates
   */
  function setState(updates = {}) {
    let filtersChanged = false;
    let dataChanged = false;
    let currencyChanged = false;
    let tabChanged = false;
    let drilldownChanged = false;
    let loadingChanged = false;
    let skuChanged = false;

    if (updates.filters) {
      state.filters = { ...state.filters, ...updates.filters };
      filtersChanged = true;
    }

    if (updates.rawData !== undefined && updates.rawData !== state.rawData) {
      state.rawData = updates.rawData;
      dataChanged = true;
    }

    if (updates.previousPeriodInvoices !== undefined) {
      state.previousPeriodInvoices = updates.previousPeriodInvoices;
      dataChanged = true;
    }

    if (updates.currency !== undefined && updates.currency !== 'AED') {
      state.currency = 'AED';
    }

    if (updates.activeTab !== undefined && updates.activeTab !== state.activeTab) {
      state.activeTab = updates.activeTab;
      tabChanged = true;
    }

    if (updates.selectedCustomer !== undefined) {
      state.selectedCustomer = updates.selectedCustomer;
      drilldownChanged = true;
    }

    if (updates.selectedProduct !== undefined) {
      state.selectedProduct = updates.selectedProduct;
      drilldownChanged = true;
    }

    if (updates.selectedSKUs !== undefined) {
      state.selectedSKUs = [...updates.selectedSKUs];
      skuChanged = true;
    }

    if (updates.isZohoEnv !== undefined) state.isZohoEnv = updates.isZohoEnv;
    if (updates.dataSourceLabel !== undefined) state.dataSourceLabel = updates.dataSourceLabel;
    if (updates.error !== undefined) state.error = updates.error;

    if (updates.isLoading !== undefined && updates.isLoading !== state.isLoading) {
      state.isLoading = updates.isLoading;
      loadingChanged = true;
    }

    // Recompute filtered invoices if filters or raw data changed
    if (filtersChanged || dataChanged) {
      applyFilters();
    }

    // Fire specific events
    if (loadingChanged) notify('loadingChanged', state.isLoading);
    if (dataChanged) notify('dataChanged', state.rawData);
    if (filtersChanged) notify('filtersChanged', { filters: state.filters, filteredInvoices: state.filteredInvoices });
    if (currencyChanged) notify('currencyChanged', { currency: state.currency, exchangeRate: state.exchangeRate });
    if (tabChanged) notify('tabChanged', state.activeTab);
    if (drilldownChanged) notify('drilldownChanged', { customer: state.selectedCustomer, product: state.selectedProduct });
    if (skuChanged) notify('skuChanged', state.selectedSKUs);

    notify('stateUpdated', getState());
  }

  /**
   * Helper to set an individual filter.
   */
  function setFilter(key, value) {
    setState({
      filters: { [key]: value }
    });
  }

  /**
   * Reset all filters to default values.
   */
  function clearFilters() {
    setState({
      filters: { ...DEFAULT_FILTERS }
    });
  }

  /**
   * Toggle SKU in ASP selection.
   */
  function toggleSKU(sku) {
    const list = [...state.selectedSKUs];
    const idx = list.indexOf(sku);
    if (idx >= 0) {
      list.splice(idx, 1);
    } else {
      list.push(sku);
    }
    setState({ selectedSKUs: list });
  }

  /**
   * Select all or specific SKUs.
   */
  function setSelectedSKUs(skus = []) {
    setState({ selectedSKUs: skus });
  }

  return {
    getState,
    setState,
    subscribe,
    notify,
    applyFilters,
    setFilter,
    clearFilters,
    toggleSKU,
    setSelectedSKUs,
    DEFAULT_FILTERS
  };
});
