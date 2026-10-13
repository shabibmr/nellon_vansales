/**
 * Koyson Sales Dashboard - Chart.js Visualizations Controller
 * High-performance, reactive charts with smooth transitions and theme support.
 * Attaches to: window.DashboardCharts
 */

(function () {
  'use strict';

  // Chart instances registry
  const instances = {
    revenueTrend: null,
    brandDonut: null,
    invoiceStatus: null,
    weeklyActivity: null,
    aspTrend: null
  };

  // Color Palette Tokens
  const THEME_COLORS = {
    brands: {
      'Nellon': { bg: '#2563EB', hover: '#1D4ED8', border: '#1E40AF', light: 'rgba(37, 99, 235, 0.15)' },
      'Non-Branded': { bg: '#64748B', hover: '#475569', border: '#334155', light: 'rgba(100, 116, 139, 0.15)' },
      'Raviya': { bg: '#F59E0B', hover: '#D97706', border: '#B45309', light: 'rgba(245, 158, 11, 0.15)' }
    },
    status: {
      'Open': { bg: '#0284C7', hover: '#0369A1' },
      'Overdue': { bg: '#EF4444', hover: '#DC2626' }, // Distinct Red
      'Partially Paid': { bg: '#F59E0B', hover: '#D97706' },
      'Closed': { bg: '#10B981', hover: '#059669' }
    },
    lineItems: '#10B981',
    skuPalette: [
      '#2563EB', '#F59E0B', '#10B981', '#8B5CF6', '#EC4899',
      '#06B6D4', '#F97316', '#14B8A6', '#6366F1', '#84CC16'
    ]
  };

  function getActiveCurrency() {
    return 'AED';
  }

  /**
   * Safe Currency Formatter (AED)
   */
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

  /**
   * Center Text Plugin for Donut Chart
   */
  const centerTextPlugin = {
    id: 'centerTextPlugin',
    afterDraw(chart) {
      if (chart.config.type !== 'doughnut') return;
      const { ctx, chartArea } = chart;
      if (!chartArea) return;
      const { top, bottom, left, right } = chartArea;
      const centerConfig = chart.config.options.plugins?.centerText;
      if (!centerConfig || !centerConfig.display) return;

      ctx.save();
      const centerX = (left + right) / 2;
      const centerY = (top + bottom) / 2;

      // Label (Subheading)
      ctx.font = '500 11px Inter, system-ui, -apple-system, sans-serif';
      ctx.fillStyle = '#64748B';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(centerConfig.text || 'Net Revenue', centerX, centerY - 10);

      // Value (Primary Amount)
      ctx.font = '700 16px Inter, system-ui, -apple-system, sans-serif';
      ctx.fillStyle = document.documentElement.classList.contains('dark') ? '#F8FAFC' : '#0F172A';
      ctx.fillText(centerConfig.value || '', centerX, centerY + 10);
      ctx.restore();
    }
  };

  /**
   * Initializes Global Chart.js Defaults
   */
  function initCharts() {
    if (typeof Chart === 'undefined') {
      console.warn('[DashboardCharts] Chart.js is not loaded.');
      return;
    }

    try {
      Chart.register(centerTextPlugin);
    } catch (e) {}

    Chart.defaults.font.family = 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    Chart.defaults.font.size = 12;
    Chart.defaults.color = '#64748B';
    Chart.defaults.responsive = true;
    Chart.defaults.maintainAspectRatio = false;
    Chart.defaults.animation = {
      duration: 650,
      easing: 'easeOutQuart'
    };

    if (Chart.defaults.plugins && Chart.defaults.plugins.tooltip) {
      Chart.defaults.plugins.tooltip.backgroundColor = '#0F172A';
      Chart.defaults.plugins.tooltip.titleColor = '#F8FAFC';
      Chart.defaults.plugins.tooltip.bodyColor = '#E2E8F0';
      Chart.defaults.plugins.tooltip.borderColor = '#334155';
      Chart.defaults.plugins.tooltip.borderWidth = 1;
      Chart.defaults.plugins.tooltip.padding = 10;
      Chart.defaults.plugins.tooltip.cornerRadius = 8;
      Chart.defaults.plugins.tooltip.boxPadding = 4;
      Chart.defaults.plugins.tooltip.usePointStyle = true;
    }

    if (Chart.defaults.plugins && Chart.defaults.plugins.legend && Chart.defaults.plugins.legend.labels) {
      Chart.defaults.plugins.legend.labels.usePointStyle = true;
      Chart.defaults.plugins.legend.labels.pointStyle = 'circle';
      Chart.defaults.plugins.legend.labels.boxWidth = 8;
      Chart.defaults.plugins.legend.labels.padding = 16;
    }
  }

  function getCanvas(idOrSelector) {
    if (!idOrSelector) return null;
    if (idOrSelector.getContext) return idOrSelector;
    let el = document.getElementById(idOrSelector);
    if (!el) {
      el = document.querySelector(idOrSelector);
    }
    return el && el.getContext ? el : null;
  }

  /**
   * 1. REVENUE TREND (Stacked Bar for Brands + Line for Line Items Volume)
   */
  function renderRevenueTrend(trendData) {
    const canvas = getCanvas('canvas-revenue-trend') || getCanvas('chart-revenue-trend') || getCanvas('[data-chart="revenue-trend"]');
    if (!canvas) return null;

    let labels = ['Apr 2026', 'May 2026', 'Jun 2026', 'Jul 2026'];
    let nellon = [850000, 920000, 890000, 860000];
    let nonBranded = [620000, 680000, 640000, 630000];
    let raviya = [190000, 210000, 195000, 188300];
    let lineItems = [1120, 1340, 1260, 1180];

    if (trendData) {
      if (trendData.months && trendData.series) {
        labels = trendData.months;
        nellon = trendData.series.nellon || [];
        nonBranded = trendData.series.nonBranded || [];
        raviya = trendData.series.raviya || [];
        lineItems = trendData.series.lineItems || [];
      } else if (trendData.labels) {
        labels = trendData.labels;
        nellon = trendData.nellon || [];
        nonBranded = trendData.nonBranded || [];
        raviya = trendData.raviya || [];
        lineItems = trendData.lineItems || [];
      }
    }

    const datasets = [
      {
        type: 'bar',
        label: 'Nellon',
        data: nellon,
        backgroundColor: THEME_COLORS.brands['Nellon'].bg,
        hoverBackgroundColor: THEME_COLORS.brands['Nellon'].hover,
        borderRadius: 4,
        stack: 'revenue',
        yAxisID: 'y'
      },
      {
        type: 'bar',
        label: 'Non-Branded',
        data: nonBranded,
        backgroundColor: THEME_COLORS.brands['Non-Branded'].bg,
        hoverBackgroundColor: THEME_COLORS.brands['Non-Branded'].hover,
        borderRadius: 4,
        stack: 'revenue',
        yAxisID: 'y'
      },
      {
        type: 'bar',
        label: 'Raviya',
        data: raviya,
        backgroundColor: THEME_COLORS.brands['Raviya'].bg,
        hoverBackgroundColor: THEME_COLORS.brands['Raviya'].hover,
        borderRadius: 4,
        stack: 'revenue',
        yAxisID: 'y'
      },
      {
        type: 'line',
        label: 'Line Items Volume',
        data: lineItems,
        borderColor: THEME_COLORS.lineItems,
        backgroundColor: 'rgba(16, 185, 129, 0.1)',
        borderWidth: 2.5,
        tension: 0.35,
        pointBackgroundColor: '#10B981',
        pointBorderColor: '#FFFFFF',
        pointBorderWidth: 2,
        pointRadius: 4.5,
        pointHoverRadius: 6.5,
        yAxisID: 'y1'
      }
    ];

    if (instances.revenueTrend) {
      instances.revenueTrend.data.labels = labels;
      instances.revenueTrend.data.datasets = datasets;
      instances.revenueTrend.update();
      return instances.revenueTrend;
    }

    instances.revenueTrend = new Chart(canvas, {
      type: 'bar',
      data: { labels, datasets },
      options: {
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top', align: 'end' },
          tooltip: {
            callbacks: {
              label(context) {
                const label = context.dataset.label || '';
                if (context.dataset.yAxisID === 'y1') {
                  return `${label}: ${formatNumber(context.raw)} items`;
                }
                return `${label}: ${formatMoney(context.raw)}`;
              },
              footer(items) {
                let totalRev = 0;
                items.forEach(item => {
                  if (item.dataset.yAxisID !== 'y1') {
                    totalRev += (Number(item.raw) || 0);
                  }
                });
                return `Total Revenue: ${formatMoney(totalRev)}`;
              }
            }
          }
        },
        scales: {
          x: { grid: { display: false } },
          y: {
            type: 'linear',
            position: 'left',
            stacked: true,
            grid: { color: 'rgba(226, 232, 240, 0.5)' },
            ticks: { callback: val => formatMoney(val, true) }
          },
          y1: {
            type: 'linear',
            position: 'right',
            grid: { drawOnChartArea: false },
            ticks: { callback: val => formatNumber(val) }
          }
        }
      }
    });

    return instances.revenueTrend;
  }

  /**
   * 2. BRAND REVENUE DONUT (Nellon, Non-Branded, Raviya)
   */
  function renderBrandDonut(brandData) {
    const canvas = getCanvas('canvas-revenue-brand') || getCanvas('chart-brand-donut') || getCanvas('[data-chart="brand-donut"]');
    if (!canvas) return null;

    let brands = ['Nellon', 'Non-Branded', 'Raviya'];
    let revenues = [3520000, 2570000, 783300];
    let totalRev = 6873300;

    if (Array.isArray(brandData) && brandData.length > 0) {
      brands = brandData.map(b => b.brand);
      revenues = brandData.map(b => b.revenue);
      totalRev = revenues.reduce((a, b) => a + b, 0);
    } else if (brandData && brandData.brands) {
      brands = brandData.brands;
      revenues = brandData.revenues;
      totalRev = brandData.totalNetRevenue || revenues.reduce((a, b) => a + b, 0);
    }

    const bgColors = brands.map(b => THEME_COLORS.brands[b]?.bg || '#94A3B8');
    const hoverColors = brands.map(b => THEME_COLORS.brands[b]?.hover || '#64748B');

    const datasets = [{
      data: revenues,
      backgroundColor: bgColors,
      hoverBackgroundColor: hoverColors,
      borderWidth: 2,
      borderColor: '#FFFFFF',
      hoverOffset: 6
    }];

    if (instances.brandDonut) {
      instances.brandDonut.data.labels = brands;
      instances.brandDonut.data.datasets = datasets;
      if (instances.brandDonut.options.plugins.centerText) {
        instances.brandDonut.options.plugins.centerText.value = formatMoney(totalRev, true);
      }
      instances.brandDonut.update();
      return instances.brandDonut;
    }

    instances.brandDonut = new Chart(canvas, {
      type: 'doughnut',
      data: { labels: brands, datasets },
      options: {
        cutout: '72%',
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              generateLabels(chart) {
                const dataset = chart.data.datasets[0];
                return chart.data.labels.map((label, i) => {
                  const val = dataset.data[i] || 0;
                  const pct = totalRev > 0 ? ((val / totalRev) * 100).toFixed(1) : '0';
                  return {
                    text: `${label} (${pct}%)`,
                    fillStyle: dataset.backgroundColor[i],
                    strokeStyle: dataset.borderColor || '#FFF',
                    lineWidth: 1,
                    index: i
                  };
                });
              }
            }
          },
          centerText: {
            display: true,
            text: 'Net Revenue',
            value: formatMoney(totalRev, true)
          },
          tooltip: {
            callbacks: {
              label(context) {
                const val = context.raw || 0;
                const pct = totalRev > 0 ? ((val / totalRev) * 100).toFixed(1) : 0;
                return ` ${context.label}: ${formatMoney(val)} (${pct}%)`;
              }
            }
          }
        },
        onClick(evt, elements) {
          if (!elements.length) return;
          const index = elements[0].index;
          const selectedBrand = brands[index];
          if (window.AppState && typeof window.AppState.setFilter === 'function') {
            window.AppState.setFilter('brand', selectedBrand);
          }
        }
      }
    });

    return instances.brandDonut;
  }

  /**
   * 3. INVOICE STATUS (Horizontal Bar with Overdue in distinct red #EF4444)
   */
  function renderInvoiceStatus(statusData) {
    const canvas = getCanvas('canvas-invoice-status') || getCanvas('chart-invoice-status') || getCanvas('[data-chart="invoice-status"]');
    if (!canvas) return null;

    let labels = ['Open', 'Overdue', 'Partially Paid', 'Closed'];
    let revenues = [1490000, 3000000, 70400, 2310000];
    let counts = [280, 510, 15, 479];

    if (statusData) {
      if (Array.isArray(statusData.statuses)) {
        labels = statusData.statuses.map(s => s.status);
        revenues = statusData.statuses.map(s => s.revenue);
        counts = statusData.statuses.map(s => s.count);
      } else if (Array.isArray(statusData)) {
        labels = statusData.map(s => s.status || s.name);
        revenues = statusData.map(s => s.revenue || s.amount);
        counts = statusData.map(s => s.count || 0);
      } else if (statusData.labels) {
        labels = statusData.labels;
        revenues = statusData.revenues;
        counts = statusData.counts || [];
      }
    }

    const bgColors = labels.map(lbl => THEME_COLORS.status[lbl]?.bg || '#94A3B8');
    const hoverColors = labels.map(lbl => THEME_COLORS.status[lbl]?.hover || '#64748B');

    const datasets = [{
      label: 'Revenue',
      data: revenues,
      backgroundColor: bgColors,
      hoverBackgroundColor: hoverColors,
      borderRadius: 5,
      barThickness: 22
    }];

    if (instances.invoiceStatus) {
      instances.invoiceStatus.data.labels = labels;
      instances.invoiceStatus.data.datasets = datasets;
      instances.invoiceStatus.update();
      return instances.invoiceStatus;
    }

    instances.invoiceStatus = new Chart(canvas, {
      type: 'bar',
      data: { labels, datasets },
      options: {
        indexAxis: 'y',
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label(context) {
                const idx = context.dataIndex;
                const count = counts && counts[idx] ? `${counts[idx]} invoices` : '';
                return ` ${formatMoney(context.raw)} ${count ? '• ' + count : ''}`;
              }
            }
          }
        },
        scales: {
          x: {
            grid: { color: 'rgba(226, 232, 240, 0.5)' },
            ticks: { callback: val => formatMoney(val, true) }
          },
          y: { grid: { display: false } }
        },
        onClick(evt, elements) {
          if (!elements.length) return;
          const index = elements[0].index;
          const status = labels[index];
          if (window.AppState && typeof window.AppState.setFilter === 'function') {
            window.AppState.setFilter('status', status);
          }
        }
      }
    });

    return instances.invoiceStatus;
  }

  /**
   * 4. WEEKLY ACTIVITY (Bar / Area Combo for Weekly Volume & Revenue)
   */
  function renderWeeklyActivity(activityData) {
    const canvas = getCanvas('canvas-weekly-activity') || getCanvas('chart-weekly-activity') || getCanvas('[data-chart="weekly-activity"]');
    if (!canvas) return null;

    let labels = ['W1 (Apr)', 'W2 (Apr)', 'W3 (May)', 'W4 (May)', 'W5 (Jun)', 'W6 (Jun)', 'W7 (Jul)', 'W8 (Jul)'];
    let revenues = [410000, 520000, 480000, 610000, 590000, 640000, 580000, 620000];
    let invoices = [82, 104, 96, 122, 118, 128, 116, 124];

    if (activityData) {
      labels = activityData.labels || labels;
      revenues = activityData.revenues || revenues;
      invoices = activityData.invoices || invoices;
    }

    const datasets = [
      {
        type: 'bar',
        label: 'Weekly Revenue',
        data: revenues,
        backgroundColor: 'rgba(37, 99, 235, 0.85)',
        hoverBackgroundColor: '#1D4ED8',
        borderRadius: 4,
        yAxisID: 'y'
      },
      {
        type: 'line',
        label: 'Invoices Count',
        data: invoices,
        borderColor: '#F59E0B',
        backgroundColor: 'rgba(245, 158, 11, 0.1)',
        borderWidth: 2,
        tension: 0.3,
        pointRadius: 4,
        yAxisID: 'y1'
      }
    ];

    if (instances.weeklyActivity) {
      instances.weeklyActivity.data.labels = labels;
      instances.weeklyActivity.data.datasets = datasets;
      instances.weeklyActivity.update();
      return instances.weeklyActivity;
    }

    instances.weeklyActivity = new Chart(canvas, {
      type: 'bar',
      data: { labels, datasets },
      options: {
        interaction: { mode: 'index', intersect: false },
        plugins: {
          legend: { position: 'top', align: 'end' },
          tooltip: {
            callbacks: {
              label(context) {
                if (context.dataset.yAxisID === 'y1') {
                  return `Invoices: ${formatNumber(context.raw)}`;
                }
                return `Revenue: ${formatMoney(context.raw)}`;
              }
            }
          }
        },
        scales: {
          x: { grid: { display: false } },
          y: {
            type: 'linear',
            position: 'left',
            grid: { color: 'rgba(226, 232, 240, 0.5)' },
            ticks: { callback: val => formatMoney(val, true) }
          },
          y1: {
            type: 'linear',
            position: 'right',
            grid: { drawOnChartArea: false },
            ticks: { callback: val => formatNumber(val) }
          }
        }
      }
    });

    return instances.weeklyActivity;
  }

  /**
   * 5. ASP TREND (Multi-line Chart for Selected SKUs)
   */
  function renderASPTrend(aspData, selectedSKUs = []) {
    const canvas = getCanvas('canvas-asp-trend') || getCanvas('chart-asp-trend') || getCanvas('[data-chart="asp-trend"]');
    if (!canvas) return null;

    let months = ['Apr 2026', 'May 2026', 'Jun 2026', 'Jul 2026'];
    let series = [
      { sku: 'Nellon Basmati Rice 5kg', data: [42.5, 43.0, 42.8, 44.2] },
      { sku: 'Raviya Sunflower Oil 1L', data: [14.2, 14.5, 14.8, 14.6] },
      { sku: 'Sugar Premium 2kg', data: [8.5, 8.4, 8.6, 8.9] },
      { sku: 'Nellon Chakki Atta 10kg', data: [31.0, 31.5, 32.0, 32.2] }
    ];

    if (aspData) {
      if (aspData.months) months = aspData.months;
      if (Array.isArray(aspData.skus)) {
        series = aspData.skus.map(s => {
          let pts = [];
          if (Array.isArray(s.aspTrend)) {
            pts = s.aspTrend.map(t => (typeof t === 'object' && t !== null) ? (t.asp || 0) : (Number(t) || 0));
          } else if (Array.isArray(s.data)) {
            pts = s.data.map(t => (typeof t === 'object' && t !== null) ? (t.asp || 0) : (Number(t) || 0));
          }
          return { sku: s.name || s.sku, data: pts };
        });
      } else if (Array.isArray(aspData.series)) {
        series = aspData.series;
      }
    }

    let seriesToRender = series;
    if (selectedSKUs && selectedSKUs.length > 0) {
      seriesToRender = series.filter(s =>
        selectedSKUs.some(sel => sel.toLowerCase() === s.sku.toLowerCase() || s.sku.toLowerCase().includes(sel.toLowerCase()))
      );
    }
    if (!seriesToRender.length) seriesToRender = series.slice(0, 3);

    const datasets = seriesToRender.map((s, idx) => {
      const color = THEME_COLORS.skuPalette[idx % THEME_COLORS.skuPalette.length];
      return {
        label: s.sku,
        data: s.data,
        borderColor: color,
        backgroundColor: color,
        borderWidth: 2.2,
        tension: 0.3,
        pointRadius: 4,
        pointHoverRadius: 6,
        fill: false
      };
    });

    if (instances.aspTrend) {
      instances.aspTrend.data.labels = months;
      instances.aspTrend.data.datasets = datasets;
      instances.aspTrend.update();
      return instances.aspTrend;
    }

    instances.aspTrend = new Chart(canvas, {
      type: 'line',
      data: { labels: months, datasets },
      options: {
        plugins: {
          legend: {
            position: 'bottom',
            labels: { boxWidth: 8, padding: 12 }
          },
          tooltip: {
            callbacks: {
              label(context) {
                return ` ${context.dataset.label}: ${formatMoney(context.raw)}`;
              }
            }
          }
        },
        scales: {
          x: { grid: { display: false } },
          y: {
            grid: { color: 'rgba(226, 232, 240, 0.5)' },
            ticks: { callback: val => formatMoney(val) }
          }
        }
      }
    });

    return instances.aspTrend;
  }

  /**
   * 6. UPDATE ALL CHARTS
   */
  function updateAllCharts() {
    let rawInvoices = [];
    let state = {};

    if (window.AppState && typeof window.AppState.getState === 'function') {
      state = window.AppState.getState();
      rawInvoices = state.filteredInvoices || state.rawData || [];
    }

    let trendData = null;
    let brandData = null;
    let statusData = null;
    let weeklyData = null;
    let aspData = null;

    if (window.Calculations) {
      if (typeof window.Calculations.computeMonthlyTrend === 'function') {
        trendData = window.Calculations.computeMonthlyTrend(rawInvoices);
      } else if (typeof window.Calculations.getRevenueTrend === 'function') {
        trendData = window.Calculations.getRevenueTrend(rawInvoices);
      }

      if (typeof window.Calculations.computeBrandBreakdown === 'function') {
        brandData = window.Calculations.computeBrandBreakdown(rawInvoices);
      } else if (typeof window.Calculations.getBrandBreakdown === 'function') {
        brandData = window.Calculations.getBrandBreakdown(rawInvoices);
      }

      if (typeof window.Calculations.computeStatusBreakdown === 'function') {
        statusData = window.Calculations.computeStatusBreakdown(rawInvoices);
      } else if (typeof window.Calculations.getInvoiceStatusBreakdown === 'function') {
        statusData = window.Calculations.getInvoiceStatusBreakdown(rawInvoices);
      }

      if (typeof window.Calculations.computeASPTrend === 'function') {
        aspData = window.Calculations.computeASPTrend(rawInvoices, state.selectedSKUs);
      } else if (typeof window.Calculations.getASPTrend === 'function') {
        aspData = window.Calculations.getASPTrend(rawInvoices, state.selectedSKUs);
      }

      if (typeof window.Calculations.computeWeeklyActivity === 'function') {
        weeklyData = window.Calculations.computeWeeklyActivity(rawInvoices);
      }
    }

    renderRevenueTrend(trendData);
    renderBrandDonut(brandData);
    renderInvoiceStatus(statusData);
    renderWeeklyActivity(weeklyData);
    renderASPTrend(aspData, state.selectedSKUs);
  }

  function destroyAll() {
    Object.keys(instances).forEach(key => {
      if (instances[key]) {
        instances[key].destroy();
        instances[key] = null;
      }
    });
  }

  // Public Interface
  window.DashboardCharts = {
    initCharts,
    renderRevenueTrend,
    renderBrandDonut,
    renderInvoiceStatus,
    renderWeeklyActivity,
    renderASPTrend,
    updateAllCharts,
    destroyAll,
    getInstances: () => ({ ...instances })
  };

})();
