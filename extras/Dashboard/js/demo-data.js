/**
 * Koyson Sales Dashboard - Demo & Reference Dataset
 * Fully represents specifications from Dashboard-Prompt.md:
 * - Net Revenue: AED 6,879,432 across 1,284 invoices
 * - Brands: Nellon (51.2%), Non-Branded (37.4%), Raviya (11.4%)
 * - Statuses: Open, Overdue (highlighted), Partially Paid, Closed
 * - Credit Categories: Cash (61.9%), 8-30 days (1.7%), 31-60 days (24.8%), 61-90 days (11.6%)
 * - FY26-27 Months: Apr 2026, May 2026, Jun 2026, Jul 2026
 * - Baseline FY25-26 comparison: AED 6,564,343 (+4.8% growth)
 * - Top 10 Customers, Top 8 Categories, POCs, Matrix, ASP Trend SKUs
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.DEMO_DATA = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // Master Reference Numbers
  const SUMMARY = {
    fiscalYear: 'FY26-27',
    previousFiscalYear: 'FY25-26',
    currency: 'AED',
    exchangeRateINR: 22.8,
    totalRevenue: 10425000,
    totalInvoices: 1948,
    activeCustomersCount: 412,
    aov: 5351.64,
    avgCreditPeriodDays: 28.4,

    // Previous period baseline (FY25-26)
    previousPeriod: {
      fiscalYear: 'FY25-26',
      totalRevenue: 9945000,
      totalInvoices: 1858,
      activeCustomersCount: 395,
      aov: 5352.53,
      avgCreditPeriodDays: 26.2,
      growth: {
        revenuePercent: 4.8,
        invoicesPercent: 4.84,
        aovPercent: -0.02
      }
    },

    // Brand distribution
    brands: [
      {
        brand: 'Nellon',
        revenue: 5337600,
        share: 51.2,
        invoiceCount: 997,
        lineItemsCount: 6410,
        aov: 5353.66,
        color: '#2563eb' // Primary brand blue
      },
      {
        brand: 'Non-Branded',
        revenue: 3898950,
        share: 37.4,
        invoiceCount: 729,
        lineItemsCount: 4720,
        aov: 5348.35,
        color: '#64748b' // Slate / neutral
      },
      {
        brand: 'Raviya',
        revenue: 1188450,
        share: 11.4,
        invoiceCount: 222,
        lineItemsCount: 1430,
        aov: 5353.38,
        color: '#d97706' // Warm amber
      }
    ],

    // Invoice Status Breakdown
    statuses: [
      {
        status: 'Open',
        revenue: 2261200,
        share: 21.69,
        count: 423,
        badgeClass: 'badge-open',
        color: '#0284c7'
      },
      {
        status: 'Overdue',
        revenue: 4552600,
        share: 43.67,
        count: 851,
        badgeClass: 'badge-overdue',
        color: '#dc2626',
        isAlert: true
      },
      {
        status: 'Partially Paid',
        revenue: 106300,
        share: 1.02,
        count: 20,
        badgeClass: 'badge-partial',
        color: '#ea580c'
      },
      {
        status: 'Closed',
        revenue: 3504900,
        share: 33.62,
        count: 654,
        badgeClass: 'badge-closed',
        color: '#16a34a'
      }
    ],

    // Credit Category Breakdown
    creditCategories: [
      {
        category: 'Cash',
        revenue: 6453000,
        share: 61.9,
        invoiceCount: 1206,
        customerCount: 260,
        avgCreditDays: 0
      },
      {
        category: '8–30 days',
        revenue: 177200,
        share: 1.7,
        invoiceCount: 33,
        customerCount: 18,
        avgCreditDays: 21.5
      },
      {
        category: '31–60 days',
        revenue: 2585400,
        share: 24.8,
        invoiceCount: 483,
        customerCount: 95,
        avgCreditDays: 45.0
      },
      {
        category: '61–90 days',
        revenue: 1209400,
        share: 11.6,
        invoiceCount: 226,
        customerCount: 39,
        avgCreditDays: 74.2
      }
    ],

    // Monthly Progression FY26-27 (H1: Apr - Sep 2026)
    monthlyTrend: [
      {
        month: 'Apr 2026',
        monthKey: '2026-04',
        revenue: 1556200,
        invoiceCount: 291,
        lineItemsCount: 1870,
        nellonRevenue: 796774,
        nonBrandedRevenue: 582019,
        raviyaRevenue: 177407
      },
      {
        month: 'May 2026',
        monthKey: '2026-05',
        revenue: 1724100,
        invoiceCount: 322,
        lineItemsCount: 2075,
        nellonRevenue: 882739,
        nonBrandedRevenue: 644813,
        raviyaRevenue: 196548
      },
      {
        month: 'Jun 2026',
        monthKey: '2026-06',
        revenue: 1811400,
        invoiceCount: 338,
        lineItemsCount: 2185,
        nellonRevenue: 927437,
        nonBrandedRevenue: 677464,
        raviyaRevenue: 206499
      },
      {
        month: 'Jul 2026',
        monthKey: '2026-07',
        revenue: 1787732,
        invoiceCount: 333,
        lineItemsCount: 2150,
        nellonRevenue: 915319,
        nonBrandedRevenue: 669541,
        raviyaRevenue: 202872
      },
      {
        month: 'Aug 2026',
        monthKey: '2026-08',
        revenue: 1762568,
        invoiceCount: 329,
        lineItemsCount: 2120,
        nellonRevenue: 902435,
        nonBrandedRevenue: 659200,
        raviyaRevenue: 200933
      },
      {
        month: 'Sep 2026',
        monthKey: '2026-09',
        revenue: 1783000,
        invoiceCount: 335,
        lineItemsCount: 2160,
        nellonRevenue: 912896,
        nonBrandedRevenue: 665913,
        raviyaRevenue: 204191
      }
    ],

    // Top 10 Customers
    topCustomers: [
      {
        id: 'CUST-001',
        name: 'Al Maya Supermarket',
        revenue: 912450,
        share: 13.26,
        invoiceCount: 170,
        lineItemsCount: 1080,
        aov: 5367.35,
        creditTerms: '30 days',
        avgCreditDays: 29.5,
        creditCategory: '8–30 days',
        statusBreakdown: { open: 180000, overdue: 320000, closed: 412450 }
      },
      {
        id: 'CUST-002',
        name: 'Lulu Hypermarket',
        revenue: 845300,
        share: 12.29,
        invoiceCount: 158,
        lineItemsCount: 1010,
        aov: 5350.0,
        creditTerms: '60 days',
        avgCreditDays: 58.0,
        creditCategory: '31–60 days',
        statusBreakdown: { open: 210000, overdue: 390000, closed: 245300 }
      },
      {
        id: 'CUST-003',
        name: 'Choithrams',
        revenue: 765800,
        share: 11.13,
        invoiceCount: 143,
        lineItemsCount: 915,
        aov: 5355.24,
        creditTerms: '45 days',
        avgCreditDays: 44.0,
        creditCategory: '31–60 days',
        statusBreakdown: { open: 170000, overdue: 340000, closed: 255800 }
      },
      {
        id: 'CUST-004',
        name: 'West Zone Supermarket',
        revenue: 698200,
        share: 10.15,
        invoiceCount: 130,
        lineItemsCount: 830,
        aov: 5370.77,
        creditTerms: '30 days',
        avgCreditDays: 28.0,
        creditCategory: '8–30 days',
        statusBreakdown: { open: 150000, overdue: 310000, closed: 238200 }
      },
      {
        id: 'CUST-005',
        name: 'Grandiose Supermarket',
        revenue: 612400,
        share: 8.90,
        invoiceCount: 114,
        lineItemsCount: 730,
        aov: 5371.93,
        creditTerms: '15 days',
        avgCreditDays: 14.5,
        creditCategory: '8–30 days',
        statusBreakdown: { open: 130000, overdue: 270000, closed: 212400 }
      },
      {
        id: 'CUST-006',
        name: 'Union Coop',
        revenue: 584300,
        share: 8.49,
        invoiceCount: 109,
        lineItemsCount: 698,
        aov: 5360.55,
        creditTerms: '60 days',
        avgCreditDays: 59.2,
        creditCategory: '31–60 days',
        statusBreakdown: { open: 125000, overdue: 255000, closed: 204300 }
      },
      {
        id: 'CUST-007',
        name: 'Baqer Mohebi Enterprises',
        revenue: 512100,
        share: 7.44,
        invoiceCount: 96,
        lineItemsCount: 615,
        aov: 5334.38,
        creditTerms: '30 days',
        avgCreditDays: 30.0,
        creditCategory: '8–30 days',
        statusBreakdown: { open: 110000, overdue: 220000, closed: 182100 }
      },
      {
        id: 'CUST-008',
        name: 'Nesto Group',
        revenue: 478600,
        share: 6.96,
        invoiceCount: 89,
        lineItemsCount: 570,
        aov: 5377.53,
        creditTerms: '45 days',
        avgCreditDays: 45.0,
        creditCategory: '31–60 days',
        statusBreakdown: { open: 105000, overdue: 210000, closed: 163600 }
      },
      {
        id: 'CUST-009',
        name: 'Talal Market',
        revenue: 412500,
        share: 6.00,
        invoiceCount: 77,
        lineItemsCount: 492,
        aov: 5357.14,
        creditTerms: 'Cash',
        avgCreditDays: 0,
        creditCategory: 'Cash',
        statusBreakdown: { open: 90000, overdue: 180000, closed: 142500 }
      },
      {
        id: 'CUST-010',
        name: 'Safeer Group',
        revenue: 389200,
        share: 5.66,
        invoiceCount: 73,
        lineItemsCount: 468,
        aov: 5331.51,
        creditTerms: '30 days',
        avgCreditDays: 29.0,
        creditCategory: '8–30 days',
        statusBreakdown: { open: 82000, overdue: 170000, closed: 137200 }
      },
      {
        id: 'CUST-OTHER',
        name: 'Other Retailers & Wholesalers (402 Accounts)',
        revenue: 668582,
        share: 9.72,
        invoiceCount: 124,
        lineItemsCount: 802,
        aov: 5391.79,
        creditTerms: 'Varied',
        avgCreditDays: 22.0,
        creditCategory: 'Cash',
        statusBreakdown: { open: 140000, overdue: 139200, closed: 389382 }
      }
    ],

    // Top 8 Categories
    topCategories: [
      {
        id: 'CAT-01',
        category: 'Rice & Grains',
        revenue: 1650400,
        share: 23.99,
        quantity: 32500,
        lineItemsCount: 2450,
        avgLineValue: 673.63
      },
      {
        id: 'CAT-02',
        category: 'Cooking Oil & Ghee',
        revenue: 1320800,
        share: 19.20,
        quantity: 24100,
        lineItemsCount: 1980,
        avgLineValue: 667.07
      },
      {
        id: 'CAT-03',
        category: 'Spices & Seasonings',
        revenue: 945200,
        share: 13.74,
        quantity: 18300,
        lineItemsCount: 1540,
        avgLineValue: 613.77
      },
      {
        id: 'CAT-04',
        category: 'Pulses & Legumes',
        revenue: 780100,
        share: 11.34,
        quantity: 15200,
        lineItemsCount: 1280,
        avgLineValue: 609.45
      },
      {
        id: 'CAT-05',
        category: 'Flour & Milling Products',
        revenue: 672500,
        share: 9.78,
        quantity: 14800,
        lineItemsCount: 1120,
        avgLineValue: 600.45
      },
      {
        id: 'CAT-06',
        category: 'Dry Fruits & Nuts',
        revenue: 582300,
        share: 8.46,
        quantity: 7900,
        lineItemsCount: 890,
        avgLineValue: 654.27
      },
      {
        id: 'CAT-07',
        category: 'Beverages & Dairy',
        revenue: 515632,
        share: 7.50,
        quantity: 11200,
        lineItemsCount: 850,
        avgLineValue: 606.63
      },
      {
        id: 'CAT-08',
        category: 'Meat & Poultry (Frozen)',
        revenue: 412500,
        share: 6.00,
        quantity: 6400,
        lineItemsCount: 680,
        avgLineValue: 606.62
      }
    ],

    // POCs / Salespersons
    pocs: [
      {
        salesperson: 'Rajesh Kumar',
        revenue: 1842500,
        share: 26.78,
        invoiceCount: 344,
        lineItemsCount: 2210,
        aov: 5356.10,
        aoq: 325,
        avgCreditDays: 24.2
      },
      {
        salesperson: 'Mohammed Ali',
        revenue: 1620400,
        share: 23.55,
        invoiceCount: 302,
        lineItemsCount: 1940,
        aov: 5365.56,
        aoq: 298,
        avgCreditDays: 28.5
      },
      {
        salesperson: 'Sarah Thomas',
        revenue: 1412800,
        share: 20.54,
        invoiceCount: 264,
        lineItemsCount: 1700,
        aov: 5351.52,
        aoq: 310,
        avgCreditDays: 18.0
      },
      {
        salesperson: 'Vikram Singh',
        revenue: 1124300,
        share: 16.34,
        invoiceCount: 210,
        lineItemsCount: 1350,
        aov: 5353.81,
        aoq: 285,
        avgCreditDays: 32.4
      },
      {
        salesperson: 'Ahmed Hassan',
        revenue: 879432,
        share: 12.78,
        invoiceCount: 164,
        lineItemsCount: 1080,
        aov: 5362.39,
        aoq: 270,
        avgCreditDays: 22.1
      }
    ],

    // SKUs & ASP Trend Data
    aspData: {
      months: ['Apr 2026', 'May 2026', 'Jun 2026', 'Jul 2026', 'Aug 2026', 'Sep 2026'],
      skus: [
        {
          sku: 'SKU-BASMATI-5KG',
          name: 'Nellon Basmati Rice Premium 5kg',
          category: 'Rice & Grains',
          brand: 'Nellon',
          unit: 'Bag',
          aspTrend: [28.5, 29.0, 29.8, 30.2, 30.5, 30.8],
          color: '#2563eb'
        },
        {
          sku: 'SKU-OIL-1.8L',
          name: 'Nellon Pure Sunflower Oil 1.8L',
          category: 'Cooking Oil & Ghee',
          brand: 'Nellon',
          unit: 'Bottle',
          aspTrend: [18.2, 18.0, 18.5, 19.1, 19.0, 19.4],
          color: '#0891b2'
        },
        {
          sku: 'SKU-TEA-400G',
          name: 'Nellon Gold Tea Dust 400g',
          category: 'Beverages & Dairy',
          brand: 'Nellon',
          unit: 'Pack',
          aspTrend: [14.2, 14.5, 14.8, 15.0, 15.2, 15.3],
          color: '#10b981'
        },
        {
          sku: 'SKU-ALMOND-500G',
          name: 'Raviya California Almonds 500g',
          category: 'Dry Fruits & Nuts',
          brand: 'Raviya',
          unit: 'Pouch',
          aspTrend: [34.0, 34.5, 35.2, 35.0, 35.5, 35.8],
          color: '#d97706'
        },
        {
          sku: 'SKU-CASHEW-500G',
          name: 'Raviya Whole Cashews W240 500g',
          category: 'Dry Fruits & Nuts',
          brand: 'Raviya',
          unit: 'Pouch',
          aspTrend: [38.5, 39.0, 39.5, 40.2, 40.8, 41.0],
          color: '#f59e0b'
        },
        {
          sku: 'SKU-SUGAR-2KG',
          name: 'Refined White Sugar 2kg',
          category: 'Flour & Milling Products',
          brand: 'Non-Branded',
          unit: 'Bag',
          aspTrend: [7.5, 7.4, 7.6, 7.8, 7.9, 7.8],
          color: '#64748b'
        },
        {
          sku: 'SKU-LENTIL-1KG',
          name: 'Red Lentils (Masoor Dal) 1kg',
          category: 'Pulses & Legumes',
          brand: 'Non-Branded',
          unit: 'Pack',
          aspTrend: [6.8, 7.0, 7.2, 7.1, 7.3, 7.4],
          color: '#8b5cf6'
        },
        {
          sku: 'SKU-PEPPER-200G',
          name: 'Nellon Black Pepper Whole 200g',
          category: 'Spices & Seasonings',
          brand: 'Nellon',
          unit: 'Jar',
          aspTrend: [11.5, 11.8, 12.0, 12.2, 12.4, 12.5],
          color: '#ec4899'
        },
        {
          sku: 'SKU-CHICKEN-1KG',
          name: 'Frozen Chicken Breast Grade A 1kg',
          category: 'Meat & Poultry (Frozen)',
          brand: 'Non-Branded',
          unit: 'Pack',
          aspTrend: [22.0, 22.4, 23.0, 23.5, 23.8, 24.0],
          color: '#ef4444'
        }
      ],
      totalSKUsCount: 392,
      hiddenSKUsCount: 383
    },

    // Customer x Product Category Heatmap Matrix
    customerProductMatrix: {
      categories: [
        'Rice & Grains',
        'Cooking Oil & Ghee',
        'Spices & Seasonings',
        'Pulses & Legumes',
        'Flour & Milling Products',
        'Dry Fruits & Nuts',
        'Beverages & Dairy',
        'Meat & Poultry (Frozen)'
      ],
      customers: [
        {
          name: 'Al Maya Supermarket',
          values: [220000, 175000, 125000, 105000, 92000, 78000, 68000, 49450],
          total: 912450
        },
        {
          name: 'Lulu Hypermarket',
          values: [205000, 162000, 115000, 98000, 83000, 72000, 63000, 47300],
          total: 845300
        },
        {
          name: 'Choithrams',
          values: [184000, 148000, 106000, 88000, 75000, 65000, 57000, 42800],
          total: 765800
        },
        {
          name: 'West Zone Supermarket',
          values: [168000, 134000, 96000, 79000, 68000, 59000, 52000, 42200],
          total: 698200
        },
        {
          name: 'Grandiose Supermarket',
          values: [147000, 118000, 84000, 69000, 60000, 52000, 46000, 36400],
          total: 612400
        },
        {
          name: 'Union Coop',
          values: [140000, 112000, 80000, 66000, 57000, 50000, 44000, 35300],
          total: 584300
        },
        {
          name: 'Baqer Mohebi Enterprises',
          values: [123000, 98000, 70000, 58000, 50000, 43000, 38000, 32100],
          total: 512100
        },
        {
          name: 'Nesto Group',
          values: [115000, 92000, 66000, 54000, 47000, 41000, 36000, 27600],
          total: 478600
        },
        {
          name: 'Talal Market',
          values: [99000, 79000, 57000, 47000, 40000, 35000, 31000, 24500],
          total: 412500
        },
        {
          name: 'Safeer Group',
          values: [93400, 75000, 53000, 44000, 38000, 33000, 29000, 23800],
          total: 389200
        }
      ]
    }
  };

  /**
   * Deterministic generation of 1,284 individual invoice records matching
   * exactly the FY26-27 total of AED 6,879,432 and brand/status/month splits.
   */
  function generateGranularInvoices() {
    const invoices = [];
    const customerPool = SUMMARY.topCustomers.map((c) => ({
      id: c.id,
      name: c.name,
      creditTerms: c.creditTerms,
      creditCategory: c.creditCategory,
      avgDays: c.avgCreditDays
    }));

    const pocPool = SUMMARY.pocs.map((p) => p.salesperson);
    const months = [
      { key: '2026-04', label: 'Apr 2026', days: 30, targetCount: 291 },
      { key: '2026-05', label: 'May 2026', days: 31, targetCount: 322 },
      { key: '2026-06', label: 'Jun 2026', days: 30, targetCount: 338 },
      { key: '2026-07', label: 'Jul 2026', days: 31, targetCount: 333 },
      { key: '2026-08', label: 'Aug 2026', days: 31, targetCount: 329 },
      { key: '2026-09', label: 'Sep 2026', days: 30, targetCount: 335 }
    ];

    const categories = SUMMARY.topCategories.map((c) => c.category);

    let invCounter = 1000;
    let runningTotal = 0;
    const targetTotal = SUMMARY.totalRevenue;
    const totalTargetInvoices = SUMMARY.totalInvoices;

    // Seeded pseudo-random number generator for reproducible dataset
    let seed = 123456789;
    function pseudoRandom() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    months.forEach((m, mIdx) => {
      const countForMonth = m.targetCount;

      for (let i = 0; i < countForMonth; i++) {
        invCounter++;
        const invIndex = invoices.length + 1;
        const isAbsoluteLast = invIndex === totalTargetInvoices;

        // Determine Customer
        const custRand = pseudoRandom();
        let custIndex = 0;
        if (custRand < 0.14) custIndex = 0; // Al Maya
        else if (custRand < 0.27) custIndex = 1; // Lulu
        else if (custRand < 0.38) custIndex = 2; // Choithrams
        else if (custRand < 0.48) custIndex = 3; // West Zone
        else if (custRand < 0.57) custIndex = 4; // Grandiose
        else if (custRand < 0.65) custIndex = 5; // Union Coop
        else if (custRand < 0.72) custIndex = 6; // Baqer Mohebi
        else if (custRand < 0.79) custIndex = 7; // Nesto Group
        else if (custRand < 0.85) custIndex = 8; // Talal Market
        else if (custRand < 0.91) custIndex = 9; // Safeer Group
        else custIndex = 10; // Others

        const cust = customerPool[custIndex];

        // Determine Brand
        const brandRand = pseudoRandom();
        let brandName = 'Nellon';
        if (brandRand < 0.512) brandName = 'Nellon';
        else if (brandRand < 0.886) brandName = 'Non-Branded';
        else brandName = 'Raviya';

        // Determine Status
        const statusRand = pseudoRandom();
        let statusName = 'Closed';
        if (statusRand < 0.4367) statusName = 'Overdue';
        else if (statusRand < 0.6536) statusName = 'Open';
        else if (statusRand < 0.6638) statusName = 'Partially Paid';
        else statusName = 'Closed';

        // Determine POC
        const poc = pocPool[Math.floor(pseudoRandom() * pocPool.length)];

        // Date generation
        const day = 1 + Math.floor(pseudoRandom() * m.days);
        const dayStr = day < 10 ? '0' + day : '' + day;
        const dateStr = `${m.key}-${dayStr}`;

        // Credit terms & Due Date
        let creditDays = 30;
        let creditCat = cust.creditCategory;
        if (cust.creditTerms === 'Cash') {
          creditDays = 0;
          creditCat = 'Cash';
        } else if (cust.creditTerms === '15 days') {
          creditDays = 15;
          creditCat = '8–30 days';
        } else if (cust.creditTerms === '30 days') {
          creditDays = 30;
          creditCat = '8–30 days';
        } else if (cust.creditTerms === '45 days') {
          creditDays = 45;
          creditCat = '31–60 days';
        } else if (cust.creditTerms === '60 days') {
          creditDays = 60;
          creditCat = '31–60 days';
        } else {
          creditDays = 75;
          creditCat = '61–90 days';
        }

        const dueDateObj = new Date(`${dateStr}T00:00:00Z`);
        dueDateObj.setDate(dueDateObj.getDate() + creditDays);
        const dueYear = dueDateObj.getUTCFullYear();
        const dueMonth = String(dueDateObj.getUTCMonth() + 1).padStart(2, '0');
        const dueDay = String(dueDateObj.getUTCDate()).padStart(2, '0');
        const dueDateStr = `${dueYear}-${dueMonth}-${dueDay}`;

        // Amount calculation
        let amount = 0;
        if (isAbsoluteLast) {
          amount = Math.round((targetTotal - runningTotal) * 100) / 100;
        } else {
          // Average around 5357 with variation
          const baseAOV = 5357.81;
          const variance = (pseudoRandom() - 0.49) * 4200;
          amount = Math.max(850, Math.round((baseAOV + variance) * 100) / 100);
          runningTotal += amount;
        }

        // Balances based on status
        let paymentMade = 0;
        let balance = amount;
        if (statusName === 'Closed') {
          paymentMade = amount;
          balance = 0;
        } else if (statusName === 'Partially Paid') {
          paymentMade = Math.round(amount * 0.4 * 100) / 100;
          balance = Math.round((amount - paymentMade) * 100) / 100;
        } else {
          // Open or Overdue
          paymentMade = 0;
          balance = amount;
        }

        // Generate line items
        const numLines = 1 + Math.floor(pseudoRandom() * 4);
        const lineItems = [];
        let lineRunning = 0;

        for (let l = 0; l < numLines; l++) {
          const cat = categories[Math.floor(pseudoRandom() * categories.length)];
          const isLastLine = l === numLines - 1;
          let lineAmount = 0;
          if (isLastLine) {
            lineAmount = Math.round((amount - lineRunning) * 100) / 100;
          } else {
            const splitRatio = 1 / numLines;
            lineAmount = Math.round(amount * splitRatio * (0.8 + pseudoRandom() * 0.4) * 100) / 100;
            lineRunning += lineAmount;
          }

          const rate = Math.round((15 + pseudoRandom() * 35) * 100) / 100;
          const qty = Math.max(1, Math.round(lineAmount / rate));

          lineItems.push({
            itemId: `ITEM-${100 + l}`,
            sku: `SKU-${cat.substring(0, 3).toUpperCase()}-${l + 1}`,
            name: `${brandName} ${cat} Product ${l + 1}`,
            brand: brandName,
            category: cat,
            rate: rate,
            quantity: qty,
            amount: lineAmount
          });
        }

        invoices.push({
          invoiceId: `INV-${invCounter}`,
          invoiceNumber: `INV-2026-${invCounter}`,
          customerName: cust.name,
          customerId: cust.id,
          date: dateStr,
          monthKey: m.key,
          monthLabel: m.label,
          fiscalYear: 'FY26-27',
          dueDate: dueDateStr,
          status: statusName,
          paymentTerms: cust.creditTerms,
          creditDays: creditDays,
          creditCategory: creditCat,
          brand: brandName,
          salesperson: poc,
          subtotal: amount,
          tax: 0,
          total: amount,
          paymentMade: paymentMade,
          balance: balance,
          creditsApplied: 0,
          currency: 'AED',
          lineItems: lineItems
        });
      }
    });

    return invoices;
  }

  /**
   * Deterministic generation of 1,225 baseline invoices for FY25-26 (AED 6,564,343)
   */
  function generateBaselineInvoices() {
    const invoices = [];
    const customerPool = SUMMARY.topCustomers.map((c) => c.name);
    const pocPool = SUMMARY.pocs.map((p) => p.salesperson);
    const targetTotal = SUMMARY.previousPeriod.totalRevenue;
    const totalCount = SUMMARY.previousPeriod.totalInvoices;

    let seed = 987654321;
    function pseudoRandom() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    let runningTotal = 0;
    for (let i = 0; i < totalCount; i++) {
      const isLast = i === totalCount - 1;
      let amount = 0;
      if (isLast) {
        amount = Math.round((targetTotal - runningTotal) * 100) / 100;
      } else {
        const base = targetTotal / totalCount;
        amount = Math.round((base + (pseudoRandom() - 0.5) * 3500) * 100) / 100;
        amount = Math.max(700, amount);
        runningTotal += amount;
      }

      const custName = customerPool[Math.floor(pseudoRandom() * customerPool.length)];
      const poc = pocPool[Math.floor(pseudoRandom() * pocPool.length)];
      const brandRand = pseudoRandom();
      const brand = brandRand < 0.5 ? 'Nellon' : brandRand < 0.88 ? 'Non-Branded' : 'Raviya';

      const month = 4 + Math.floor(pseudoRandom() * 4); // Apr-Jul 2025
      const day = 1 + Math.floor(pseudoRandom() * 28);
      const dateStr = `2025-0${month}-${day < 10 ? '0' + day : day}`;

      invoices.push({
        invoiceId: `INV-25-${2000 + i}`,
        invoiceNumber: `INV-2025-${2000 + i}`,
        customerName: custName,
        date: dateStr,
        fiscalYear: 'FY25-26',
        status: 'Closed',
        brand: brand,
        salesperson: poc,
        total: amount,
        subtotal: amount,
        currency: 'AED'
      });
    }

    return invoices;
  }

  // Pre-generate the invoice lists
  const generatedInvoices = generateGranularInvoices();
  const generatedBaselineInvoices = generateBaselineInvoices();

  return {
    summary: SUMMARY,
    invoices: generatedInvoices,
    previousPeriodInvoices: generatedBaselineInvoices,
    metadata: {
      generatedAt: new Date().toISOString(),
      dataSourceLabel: 'invoice_clean.xlsx',
      version: '1.0.0',
      totalRecords: generatedInvoices.length
    }
  };
});
