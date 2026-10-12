/**
 * Koyson Sales Dashboard - Global Filter Bar Controller
 * Wires #filter-status, #filter-brand, #filter-fy, #filter-period, #filter-month,
 * #check-compare-period, and #btn-clear-filters.
 * Attaches to: window.FilterController
 */

(function () {
  'use strict';

  const DEFAULT_FILTERS = {
    status: 'all',
    brand: 'all',
    fy: 'FY26-27',
    period: 'Full FY',
    month: 'all',
    comparePeriod: false
  };

  /**
   * Initializes Global Filters
   */
  function initFilters() {
    const selStatus = document.getElementById('filter-status');
    const selBrand = document.getElementById('filter-brand');
    const selFY = document.getElementById('filter-fy');
    const selPeriod = document.getElementById('filter-period');
    const selMonth = document.getElementById('filter-month');
    const checkCompare = document.getElementById('check-compare-period');
    const btnClear = document.getElementById('btn-clear-filters');

    if (selStatus) {
      selStatus.addEventListener('change', (e) => {
        const val = e.target.value === 'All' ? 'all' : e.target.value;
        setAppFilter('status', val);
      });
    }

    if (selBrand) {
      selBrand.addEventListener('change', (e) => {
        const val = e.target.value === 'All' ? 'all' : e.target.value;
        setAppFilter('brand', val);
      });
    }

    if (selFY) {
      selFY.addEventListener('change', (e) => {
        setAppFilter('fy', e.target.value);
      });
    }

    if (selPeriod) {
      selPeriod.addEventListener('change', (e) => {
        setAppFilter('period', e.target.value);
      });
    }

    if (selMonth) {
      selMonth.addEventListener('change', (e) => {
        const val = e.target.value === 'All' ? 'all' : e.target.value;
        setAppFilter('month', val);
      });
    }

    if (checkCompare) {
      checkCompare.addEventListener('change', (e) => {
        setAppFilter('comparePeriod', e.target.checked);
      });
    }

    if (btnClear) {
      btnClear.addEventListener('click', () => {
        resetFilters();
      });
    }

    // Subscribe to external state mutations
    if (window.AppState && typeof window.AppState.subscribe === 'function') {
      window.AppState.subscribe('*', () => {
        syncUIWithState();
      });
    }

    renderActiveFilterBadges();
  }

  function setAppFilter(key, value) {
    if (window.AppState) {
      if (typeof window.AppState.setFilter === 'function') {
        window.AppState.setFilter(key, value);
      } else if (typeof window.AppState.setState === 'function') {
        window.AppState.setState({ filters: { [key]: value } });
      }
    }
    renderActiveFilterBadges();
  }

  function resetFilters() {
    if (window.AppState) {
      if (typeof window.AppState.clearFilters === 'function') {
        window.AppState.clearFilters();
      } else if (typeof window.AppState.setFilter === 'function') {
        Object.entries(DEFAULT_FILTERS).forEach(([k, v]) => window.AppState.setFilter(k, v));
      }
    }

    const selStatus = document.getElementById('filter-status');
    const selBrand = document.getElementById('filter-brand');
    const selFY = document.getElementById('filter-fy');
    const selPeriod = document.getElementById('filter-period');
    const selMonth = document.getElementById('filter-month');
    const checkCompare = document.getElementById('check-compare-period');

    if (selStatus) selStatus.value = 'All';
    if (selBrand) selBrand.value = 'All';
    if (selFY) selFY.value = 'FY26-27';
    if (selPeriod) selPeriod.value = 'Full FY';
    if (selMonth) selMonth.value = 'All';
    if (checkCompare) checkCompare.checked = false;

    renderActiveFilterBadges();
  }

  function syncUIWithState() {
    if (!window.AppState || typeof window.AppState.getState !== 'function') return;
    const filters = window.AppState.getState().filters || {};

    const selStatus = document.getElementById('filter-status');
    const selBrand = document.getElementById('filter-brand');
    const selFY = document.getElementById('filter-fy');
    const selPeriod = document.getElementById('filter-period');
    const selMonth = document.getElementById('filter-month');
    const checkCompare = document.getElementById('check-compare-period');

    if (selStatus && filters.status) {
      selStatus.value = filters.status === 'all' ? 'All' : filters.status;
    }
    if (selBrand && filters.brand) {
      selBrand.value = filters.brand === 'all' ? 'All' : filters.brand;
    }
    if (selFY && filters.fy) {
      selFY.value = filters.fy;
    }
    if (selPeriod && filters.period) {
      selPeriod.value = filters.period;
    }
    if (selMonth && filters.month) {
      selMonth.value = filters.month === 'all' ? 'All' : filters.month;
    }
    if (checkCompare && typeof filters.comparePeriod === 'boolean') {
      checkCompare.checked = filters.comparePeriod;
    }

    renderActiveFilterBadges();
  }

  function renderActiveFilterBadges() {
    let container = document.getElementById('active-filter-badges-bar');
    const filterBar = document.getElementById('global-filter-bar');
    if (!filterBar) return;

    if (!container) {
      container = document.createElement('div');
      container.id = 'active-filter-badges-bar';
      container.style.cssText = 'display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 6px 24px; background-color: var(--color-bg-surface); border-bottom: 1px solid var(--color-border-subtle); font-size: 11px;';
      filterBar.parentNode.insertBefore(container, filterBar.nextSibling);
    }

    let filters = DEFAULT_FILTERS;
    if (window.AppState && typeof window.AppState.getState === 'function') {
      filters = window.AppState.getState().filters || DEFAULT_FILTERS;
    }

    const activeList = [];
    if (filters.status && filters.status !== 'all') {
      activeList.push({ key: 'status', label: `Status: ${filters.status}`, resetVal: 'all', selectId: 'filter-status', defaultSelect: 'All' });
    }
    if (filters.brand && filters.brand !== 'all') {
      activeList.push({ key: 'brand', label: `Brand: ${filters.brand}`, resetVal: 'all', selectId: 'filter-brand', defaultSelect: 'All' });
    }
    if (filters.month && filters.month !== 'all') {
      activeList.push({ key: 'month', label: `Month: ${filters.month}`, resetVal: 'all', selectId: 'filter-month', defaultSelect: 'All' });
    }
    if (filters.period && filters.period !== 'Full FY') {
      activeList.push({ key: 'period', label: `Period: ${filters.period}`, resetVal: 'Full FY', selectId: 'filter-period', defaultSelect: 'Full FY' });
    }
    if (filters.comparePeriod) {
      activeList.push({ key: 'comparePeriod', label: 'Comparing Previous Period', resetVal: false, checkId: 'check-compare-period' });
    }

    if (!activeList.length) {
      container.style.display = 'none';
      container.innerHTML = '';
      return;
    }

    container.style.display = 'flex';
    container.innerHTML = `
      <span style="font-weight: 600; color: var(--color-text-muted);">Active Filters:</span>
      ${activeList.map(item => `
        <span class="badge" style="background-color: var(--brand-nellon-light); color: var(--brand-nellon); border: 1px solid var(--color-border); display: inline-flex; align-items: center; gap: 4px; padding: 3px 8px; border-radius: 9999px;">
          ${item.label}
          <span style="cursor: pointer; font-weight: bold; margin-left: 2px;" data-remove-filter="${item.key}" data-reset-val="${item.resetVal}" title="Remove filter">✕</span>
        </span>
      `).join('')}
      <button type="button" id="btn-reset-all-badges" style="background: none; border: none; color: var(--color-text-muted); cursor: pointer; text-decoration: underline; font-size: 11px; margin-left: 8px;">Clear all</button>
    `;

    container.querySelectorAll('[data-remove-filter]').forEach(el => {
      el.addEventListener('click', () => {
        const key = el.getAttribute('data-remove-filter');
        let resetVal = el.getAttribute('data-reset-val');
        if (resetVal === 'false') resetVal = false;
        if (resetVal === 'true') resetVal = true;

        setAppFilter(key, resetVal);

        const item = activeList.find(i => i.key === key);
        if (item && item.selectId) {
          const s = document.getElementById(item.selectId);
          if (s) s.value = item.defaultSelect;
        }
        if (item && item.checkId) {
          const c = document.getElementById(item.checkId);
          if (c) c.checked = false;
        }
      });
    });

    const resetAllBtn = container.querySelector('#btn-reset-all-badges');
    if (resetAllBtn) {
      resetAllBtn.addEventListener('click', resetFilters);
    }
  }

  function escapeHtml(str) {
    if (!str && str !== 0) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /**
   * Dynamically populates dropdown options based on the loaded dataset.
   * Extracts distinct Statuses, Brands, FYs, and Months while preserving active selections.
   */
  function populateDynamicFilters(invoices = []) {
    if (!Array.isArray(invoices) || invoices.length === 0) return;

    // 1. Statuses
    const statusSet = new Set(['Open', 'Overdue', 'Partially Paid', 'Closed']);
    invoices.forEach(inv => { if (inv.status) statusSet.add(inv.status); });
    const statuses = Array.from(statusSet);
    const selStatus = document.getElementById('filter-status');
    if (selStatus) {
      const currentVal = selStatus.value;
      selStatus.innerHTML = '<option value="All">All Statuses</option>' + 
        statuses.map(s => `<option value="${escapeHtml(s)}">${escapeHtml(s)}</option>`).join('');
      if (statuses.includes(currentVal) || currentVal === 'All') {
        selStatus.value = currentVal;
      }
    }

    // 2. Brands
    const brandSet = new Set(['Nellon', 'Raviya', 'Non-Branded']);
    invoices.forEach(inv => { if (inv.brand) brandSet.add(inv.brand); });
    const brands = Array.from(brandSet);
    const selBrand = document.getElementById('filter-brand');
    if (selBrand) {
      const currentVal = selBrand.value;
      selBrand.innerHTML = '<option value="All">All Brands</option>' + 
        brands.map(b => `<option value="${escapeHtml(b)}">${escapeHtml(b)}</option>`).join('');
      if (brands.includes(currentVal) || currentVal === 'All') {
        selBrand.value = currentVal;
      }
    }

    // 3. Fiscal Years
    const fySet = new Set(['FY26-27', 'FY25-26']);
    invoices.forEach(inv => { if (inv.fiscalYear) fySet.add(inv.fiscalYear); });
    const fys = Array.from(fySet).sort().reverse();
    const selFY = document.getElementById('filter-fy');
    if (selFY) {
      const currentVal = selFY.value;
      selFY.innerHTML = fys.map(f => `<option value="${escapeHtml(f)}">${escapeHtml(f)}</option>`).join('');
      if (fys.includes(currentVal)) {
        selFY.value = currentVal;
      }
    }

    // 4. Months (Chronological sorting)
    const monthMap = new Map();
    invoices.forEach(inv => {
      if (inv.monthLabel && inv.monthKey) {
        monthMap.set(inv.monthLabel, inv.monthKey);
      } else if (inv.monthLabel) {
        monthMap.set(inv.monthLabel, inv.monthLabel);
      }
    });

    if (monthMap.size > 0) {
      const sortedMonths = Array.from(monthMap.entries())
        .sort((a, b) => a[1].localeCompare(b[1]))
        .map(entry => entry[0]);
      
      const selMonth = document.getElementById('filter-month');
      if (selMonth) {
        const currentVal = selMonth.value;
        selMonth.innerHTML = '<option value="All">All Months</option>' + 
          sortedMonths.map(m => `<option value="${escapeHtml(m)}">${escapeHtml(m)}</option>`).join('');
        if (sortedMonths.includes(currentVal) || currentVal === 'All') {
          selMonth.value = currentVal;
        }
      }
    }
  }

  // Public Interface
  window.FilterController = {
    initFilters,
    populateDynamicFilters,
    setAppFilter,
    resetFilters,
    syncUIWithState,
    renderActiveFilterBadges
  };

})();
