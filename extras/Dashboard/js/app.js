/**
 * Koyson Sales Dashboard - Main Application Orchestrator
 * Bootstraps Zoho service, data service, state subscriptions, KPI count-up animations,
 * currency switcher (AED/INR), refresh control, theme toggle, month snapshot panel,
 * ASP SKU selector, and sidebar interactions.
 * (Note: Per user requirement, upload modal/button handling is excluded.)
 * Attaches to: window.DashboardApp
 */

(function () {
  'use strict';

  function getActiveCurrency() {
    if (window.AppState && typeof window.AppState.getState === 'function') {
      return window.AppState.getState().currency || 'AED';
    }
    return 'AED';
  }

  function formatMoney(value, compact = false) {
    const curr = getActiveCurrency();
    const rate = (window.AppState && typeof window.AppState.getState === 'function')
      ? (window.AppState.getState().exchangeRate || 22.8)
      : 22.8;
    if (window.Formatters && typeof window.Formatters.formatCurrency === 'function') {
      return window.Formatters.formatCurrency(value, curr, compact, rate);
    }
    const num = Number(value) || 0;
    if (compact) {
      if (Math.abs(num) >= 1_000_000) return `${curr} ${(num / 1_000_000).toFixed(2)}M`;
      if (Math.abs(num) >= 1_000) return `${curr} ${(num / 1_000).toFixed(1)}K`;
    }
    return `${curr} ${num.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
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
    return `${(Number(value) || 0).toFixed(1)}%`;
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
   * Count-up Animation Helper (600-900ms)
   */
  function animateValue(element, start, end, duration = 750, isCurrency = false, isCompact = false) {
    if (!element) return;
    const startTime = performance.now();
    const range = end - start;

    function step(currentTime) {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const ease = 1 - Math.pow(1 - progress, 4); // easeOutQuart
      const current = start + range * ease;

      if (isCurrency) {
        element.textContent = formatMoney(current, isCompact && progress === 1);
      } else {
        element.textContent = formatNumber(Math.round(current));
      }

      if (progress < 1) {
        requestAnimationFrame(step);
      } else {
        if (isCurrency) {
          element.textContent = formatMoney(end, isCompact);
        } else {
          element.textContent = formatNumber(Math.round(end));
        }
      }
    }

    requestAnimationFrame(step);
  }

  /**
   * 1. UPDATE KPI CARDS & BRAND SUMMARY
   */
  function updateKPICards() {
    let rawInvoices = [];
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      rawInvoices = state.filteredInvoices || state.rawData || [];
    }

    let kpis = null;
    if (window.Calculations && typeof window.Calculations.computeKPIs === 'function') {
      kpis = window.Calculations.computeKPIs(rawInvoices);
    }

    const netRevenue = kpis ? kpis.netRevenue : 6873300;
    const invoiceCount = kpis ? kpis.invoiceCount : 1284;
    const activeCustomers = kpis ? kpis.activeCustomers : 412;
    const aov = kpis ? kpis.aov : 5357;
    const avgCreditPeriod = kpis ? kpis.avgCreditPeriod : 28;

    const elRevenue = document.getElementById('val-net-revenue');
    const elInvoices = document.getElementById('val-invoices');
    const elCustomers = document.getElementById('val-active-customers');
    const elAov = document.getElementById('val-aov');
    const elCredit = document.getElementById('val-avg-credit');

    if (elRevenue) animateValue(elRevenue, 0, netRevenue, 800, true, true);
    if (elInvoices) animateValue(elInvoices, 0, invoiceCount, 700, false);
    if (elCustomers) animateValue(elCustomers, 0, activeCustomers, 750, false);
    if (elAov) animateValue(elAov, 0, aov, 800, true, false);
    if (elCredit) {
      animateValue(elCredit, 0, avgCreditPeriod, 650, false);
      setTimeout(() => { if (elCredit) elCredit.textContent = `${Math.round(avgCreditPeriod)} Days`; }, 660);
    }

    updateBrandCards(rawInvoices);
  }

  function updateBrandCards(invoices) {
    let brandMetrics = null;
    if (window.Calculations && typeof window.Calculations.computeBrandBreakdown === 'function') {
      brandMetrics = window.Calculations.computeBrandBreakdown(invoices);
    }

    const defaults = {
      'Nellon': { revenue: 3520000, share: 51.2, invoices: 658, lineItems: 3420, aov: 5349 },
      'Non-Branded': { revenue: 2570000, share: 37.4, invoices: 480, lineItems: 2510, aov: 5354 },
      'Raviya': { revenue: 783300, share: 11.4, invoices: 146, lineItems: 890, aov: 5365 }
    };

    const getBrand = (name) => {
      if (brandMetrics && Array.isArray(brandMetrics)) {
        const found = brandMetrics.find(b => b.brand.toLowerCase() === name.toLowerCase());
        if (found) return found;
      }
      return defaults[name];
    };

    const nellon = getBrand('Nellon');
    const nonBranded = getBrand('Non-Branded');
    const raviya = getBrand('Raviya');

    // Nellon
    const elNellonRev = document.getElementById('brand-rev-nellon');
    const elNellonShare = document.getElementById('brand-share-nellon');
    const elNellonInv = document.getElementById('brand-inv-nellon');
    const elNellonLines = document.getElementById('brand-lines-nellon');
    const elNellonAov = document.getElementById('brand-aov-nellon');

    if (elNellonRev) elNellonRev.textContent = formatMoney(nellon.revenue, true);
    if (elNellonShare) elNellonShare.textContent = `${formatPercent(nellon.share)} Share`;
    if (elNellonInv) elNellonInv.textContent = formatNumber(nellon.invoiceCount || nellon.invoices);
    if (elNellonLines) elNellonLines.textContent = formatNumber(nellon.lineItemsCount || nellon.lineItems);
    if (elNellonAov) elNellonAov.textContent = formatMoney(nellon.aov);

    // Non-Branded
    const elNBRev = document.getElementById('brand-rev-nonbranded');
    const elNBShare = document.getElementById('brand-share-nonbranded');
    const elNBInv = document.getElementById('brand-inv-nonbranded');
    const elNBLines = document.getElementById('brand-lines-nonbranded');
    const elNBAov = document.getElementById('brand-aov-nonbranded');

    if (elNBRev) elNBRev.textContent = formatMoney(nonBranded.revenue, true);
    if (elNBShare) elNBShare.textContent = `${formatPercent(nonBranded.share)} Share`;
    if (elNBInv) elNBInv.textContent = formatNumber(nonBranded.invoiceCount || nonBranded.invoices);
    if (elNBLines) elNBLines.textContent = formatNumber(nonBranded.lineItemsCount || nonBranded.lineItems);
    if (elNBAov) elNBAov.textContent = formatMoney(nonBranded.aov);

    // Raviya
    const elRavRev = document.getElementById('brand-rev-raviya');
    const elRavShare = document.getElementById('brand-share-raviya');
    const elRavInv = document.getElementById('brand-inv-raviya');
    const elRavLines = document.getElementById('brand-lines-raviya');
    const elRavAov = document.getElementById('brand-aov-raviya');

    if (elRavRev) elRavRev.textContent = formatMoney(raviya.revenue, true);
    if (elRavShare) elRavShare.textContent = `${formatPercent(raviya.share)} Share`;
    if (elRavInv) elRavInv.textContent = formatNumber(raviya.invoiceCount || raviya.invoices);
    if (elRavLines) elRavLines.textContent = formatNumber(raviya.lineItemsCount || raviya.lineItems);
    if (elRavAov) elRavAov.textContent = formatMoney(raviya.aov);
  }

  /**
   * 2. CURRENCY SWITCHER (AED vs INR)
   */
  function initCurrencySwitcher() {
    const btnAED = document.getElementById('btn-currency-aed');
    const btnINR = document.getElementById('btn-currency-inr');
    const switchContainer = document.querySelector('.currency-switch');

    // Asynchronously fetch live rate (Zoho Books settings or Open Exchange API)
    if (window.ZohoService && typeof window.ZohoService.fetchExchangeRate === 'function') {
      window.ZohoService.fetchExchangeRate('INR')
        .then((rateInfo) => {
          if (rateInfo && rateInfo.rate) {
            if (window.AppState && typeof window.AppState.setState === 'function') {
              window.AppState.setState({ exchangeRate: rateInfo.rate });
            }
            if (switchContainer) {
              switchContainer.setAttribute('title', `1 AED = ${rateInfo.rate.toFixed(2)} INR (${rateInfo.source})`);
            }
            if (getActiveCurrency() === 'INR') {
              refreshDashboardViews();
            }
          }
        })
        .catch((err) => {
          console.warn('Live FX rate fetch error:', err);
        });
    }

    function setCurrency(curr) {
      if (btnAED && btnINR) {
        if (curr === 'AED') {
          btnAED.classList.add('active');
          btnINR.classList.remove('active');
        } else {
          btnINR.classList.add('active');
          btnAED.classList.remove('active');
        }
      }

      if (window.AppState && typeof window.AppState.setState === 'function') {
        window.AppState.setState({ currency: curr });
      }

      refreshDashboardViews();
    }

    if (btnAED) btnAED.addEventListener('click', () => setCurrency('AED'));
    if (btnINR) btnINR.addEventListener('click', () => setCurrency('INR'));
  }

  /**
   * 3. REFRESH BUTTON WITH SPIN ANIMATION
   */
  function initRefreshControl() {
    const btnRefresh = document.getElementById('btn-refresh');
    const iconSvg = document.getElementById('refresh-icon-svg');
    if (!btnRefresh) return;

    btnRefresh.addEventListener('click', async () => {
      if (iconSvg) iconSvg.style.animation = 'spin 0.7s linear infinite';

      try {
        if (window.DataService && typeof window.DataService.loadInitialData === 'function') {
          await window.DataService.loadInitialData();
        }
      } catch (err) {
        console.warn('Data reload error:', err);
      } finally {
        setTimeout(() => {
          if (iconSvg) iconSvg.style.animation = '';
          refreshDashboardViews();
        }, 500);
      }
    });
  }

  /**
   * 4. THEME TOGGLE (LIGHT / DARK)
   */
  function initThemeToggle() {
    const btnTheme = document.getElementById('btn-theme-toggle');
    if (!btnTheme) return;

    function applyTheme(theme) {
      const isDark = theme === 'dark';
      document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
      document.body.classList.toggle('dark-theme', isDark);

      // Dynamically toggle Moon vs Sun icon
      btnTheme.setAttribute('title', isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode');
      btnTheme.setAttribute('aria-label', isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode');
      btnTheme.innerHTML = isDark
        ? `<svg class="icon icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2"></path><path d="M12 20v2"></path><path d="m4.93 4.93 1.41 1.41"></path><path d="m17.66 17.66 1.41 1.41"></path><path d="M2 12h2"></path><path d="M20 12h2"></path><path d="m6.34 17.66-1.41 1.41"></path><path d="m19.07 4.93-1.41 1.41"></path></svg>`
        : `<svg class="icon icon-sm" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"></path></svg>`;

      try {
        localStorage.setItem('koyson-theme', isDark ? 'dark' : 'light');
      } catch (e) {}

      // Redraw charts so axis/grid lines adapt to dark/light theme
      if (window.DashboardCharts && typeof window.DashboardCharts.updateAllCharts === 'function') {
        window.DashboardCharts.updateAllCharts();
      }
    }

    btnTheme.addEventListener('click', () => {
      const current = document.documentElement.getAttribute('data-theme') || 
        (document.body.classList.contains('dark-theme') ? 'dark' : 'light');
      applyTheme(current === 'dark' ? 'light' : 'dark');
    });

    try {
      const saved = localStorage.getItem('koyson-theme');
      if (saved === 'dark') {
        applyTheme('dark');
      } else {
        applyTheme('light');
      }
    } catch (e) {
      applyTheme('light');
    }
  }

  /**
   * 5. WAYPOINT SPINE CONTROLLER & SCROLL-SPY
   * Tracks active viewport sections with IntersectionObserver, animates glowing tracer bead,
   * handles smooth navigation clicks, and binds live telemetry to hover HUD cards.
   */
  function initWaypointSpine() {
    const spine = document.getElementById('waypoint-spine');
    if (!spine) return;

    const nodes = spine.querySelectorAll('.spine-node[data-waypoint]');
    const tracerBead = document.getElementById('spine-tracer-bead');

    // Section IDs observed by the Waypoint Spine
    const sectionIds = [
      'section-kpis',
      'section-charts-row1',
      'section-month-snapshot',
      'section-matrix-credit',
      'section-asp-trend',
      'section-tables'
    ];

    /**
     * Position tracer bead vertically or horizontally (mobile) aligned with active node
     */
    function updateTracerPosition(activeNode) {
      if (!tracerBead || !activeNode) return;
      const isMobile = window.innerWidth <= 768;

      if (isMobile) {
        const nodeLeft = activeNode.offsetLeft;
        const nodeWidth = activeNode.offsetWidth;
        tracerBead.style.left = `${nodeLeft + (nodeWidth / 2) - 7}px`;
        tracerBead.style.top = '50%';
      } else {
        const nodeTop = activeNode.offsetTop;
        const nodeHeight = activeNode.offsetHeight;
        tracerBead.style.top = `${nodeTop + (nodeHeight / 2) - 7}px`;
        tracerBead.style.left = '50%';
      }
    }

    /**
     * Set active node and update tracer
     */
    function setActiveWaypoint(sectionId) {
      nodes.forEach(node => {
        const target = node.getAttribute('data-waypoint');
        if (target === sectionId) {
          node.classList.add('active');
          updateTracerPosition(node);
        } else {
          node.classList.remove('active');
        }
      });
    }

    // Click handler for each waypoint node
    nodes.forEach(node => {
      const targetId = node.getAttribute('data-waypoint');
      const handleAction = (e) => {
        e.preventDefault();
        const targetEl = document.getElementById(targetId);
        if (targetEl) {
          targetEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
          setActiveWaypoint(targetId);
        }
      };

      node.addEventListener('click', handleAction);
      node.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          handleAction(e);
        }
      });
    });

    // Setup IntersectionObserver for smooth scroll-spy
    const observerOptions = {
      root: null,
      rootMargin: '-15% 0px -40% 0px',
      threshold: [0, 0.2, 0.5]
    };

    const sectionElements = sectionIds
      .map(id => document.getElementById(id))
      .filter(el => el !== null);

    let activeIntersectingId = sectionIds[0];

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          activeIntersectingId = entry.target.id;
          setActiveWaypoint(activeIntersectingId);
        }
      });
    }, observerOptions);

    sectionElements.forEach(el => observer.observe(el));

    // Handle window resize for bead recalculation
    window.addEventListener('resize', () => {
      const currentActive = spine.querySelector('.spine-node.active') || nodes[0];
      if (currentActive) updateTracerPosition(currentActive);
    }, { passive: true });

    // Initial position on load
    setTimeout(() => {
      const initialNode = nodes[0];
      if (initialNode) updateTracerPosition(initialNode);
    }, 150);

    // Brand card click to filter by brand
    document.querySelectorAll('.brand-card[data-brand]').forEach(card => {
      card.addEventListener('click', () => {
        const brand = card.getAttribute('data-brand');
        if (window.FilterController && typeof window.FilterController.setAppFilter === 'function') {
          window.FilterController.setAppFilter('brand', brand);
        }
      });
    });
  }

  /**
   * Updates Waypoint Spine Hover HUD Telemetry metrics from current AppState
   */
  function updateWaypointTelemetry() {
    let rawInvoices = [];
    if (window.AppState && typeof window.AppState.getState === 'function') {
      const state = window.AppState.getState();
      rawInvoices = state.filteredInvoices || state.rawData || [];
    }

    let kpis = null;
    if (window.Calculations && typeof window.Calculations.computeKPIs === 'function') {
      kpis = window.Calculations.computeKPIs(rawInvoices);
    }

    const netRev = kpis ? kpis.netRevenue : 6873300;
    const invCount = kpis ? kpis.invoiceCount : 1284;
    const accounts = kpis ? kpis.activeCustomers : 412;
    const aov = kpis ? kpis.aov : 5357;
    const avgCredit = kpis ? kpis.avgCreditPeriod : 28;

    const elWpRev = document.getElementById('wp-stat-rev');
    const elWpInv = document.getElementById('wp-stat-inv');
    const elWpAccounts = document.getElementById('wp-stat-accounts');
    const elWpAov = document.getElementById('wp-stat-aov');
    const elWpCredit = document.getElementById('wp-stat-credit');

    if (elWpRev) elWpRev.textContent = formatMoney(netRev, true);
    if (elWpInv) elWpInv.textContent = formatNumber(invCount);
    if (elWpAccounts) elWpAccounts.textContent = formatNumber(accounts);
    if (elWpAov) elWpAov.textContent = formatMoney(aov, false);
    if (elWpCredit) elWpCredit.textContent = `${Math.round(avgCredit)} Days`;

    let brandMetrics = null;
    if (window.Calculations && typeof window.Calculations.computeBrandBreakdown === 'function') {
      brandMetrics = window.Calculations.computeBrandBreakdown(rawInvoices);
    }
    const nellon = brandMetrics && brandMetrics.find(b => b.brand.toLowerCase() === 'nellon');
    const elWpShare = document.getElementById('wp-stat-share');
    if (elWpShare) {
      elWpShare.textContent = nellon ? `${nellon.share.toFixed(1)}%` : '51.2%';
    }
  }

  /**
   * 6. MONTH SNAPSHOT PANEL TABS
   */
  function initMonthSnapshot() {
    const tabs = document.querySelectorAll('.month-tab-btn');
    const elRev = document.getElementById('snap-revenue');
    const elInv = document.getElementById('snap-invoices');
    const elNellon = document.getElementById('snap-nellon');
    const elCat = document.getElementById('snap-category');

    const snapshots = {
      'Apr 2026': { revenue: 1660000, invoices: 310, nellon: 'AED 863K (52%)', category: 'Rice & Grains' },
      'May 2026': { revenue: 1810000, invoices: 340, nellon: 'AED 923K (51%)', category: 'Cooking Oil & Ghee' },
      'Jun 2026': { revenue: 1725000, invoices: 321, nellon: 'AED 880K (51%)', category: 'Rice & Grains' },
      'Jul 2026': { revenue: 1678300, invoices: 313, nellon: 'AED 854K (51%)', category: 'Sugar & Sweeteners' },
      'Aug 2026': { revenue: 1762568, invoices: 329, nellon: 'AED 902K (51%)', category: 'Cooking Oil & Ghee' },
      'Sep 2026': { revenue: 1783000, invoices: 335, nellon: 'AED 913K (51%)', category: 'Rice & Grains' }
    };

    function updateSnapshot(monthKey) {
      const data = snapshots[monthKey] || snapshots['Apr 2026'];
      if (elRev) elRev.textContent = formatMoney(data.revenue, true);
      if (elInv) elInv.textContent = formatNumber(data.invoices);
      if (elNellon) elNellon.textContent = data.nellon;
      if (elCat) elCat.textContent = data.category;
    }

    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        tabs.forEach(t => {
          t.classList.remove('active');
          t.setAttribute('aria-selected', 'false');
        });
        tab.classList.add('active');
        tab.setAttribute('aria-selected', 'true');
        const m = tab.getAttribute('data-month');
        updateSnapshot(m);
      });
    });

    updateSnapshot('Apr 2026');
  }

  /**
   * 7. ASP SKU SELECTOR & CONTROLS
   */
  function initASPSKUSelector() {
    const container = document.getElementById('asp-chips-container');
    const catFilter = document.getElementById('asp-category-filter');
    const searchInput = document.getElementById('asp-sku-search');
    const btnSelectAll = document.getElementById('btn-asp-select-all');
    const btnDeselectAll = document.getElementById('btn-asp-deselect-all');
    const badgeMore = document.getElementById('asp-hidden-count');

    if (!container) return;

    const allSKUs = [
      { code: 'SKU-BASMATI-5KG', name: 'Nellon Basmati Rice 5kg', color: '#2563EB', category: 'Rice & Grains' },
      { code: 'SKU-OIL-1.8L', name: 'Raviya Sunflower Oil 1L', color: '#F59E0B', category: 'Cooking Oil & Ghee' },
      { code: 'SKU-SUGAR-2KG', name: 'Sugar Premium 2kg', color: '#10B981', category: 'Sugar & Sweeteners' },
      { code: 'SKU-ATTA-10KG', name: 'Nellon Chakki Atta 10kg', color: '#8B5CF6', category: 'Flour & Milling Products' },
      { code: 'SKU-LENTILS-1KG', name: 'Red Lentils (Masoor Dal) 1kg', color: '#EC4899', category: 'Pulses & Legumes' }
    ];

    let selectedCodes = ['SKU-BASMATI-5KG', 'SKU-OIL-1.8L', 'SKU-SUGAR-2KG', 'SKU-ATTA-10KG'];

    function renderChips() {
      let filtered = allSKUs;
      if (catFilter && catFilter.value !== 'All') {
        filtered = filtered.filter(s => s.category === catFilter.value);
      }
      if (searchInput && searchInput.value.trim()) {
        const q = searchInput.value.trim().toLowerCase();
        filtered = filtered.filter(s => s.name.toLowerCase().includes(q) || s.code.toLowerCase().includes(q));
      }

      container.innerHTML = filtered.map(s => {
        const isSelected = selectedCodes.includes(s.code);
        return `
          <div class="sku-chip ${isSelected ? 'active' : ''}" data-sku-code="${s.code}" style="cursor: pointer; user-select: none; ${isSelected ? 'background-color: var(--color-bg-surface); border-color: ' + s.color + ';' : 'opacity: 0.6;'}">
            <span class="sku-chip-dot" style="background-color: ${s.color};"></span>
            <span style="font-weight: 500;">${escapeHtml(s.name)}</span>
            <span class="sku-chip-remove" data-sku-toggle="${s.code}">${isSelected ? '✕' : '+'}</span>
          </div>
        `;
      }).join('') + `<span class="sku-more-badge" id="asp-hidden-count">+383 more SKUs not shown</span>`;

      container.querySelectorAll('[data-sku-toggle], .sku-chip').forEach(el => {
        el.addEventListener('click', (e) => {
          e.stopPropagation();
          const code = el.getAttribute('data-sku-toggle') || el.getAttribute('data-sku-code');
          if (!code) return;
          if (selectedCodes.includes(code)) {
            selectedCodes = selectedCodes.filter(c => c !== code);
          } else {
            selectedCodes.push(code);
          }
          if (window.AppState && typeof window.AppState.setSelectedSKUs === 'function') {
            window.AppState.setSelectedSKUs(selectedCodes);
          }
          renderChips();
          updateASPChart();
        });
      });
    }

    function updateASPChart() {
      const selectedNames = allSKUs.filter(s => selectedCodes.includes(s.code)).map(s => s.name);
      if (window.DashboardCharts && typeof window.DashboardCharts.renderASPTrend === 'function') {
        window.DashboardCharts.renderASPTrend(null, selectedNames);
      }
    }

    if (catFilter) catFilter.addEventListener('change', renderChips);
    if (searchInput) searchInput.addEventListener('input', renderChips);

    if (btnSelectAll) {
      btnSelectAll.addEventListener('click', () => {
        selectedCodes = allSKUs.map(s => s.code);
        if (window.AppState && typeof window.AppState.setSelectedSKUs === 'function') {
          window.AppState.setSelectedSKUs(selectedCodes);
        }
        renderChips();
        updateASPChart();
      });
    }

    if (btnDeselectAll) {
      btnDeselectAll.addEventListener('click', () => {
        selectedCodes = [];
        if (window.AppState && typeof window.AppState.setSelectedSKUs === 'function') {
          window.AppState.setSelectedSKUs([]);
        }
        renderChips();
        updateASPChart();
      });
    }

    renderChips();
  }

  /**
   * Refreshes all dashboard views smoothly without full page reload
   */
  function refreshDashboardViews() {
    const elSource = document.getElementById('source-name-label');
    if (elSource && window.AppState && typeof window.AppState.getState === 'function') {
      const src = window.AppState.getState().dataSourceLabel;
      if (src) elSource.textContent = src;
    }
    updateKPICards();
    updateWaypointTelemetry();
    if (window.DashboardCharts && typeof window.DashboardCharts.updateAllCharts === 'function') {
      window.DashboardCharts.updateAllCharts();
    }
    if (window.DashboardTables && typeof window.DashboardTables.updateAllTables === 'function') {
      window.DashboardTables.updateAllTables();
    }
  }

  /**
   * MASTER BOOTSTRAP
   */
  async function bootstrap() {
    // 1. Initialize Zoho Service if present
    if (window.ZohoService && typeof window.ZohoService.init === 'function') {
      try {
        window.ZohoService.init();
      } catch (err) {
        console.warn('ZohoService init warning:', err);
      }
    }

    // 2. Load Initial Data via DataService
    if (window.DataService && typeof window.DataService.loadInitialData === 'function') {
      try {
        await window.DataService.loadInitialData();
      } catch (err) {
        console.warn('DataService initial load warning:', err);
      }
    }

    // 3. Initialize Visuals, Tables, and Filters
    if (window.DashboardCharts && typeof window.DashboardCharts.initCharts === 'function') {
      window.DashboardCharts.initCharts();
    }
    if (window.FilterController && typeof window.FilterController.initFilters === 'function') {
      window.FilterController.initFilters();
    }
    if (window.DashboardTables && typeof window.DashboardTables.initTabSwitcher === 'function') {
      window.DashboardTables.initTabSwitcher();
    }
    if (window.ExportController && typeof window.ExportController.initExport === 'function') {
      window.ExportController.initExport();
    }

    // 4. Initialize Controls (Currency toggle, Refresh, Theme, Waypoint Spine, Month Snapshot, ASP)
    initCurrencySwitcher();
    initRefreshControl();
    initThemeToggle();
    initWaypointSpine();
    initMonthSnapshot();
    initASPSKUSelector();

    // 5. Populate Dynamic Filter Options from Loaded Dataset
    const initialRaw = (window.AppState && window.AppState.getState) ? (window.AppState.getState().rawData || []) : [];
    if (window.FilterController && typeof window.FilterController.populateDynamicFilters === 'function') {
      window.FilterController.populateDynamicFilters(initialRaw);
    }

    // 6. Initial Render
    refreshDashboardViews();

    // 7. Subscribe to AppState changes
    if (window.AppState && typeof window.AppState.subscribe === 'function') {
      window.AppState.subscribe('*', () => {
        refreshDashboardViews();
      });
      window.AppState.subscribe('dataLoaded', () => {
        const raw = (window.AppState && window.AppState.getState) ? (window.AppState.getState().rawData || []) : [];
        if (window.FilterController && typeof window.FilterController.populateDynamicFilters === 'function') {
          window.FilterController.populateDynamicFilters(raw);
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootstrap);
  } else {
    bootstrap();
  }

  // Public Interface
  window.DashboardApp = {
    bootstrap,
    refreshDashboardViews,
    updateKPICards
  };

})();
