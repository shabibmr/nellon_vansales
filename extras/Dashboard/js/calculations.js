/**
 * Koyson Sales Dashboard - Calculations Engine
 * Decoupled, pure mathematical and business calculation functions.
 * Operates purely on invoice arrays, independent of DOM or UI libraries.
 * Compatible with Browser (window.Calculations) and Node.js.
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.Calculations = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const BRAND_COLORS = {
    Nellon: '#2563eb',
    'Non-Branded': '#64748b',
    Raviya: '#d97706',
    Other: '#94a3b8'
  };

  const STATUS_COLORS = {
    Open: '#0284c7',
    Overdue: '#dc2626',
    'Partially Paid': '#ea580c',
    Closed: '#16a34a'
  };

  /**
   * Helper to safely extract monetary total from an invoice.
   */
  function getInvoiceTotal(inv) {
    if (!inv) return 0;
    const val = inv.total !== undefined ? inv.total : inv.subtotal !== undefined ? inv.subtotal : inv.amount;
    return typeof val === 'number' ? val : parseFloat(val) || 0;
  }

  /**
   * Helper to normalize month key from invoice date (e.g. "2026-04-15" => "2026-04", "Apr 2026").
   */
  function extractMonthInfo(inv) {
    if (inv.monthKey && inv.monthLabel) {
      return { key: inv.monthKey, label: inv.monthLabel };
    }
    const dStr = inv.date || inv.invoiceDate;
    if (!dStr) return { key: 'Unknown', label: 'Unknown' };

    const parts = String(dStr).split('-');
    if (parts.length >= 2) {
      const y = parts[0];
      const mNum = parseInt(parts[1], 10);
      const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const label = `${mNames[mNum - 1] || 'Unknown'} ${y}`;
      return { key: `${y}-${String(mNum).padStart(2, '0')}`, label };
    }
    return { key: 'Unknown', label: 'Unknown' };
  }

  /**
   * Compute top-level summary KPIs.
   * @param {Array<Object>} invoices
   * @returns {{ netRevenue: number, invoiceCount: number, activeCustomers: number, aov: number, avgCreditPeriod: number }}
   */
  function computeKPIs(invoices = []) {
    if (!Array.isArray(invoices) || invoices.length === 0) {
      return {
        netRevenue: 0,
        invoiceCount: 0,
        activeCustomers: 0,
        aov: 0,
        avgCreditPeriod: 0
      };
    }

    let netRevenue = 0;
    let totalCreditDays = 0;
    let creditDaysCount = 0;
    const customerSet = new Set();

    for (let i = 0; i < invoices.length; i++) {
      const inv = invoices[i];
      const amt = getInvoiceTotal(inv);
      netRevenue += amt;

      const custName = inv.customerName || inv.customerId || inv.customer;
      if (custName) {
        customerSet.add(String(custName).trim());
      }

      if (inv.creditDays !== undefined && inv.creditDays !== null) {
        totalCreditDays += Number(inv.creditDays) || 0;
        creditDaysCount++;
      }
    }

    const invoiceCount = invoices.length;
    const aov = invoiceCount > 0 ? netRevenue / invoiceCount : 0;
    const avgCreditPeriod = creditDaysCount > 0 ? totalCreditDays / creditDaysCount : 0;

    return {
      netRevenue: Math.round(netRevenue * 100) / 100,
      invoiceCount,
      activeCustomers: customerSet.size,
      aov: Math.round(aov * 100) / 100,
      avgCreditPeriod: Math.round(avgCreditPeriod * 10) / 10
    };
  }

  /**
   * Compute revenue, share %, line items, invoice count and AOV grouped by brand.
   * @param {Array<Object>} invoices
   * @returns {Array<Object>} List of brands sorted by revenue desc
   */
  function computeBrandBreakdown(invoices = []) {
    if (!Array.isArray(invoices) || invoices.length === 0) {
      return [];
    }

    const brandMap = {};
    let totalRevenue = 0;

    invoices.forEach((inv) => {
      // Check if invoice has granular line items with distinct brands
      if (Array.isArray(inv.lineItems) && inv.lineItems.length > 0) {
        inv.lineItems.forEach((li) => {
          const b = li.brand || inv.brand || 'Other';
          const amt = Number(li.amount) || Number(li.total) || (Number(li.rate) * Number(li.quantity)) || 0;
          if (!brandMap[b]) {
            brandMap[b] = { brand: b, revenue: 0, invoiceIds: new Set(), lineItemsCount: 0 };
          }
          brandMap[b].revenue += amt;
          brandMap[b].lineItemsCount++;
          brandMap[b].invoiceIds.add(inv.invoiceId || inv.invoiceNumber || inv);
          totalRevenue += amt;
        });
      } else {
        const b = inv.brand || 'Other';
        const amt = getInvoiceTotal(inv);
        if (!brandMap[b]) {
          brandMap[b] = { brand: b, revenue: 0, invoiceIds: new Set(), lineItemsCount: 0 };
        }
        brandMap[b].revenue += amt;
        brandMap[b].lineItemsCount += inv.lineItemsCount || 1;
        brandMap[b].invoiceIds.add(inv.invoiceId || inv.invoiceNumber || inv);
        totalRevenue += amt;
      }
    });

    const result = Object.values(brandMap).map((item) => {
      const invCount = item.invoiceIds.size;
      const share = totalRevenue > 0 ? (item.revenue / totalRevenue) * 100 : 0;
      const aov = invCount > 0 ? item.revenue / invCount : 0;
      return {
        brand: item.brand,
        revenue: Math.round(item.revenue * 100) / 100,
        share: Math.round(share * 10) / 10,
        invoiceCount: invCount,
        lineItemsCount: item.lineItemsCount,
        aov: Math.round(aov * 100) / 100,
        color: BRAND_COLORS[item.brand] || BRAND_COLORS.Other
      };
    });

    result.sort((a, b) => b.revenue - a.revenue);
    return result;
  }

  /**
   * Compute revenue and counts by invoice status.
   * Highlights Overdue invoices with alert status.
   * @param {Array<Object>} invoices
   * @returns {{ statuses: Array<Object>, totalRevenue: number, totalCount: number, overdueAlert: boolean }}
   */
  function computeStatusBreakdown(invoices = []) {
    const statusMap = {
      Open: { status: 'Open', revenue: 0, count: 0, color: STATUS_COLORS.Open, badgeClass: 'badge-open' },
      Overdue: { status: 'Overdue', revenue: 0, count: 0, color: STATUS_COLORS.Overdue, badgeClass: 'badge-overdue', isAlert: true },
      'Partially Paid': { status: 'Partially Paid', revenue: 0, count: 0, color: STATUS_COLORS['Partially Paid'], badgeClass: 'badge-partial' },
      Closed: { status: 'Closed', revenue: 0, count: 0, color: STATUS_COLORS.Closed, badgeClass: 'badge-closed' }
    };

    let totalRevenue = 0;
    let totalCount = 0;

    (invoices || []).forEach((inv) => {
      let st = inv.status || 'Open';
      // Normalize common status naming variants
      const lower = st.toLowerCase().trim();
      if (lower.includes('overdue')) st = 'Overdue';
      else if (lower.includes('partially') || lower.includes('partial')) st = 'Partially Paid';
      else if (lower.includes('paid') || lower.includes('closed')) st = 'Closed';
      else if (lower.includes('open') || lower.includes('sent') || lower.includes('unpaid')) st = 'Open';
      else st = 'Open';

      if (!statusMap[st]) {
        statusMap[st] = { status: st, revenue: 0, count: 0, color: '#64748b', badgeClass: 'badge-neutral' };
      }

      const amt = getInvoiceTotal(inv);
      statusMap[st].revenue += amt;
      statusMap[st].count++;
      totalRevenue += amt;
      totalCount++;
    });

    const statusList = Object.values(statusMap).map((item) => {
      const share = totalRevenue > 0 ? (item.revenue / totalRevenue) * 100 : 0;
      return {
        ...item,
        revenue: Math.round(item.revenue * 100) / 100,
        share: Math.round(share * 10) / 10
      };
    });

    const overdueRevenue = statusMap.Overdue ? statusMap.Overdue.revenue : 0;
    const overdueAlert = totalRevenue > 0 ? (overdueRevenue / totalRevenue) >= 0.3 : false;

    return {
      statuses: statusList,
      totalRevenue: Math.round(totalRevenue * 100) / 100,
      totalCount,
      overdueAlert
    };
  }

  /**
   * Compute monthly timeline trends with stacked brand revenue and line-items overlay.
   * @param {Array<Object>} invoices
   * @returns {{ months: Array<string>, monthlyData: Array<Object>, series: Object }}
   */
  function computeMonthlyTrend(invoices = []) {
    const monthMap = {};

    (invoices || []).forEach((inv) => {
      const mInfo = extractMonthInfo(inv);
      if (!monthMap[mInfo.key]) {
        monthMap[mInfo.key] = {
          monthKey: mInfo.key,
          monthLabel: mInfo.label,
          revenue: 0,
          invoiceCount: 0,
          lineItemsCount: 0,
          brands: { Nellon: 0, 'Non-Branded': 0, Raviya: 0, Other: 0 }
        };
      }

      const mObj = monthMap[mInfo.key];
      const amt = getInvoiceTotal(inv);
      mObj.revenue += amt;
      mObj.invoiceCount++;

      if (Array.isArray(inv.lineItems) && inv.lineItems.length > 0) {
        inv.lineItems.forEach((li) => {
          const b = li.brand || inv.brand || 'Other';
          const lineAmt = Number(li.amount) || Number(li.rate) * Number(li.quantity) || 0;
          if (mObj.brands[b] === undefined) mObj.brands[b] = 0;
          mObj.brands[b] += lineAmt;
          mObj.lineItemsCount++;
        });
      } else {
        const b = inv.brand || 'Other';
        if (mObj.brands[b] === undefined) mObj.brands[b] = 0;
        mObj.brands[b] += amt;
        mObj.lineItemsCount += inv.lineItemsCount || 1;
      }
    });

    const sortedMonthKeys = Object.keys(monthMap).sort();
    const monthlyData = sortedMonthKeys.map((k) => monthMap[k]);

    return {
      monthKeys: sortedMonthKeys,
      months: monthlyData.map((m) => m.monthLabel),
      monthlyData,
      series: {
        nellon: monthlyData.map((m) => Math.round(m.brands.Nellon || 0)),
        nonBranded: monthlyData.map((m) => Math.round(m.brands['Non-Branded'] || 0)),
        raviya: monthlyData.map((m) => Math.round(m.brands.Raviya || 0)),
        totalRevenue: monthlyData.map((m) => Math.round(m.revenue)),
        lineItems: monthlyData.map((m) => m.lineItemsCount)
      }
    };
  }

  /**
   * Compute ranked customer list with revenue, share, invoice count, AOV, credit days.
   * @param {Array<Object>} invoices
   * @param {number} topN - Limit for top customers (default 10)
   * @returns {{ customers: Array<Object>, topNTotal: number, grandTotal: number }}
   */
  function computeCustomerMetrics(invoices = [], topN = 10) {
    const custMap = {};
    let grandTotal = 0;

    (invoices || []).forEach((inv) => {
      const name = inv.customerName || inv.customer || 'Unknown Customer';
      const id = inv.customerId || name;

      if (!custMap[name]) {
        custMap[name] = {
          id,
          name,
          revenue: 0,
          invoiceCount: 0,
          lineItemsCount: 0,
          creditDaysSum: 0,
          creditDaysCount: 0,
          creditTerms: inv.paymentTerms || '30 days',
          creditCategory: inv.creditCategory || '8–30 days',
          statusBreakdown: { open: 0, overdue: 0, partiallyPaid: 0, closed: 0 },
          invoices: []
        };
      }

      const amt = getInvoiceTotal(inv);
      const c = custMap[name];
      c.revenue += amt;
      c.invoiceCount++;
      c.lineItemsCount += Array.isArray(inv.lineItems) ? inv.lineItems.length : (inv.lineItemsCount || 1);

      if (inv.creditDays !== undefined && inv.creditDays !== null) {
        c.creditDaysSum += Number(inv.creditDays);
        c.creditDaysCount++;
      }

      const st = (inv.status || 'Open').toLowerCase();
      if (st.includes('overdue')) c.statusBreakdown.overdue += amt;
      else if (st.includes('partial')) c.statusBreakdown.partiallyPaid += amt;
      else if (st.includes('paid') || st.includes('closed')) c.statusBreakdown.closed += amt;
      else c.statusBreakdown.open += amt;

      c.invoices.push(inv);
      grandTotal += amt;
    });

    const sorted = Object.values(custMap).sort((a, b) => b.revenue - a.revenue);

    const ranked = sorted.map((c, index) => {
      const share = grandTotal > 0 ? (c.revenue / grandTotal) * 100 : 0;
      const aov = c.invoiceCount > 0 ? c.revenue / c.invoiceCount : 0;
      const avgCreditDays = c.creditDaysCount > 0 ? c.creditDaysSum / c.creditDaysCount : 0;
      return {
        rank: index + 1,
        id: c.id,
        name: c.name,
        revenue: Math.round(c.revenue * 100) / 100,
        share: Math.round(share * 10) / 10,
        invoiceCount: c.invoiceCount,
        lineItemsCount: c.lineItemsCount,
        aov: Math.round(aov * 100) / 100,
        avgCreditDays: Math.round(avgCreditDays * 10) / 10,
        creditTerms: c.creditTerms,
        creditCategory: c.creditCategory,
        statusBreakdown: c.statusBreakdown,
        invoices: c.invoices
      };
    });

    const topCustomers = ranked.slice(0, topN);
    const topNTotal = topCustomers.reduce((acc, c) => acc + c.revenue, 0);

    return {
      customers: ranked,
      topCustomers,
      topNTotal: Math.round(topNTotal * 100) / 100,
      grandTotal: Math.round(grandTotal * 100) / 100
    };
  }

  /**
   * Compute ranked category analysis with revenue, %, quantity, and line items.
   * @param {Array<Object>} invoices
   * @returns {Array<Object>}
   */
  function computeCategoryMetrics(invoices = []) {
    const catMap = {};
    let grandTotal = 0;

    (invoices || []).forEach((inv) => {
      if (Array.isArray(inv.lineItems) && inv.lineItems.length > 0) {
        inv.lineItems.forEach((li) => {
          const cat = li.category || 'Uncategorised';
          if (!catMap[cat]) {
            catMap[cat] = { category: cat, revenue: 0, quantity: 0, lineItemsCount: 0 };
          }
          const amt = Number(li.amount) || Number(li.rate) * Number(li.quantity) || 0;
          const qty = Number(li.quantity) || 1;
          catMap[cat].revenue += amt;
          catMap[cat].quantity += qty;
          catMap[cat].lineItemsCount++;
          grandTotal += amt;
        });
      } else {
        const cat = inv.category || 'Uncategorised';
        if (!catMap[cat]) {
          catMap[cat] = { category: cat, revenue: 0, quantity: 0, lineItemsCount: 0 };
        }
        const amt = getInvoiceTotal(inv);
        catMap[cat].revenue += amt;
        catMap[cat].quantity += inv.quantity || 1;
        catMap[cat].lineItemsCount += inv.lineItemsCount || 1;
        grandTotal += amt;
      }
    });

    const list = Object.values(catMap).map((item) => {
      const share = grandTotal > 0 ? (item.revenue / grandTotal) * 100 : 0;
      const avgLineVal = item.lineItemsCount > 0 ? item.revenue / item.lineItemsCount : 0;
      return {
        category: item.category,
        revenue: Math.round(item.revenue * 100) / 100,
        share: Math.round(share * 10) / 10,
        quantity: Math.round(item.quantity),
        lineItemsCount: item.lineItemsCount,
        avgLineValue: Math.round(avgLineVal * 100) / 100
      };
    });

    list.sort((a, b) => b.revenue - a.revenue);
    return list;
  }

  /**
   * Compute POC (Salesperson) performance table metrics.
   * @param {Array<Object>} invoices
   * @returns {Array<Object>}
   */
  function computePOCMetrics(invoices = []) {
    const pocMap = {};
    let grandTotal = 0;

    (invoices || []).forEach((inv) => {
      const poc = inv.salesperson || inv.poc || 'Unassigned';
      if (!pocMap[poc]) {
        pocMap[poc] = {
          salesperson: poc,
          revenue: 0,
          invoiceCount: 0,
          lineItemsCount: 0,
          quantitySum: 0,
          creditDaysSum: 0,
          creditDaysCount: 0
        };
      }

      const p = pocMap[poc];
      const amt = getInvoiceTotal(inv);
      p.revenue += amt;
      p.invoiceCount++;

      if (Array.isArray(inv.lineItems) && inv.lineItems.length > 0) {
        inv.lineItems.forEach((li) => {
          p.quantitySum += Number(li.quantity) || 0;
          p.lineItemsCount++;
        });
      } else {
        p.quantitySum += Number(inv.quantity) || 10;
        p.lineItemsCount += inv.lineItemsCount || 1;
      }

      if (inv.creditDays !== undefined && inv.creditDays !== null) {
        p.creditDaysSum += Number(inv.creditDays);
        p.creditDaysCount++;
      }

      grandTotal += amt;
    });

    const list = Object.values(pocMap).map((p) => {
      const share = grandTotal > 0 ? (p.revenue / grandTotal) * 100 : 0;
      const aov = p.invoiceCount > 0 ? p.revenue / p.invoiceCount : 0;
      const aoq = p.invoiceCount > 0 ? p.quantitySum / p.invoiceCount : 0;
      const avgCreditDays = p.creditDaysCount > 0 ? p.creditDaysSum / p.creditDaysCount : 0;
      return {
        salesperson: p.salesperson,
        revenue: Math.round(p.revenue * 100) / 100,
        share: Math.round(share * 10) / 10,
        invoiceCount: p.invoiceCount,
        lineItemsCount: p.lineItemsCount,
        aov: Math.round(aov * 100) / 100,
        aoq: Math.round(aoq),
        avgCreditDays: Math.round(avgCreditDays * 10) / 10
      };
    });

    list.sort((a, b) => b.revenue - a.revenue);
    return list;
  }

  /**
   * Compute Customer x Product Category Heatmap Matrix and credit category breakdown.
   * @param {Array<Object>} invoices
   * @param {number} topCustomersCount - default 10
   * @param {number} topCategoriesCount - default 8
   */
  function computeCustomerProductMatrix(invoices = [], topCustomersCount = 10, topCategoriesCount = 8) {
    const custMetrics = computeCustomerMetrics(invoices, topCustomersCount);
    const catMetrics = computeCategoryMetrics(invoices).slice(0, topCategoriesCount);

    const targetCustomerNames = custMetrics.topCustomers.map((c) => c.name);
    const targetCategories = catMetrics.map((c) => c.category);

    // Initialize customer rows
    const matrixData = targetCustomerNames.map((custName) => ({
      name: custName,
      values: targetCategories.map(() => 0),
      total: 0
    }));

    const custIndexMap = {};
    targetCustomerNames.forEach((n, idx) => {
      custIndexMap[n] = idx;
    });

    const catIndexMap = {};
    targetCategories.forEach((c, idx) => {
      catIndexMap[c] = idx;
    });

    // Credit breakdown across the entire invoice set
    const creditBuckets = {
      Cash: { category: 'Cash', revenue: 0, invoiceCount: 0, customerCount: 0, customerSet: new Set() },
      '8–30 days': { category: '8–30 days', revenue: 0, invoiceCount: 0, customerCount: 0, customerSet: new Set() },
      '31–60 days': { category: '31–60 days', revenue: 0, invoiceCount: 0, customerCount: 0, customerSet: new Set() },
      '61–90 days': { category: '61–90 days', revenue: 0, invoiceCount: 0, customerCount: 0, customerSet: new Set() }
    };

    let grandTotal = 0;

    (invoices || []).forEach((inv) => {
      const amt = getInvoiceTotal(inv);
      grandTotal += amt;
      const custName = inv.customerName || inv.customer;
      const cIdx = custIndexMap[custName];

      // Credit categorization
      let days = Number(inv.creditDays) || 0;
      let catKey = 'Cash';
      if (days === 0 || inv.paymentTerms === 'Cash') catKey = 'Cash';
      else if (days <= 30) catKey = '8–30 days';
      else if (days <= 60) catKey = '31–60 days';
      else catKey = '61–90 days';

      if (creditBuckets[catKey]) {
        creditBuckets[catKey].revenue += amt;
        creditBuckets[catKey].invoiceCount++;
        if (custName) creditBuckets[catKey].customerSet.add(custName);
      }

      // Populate matrix cells
      if (cIdx !== undefined) {
        if (Array.isArray(inv.lineItems) && inv.lineItems.length > 0) {
          inv.lineItems.forEach((li) => {
            const cat = li.category;
            const kIdx = catIndexMap[cat];
            if (kIdx !== undefined) {
              const lineAmt = Number(li.amount) || Number(li.rate) * Number(li.quantity) || 0;
              matrixData[cIdx].values[kIdx] += lineAmt;
              matrixData[cIdx].total += lineAmt;
            }
          });
        } else {
          const cat = inv.category;
          const kIdx = catIndexMap[cat];
          if (kIdx !== undefined) {
            matrixData[cIdx].values[kIdx] += amt;
            matrixData[cIdx].total += amt;
          }
        }
      }
    });

    // Format credit categories
    const creditCategoryList = Object.values(creditBuckets).map((b) => {
      const share = grandTotal > 0 ? (b.revenue / grandTotal) * 100 : 0;
      return {
        category: b.category,
        revenue: Math.round(b.revenue * 100) / 100,
        share: Math.round(share * 10) / 10,
        invoiceCount: b.invoiceCount,
        customerCount: b.customerSet.size
      };
    });

    return {
      categories: targetCategories,
      customers: matrixData.map((row) => ({
        name: row.name,
        values: row.values.map((v) => Math.round(v)),
        total: Math.round(row.total)
      })),
      creditCategories: creditCategoryList
    };
  }

  /**
   * Compute ASP (Average Selling Price) trend points per SKU.
   * @param {Array<Object>} invoices
   * @param {Array<string>} selectedSKUs - list of SKU identifiers
   * @returns {{ months: Array<string>, skus: Array<Object> }}
   */
  function computeASPTrend(invoices = [], selectedSKUs = []) {
    const monthSet = new Set();
    const skuMonthMap = {};

    (invoices || []).forEach((inv) => {
      const mInfo = extractMonthInfo(inv);
      monthSet.add(mInfo.key);

      if (Array.isArray(inv.lineItems)) {
        inv.lineItems.forEach((li) => {
          const sku = li.sku;
          if (!selectedSKUs || selectedSKUs.length === 0 || selectedSKUs.includes(sku)) {
            if (!skuMonthMap[sku]) {
              skuMonthMap[sku] = {
                sku,
                name: li.name || sku,
                category: li.category,
                brand: li.brand,
                monthlySales: {}
              };
            }
            if (!skuMonthMap[sku].monthlySales[mInfo.key]) {
              skuMonthMap[sku].monthlySales[mInfo.key] = { amount: 0, quantity: 0 };
            }
            skuMonthMap[sku].monthlySales[mInfo.key].amount += Number(li.amount) || (Number(li.rate) * Number(li.quantity)) || 0;
            skuMonthMap[sku].monthlySales[mInfo.key].quantity += Number(li.quantity) || 1;
          }
        });
      }
    });

    const sortedMonthKeys = Array.from(monthSet).sort();
    const monthLabels = sortedMonthKeys.map((k) => {
      const parts = k.split('-');
      const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return parts.length === 2 ? `${mNames[parseInt(parts[1], 10) - 1]} ${parts[0]}` : k;
    });

    const skuResults = Object.values(skuMonthMap).map((item) => {
      const trend = sortedMonthKeys.map((k) => {
        const data = item.monthlySales[k];
        if (!data || data.quantity === 0) return null;
        return Math.round((data.amount / data.quantity) * 100) / 100;
      });
      return {
        sku: item.sku,
        name: item.name,
        category: item.category,
        brand: item.brand,
        aspTrend: trend
      };
    });

    return {
      monthKeys: sortedMonthKeys,
      months: monthLabels,
      skus: skuResults
    };
  }

  /**
   * Compute Period Comparison between current and previous periods.
   * @param {Array<Object>} currentInvoices
   * @param {Array<Object>} previousInvoices
   * @returns {{ current: Object, previous: Object, differences: Object, growthPercent: Object }}
   */
  function computePeriodComparison(currentInvoices = [], previousInvoices = []) {
    const currentKPIs = computeKPIs(currentInvoices);
    const prevKPIs = computeKPIs(previousInvoices);

    function calcGrowth(curr, prev) {
      if (!prev || prev === 0) return { diff: curr, percent: 0, direction: 'neutral' };
      const diff = curr - prev;
      const pct = (diff / prev) * 100;
      return {
        absolute: Math.round(diff * 100) / 100,
        percent: Math.round(pct * 10) / 10,
        direction: pct > 0 ? 'up' : pct < 0 ? 'down' : 'neutral',
        isPositive: pct >= 0
      };
    }

    return {
      current: currentKPIs,
      previous: prevKPIs,
      differences: {
        revenue: calcGrowth(currentKPIs.netRevenue, prevKPIs.netRevenue),
        invoices: calcGrowth(currentKPIs.invoiceCount, prevKPIs.invoiceCount),
        activeCustomers: calcGrowth(currentKPIs.activeCustomers, prevKPIs.activeCustomers),
        aov: calcGrowth(currentKPIs.aov, prevKPIs.aov),
        avgCreditPeriod: calcGrowth(currentKPIs.avgCreditPeriod, prevKPIs.avgCreditPeriod)
      }
    };
  }

  /**
   * Compute weekly activity (revenue and invoice counts) dynamically from invoices.
   */
  function computeWeeklyActivity(invoices = []) {
    if (!Array.isArray(invoices) || invoices.length === 0) {
      return {
        labels: ['W1 (Apr)', 'W2 (Apr)', 'W3 (May)', 'W4 (May)', 'W5 (Jun)', 'W6 (Jun)', 'W7 (Jul)', 'W8 (Jul)'],
        revenues: [0, 0, 0, 0, 0, 0, 0, 0],
        invoices: [0, 0, 0, 0, 0, 0, 0, 0]
      };
    }

    const sorted = [...invoices].filter(inv => inv.date).sort((a, b) => (a.date < b.date ? -1 : 1));
    if (sorted.length === 0) {
      return {
        labels: ['W1 (Apr)', 'W2 (Apr)', 'W3 (May)', 'W4 (May)', 'W5 (Jun)', 'W6 (Jun)', 'W7 (Jul)', 'W8 (Jul)'],
        revenues: [0, 0, 0, 0, 0, 0, 0, 0],
        invoices: [0, 0, 0, 0, 0, 0, 0, 0]
      };
    }

    const minTime = new Date(sorted[0].date).getTime();
    const maxTime = new Date(sorted[sorted.length - 1].date).getTime();
    const span = Math.max(86400000 * 7, maxTime - minTime);
    const numBuckets = 8;
    const bucketDuration = span / numBuckets;

    const revenues = new Array(numBuckets).fill(0);
    const invCounts = new Array(numBuckets).fill(0);
    const labels = [];
    const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    for (let b = 0; b < numBuckets; b++) {
      const bDate = new Date(minTime + b * bucketDuration);
      const mStr = mNames[bDate.getMonth()] || '';
      labels.push(`W${b + 1} (${mStr})`);
    }

    sorted.forEach(inv => {
      const t = new Date(inv.date).getTime();
      let bIdx = Math.floor((t - minTime) / bucketDuration);
      if (bIdx >= numBuckets) bIdx = numBuckets - 1;
      if (bIdx < 0) bIdx = 0;
      revenues[bIdx] += getInvoiceTotal(inv);
      invCounts[bIdx]++;
    });

    return {
      labels,
      revenues: revenues.map(r => Math.round(r * 100) / 100),
      invoices: invCounts
    };
  }

  return {
    getInvoiceTotal,
    computeKPIs,
    calculateKPIs: computeKPIs,
    computeBrandBreakdown,
    computeStatusBreakdown,
    computeMonthlyTrend,
    computeCustomerMetrics,
    computeCategoryMetrics,
    computePOCMetrics,
    computeCustomerProductMatrix,
    computeASPTrend,
    computePeriodComparison,
    computeWeeklyActivity
  };
});
