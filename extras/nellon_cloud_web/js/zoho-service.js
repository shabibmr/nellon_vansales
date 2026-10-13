/**
 * Koyson Sales Dashboard - Zoho Books Service Adapter
 * Interacts with Zoho Books Web Tab / Widget SDK (ZFWidget).
 * Strictly complies with security: NEVER exposes Zoho OAuth secrets;
 * routes all requests through the authorized ZFWidget client SDK proxy.
 * Compatible with Browser (window.ZohoService) and Node.js.
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.ZohoService = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  let initialized = false;
  let isAvailable = false;
  let organizationId = null;

  /**
   * Check if Zoho ZFWidget SDK is present in the global window context.
   */
  function isZohoAvailable() {
    return typeof window !== 'undefined' && typeof window.ZFWidget !== 'undefined';
  }

  /**
   * Initialize ZFWidget SDK and detect environment.
   * @returns {Promise<{ isZoho: boolean, organizationId: string|null }>}
   */
  function init() {
    return new Promise((resolve) => {
      if (!isZohoAvailable()) {
        isAvailable = false;
        initialized = true;
        resolve({ isZoho: false, organizationId: null });
        return;
      }

      try {
        window.ZFWidget.init(function () {
          initialized = true;
          isAvailable = true;

          // Attempt to get organization details from environment if available
          if (window.ZFWidget.getVariable) {
            window.ZFWidget.getVariable('organization_id')
              .then((res) => {
                organizationId = res && res.value ? res.value : null;
                resolve({ isZoho: true, organizationId });
              })
              .catch(() => {
                resolve({ isZoho: true, organizationId: null });
              });
          } else {
            resolve({ isZoho: true, organizationId: null });
          }
        });
      } catch (err) {
        console.warn('ZFWidget initialization encountered error:', err);
        initialized = true;
        isAvailable = false;
        resolve({ isZoho: false, organizationId: null });
      }
    });
  }

  /**
   * Fetch invoices from Zoho Books via the ZFWidget secure client proxy.
   * Handles multi-page pagination with optional progress callback.
   * @param {Object} queryParams - Query parameters (date ranges, status, etc.)
   * @param {Function} onProgress - Progress callback (receivedCount, totalCount)
   * @returns {Promise<Array<Object>>} Raw Zoho invoice list
   */
  async function fetchInvoices(queryParams = {}, onProgress = null) {
    if (!isAvailable) {
      throw new Error('Zoho Books ZFWidget environment is not available in this context.');
    }

    const allInvoices = [];
    let page = 1;
    let hasMorePages = true;
    const perPage = 200; // Maximum allowed per Zoho Books API page

    while (hasMorePages) {
      const query = {
        page: page,
        per_page: perPage,
        sort_column: 'date',
        sort_order: 'D',
        ...queryParams
      };

      if (organizationId) {
        query.organization_id = organizationId;
      }

      try {
        const response = await makeZFRequest('/books/v3/invoices', 'GET', query);
        const data = typeof response === 'string' ? JSON.parse(response) : response;

        if (data && data.code === 0 && Array.isArray(data.invoices)) {
          allInvoices.push(...data.invoices);
          const pageContext = data.page_context || {};
          hasMorePages = pageContext.has_more_page === true;
          page++;

          if (typeof onProgress === 'function') {
            onProgress(allInvoices.length, pageContext.total || allInvoices.length);
          }
        } else {
          hasMorePages = false;
        }
      } catch (err) {
        console.error(`Error fetching invoices page ${page}:`, err);
        throw err;
      }
    }

    return allInvoices;
  }

  /**
   * Fetch detailed invoice information including line items.
   * @param {string} invoiceId
   * @returns {Promise<Object>}
   */
  async function fetchInvoiceDetails(invoiceId) {
    if (!isAvailable) {
      throw new Error('Zoho Books ZFWidget environment is not available.');
    }

    const query = organizationId ? { organization_id: organizationId } : {};
    const res = await makeZFRequest(`/books/v3/invoices/${invoiceId}`, 'GET', query);
    const parsed = typeof res === 'string' ? JSON.parse(res) : res;
    return parsed && parsed.invoice ? parsed.invoice : null;
  }

  /**
   * Fetch live or organization exchange rate for AED -> targetCurrency (default 'INR').
   * 1. Checks Zoho Books Currencies API (/books/v3/settings/currencies) if running in Zoho.
   * 2. Falls back to free public forex API (open.er-api.com) with 1-hour cache.
   * 3. Falls back to static standard rate (22.8) if offline.
   * @param {string} targetCurrency
   * @returns {Promise<{ rate: number, source: string, timestamp: number }>}
   */
  async function fetchExchangeRate(targetCurrency = 'INR') {
    const defaultRate = 22.8;

    // 1. If running inside Zoho Books, try organization currencies API
    if (isAvailable) {
      try {
        const query = organizationId ? { organization_id: organizationId } : {};
        const response = await makeZFRequest('/books/v3/settings/currencies', 'GET', query);
        const parsed = typeof response === 'string' ? JSON.parse(response) : response;
        const currencies = (parsed && parsed.currencies) || (parsed && parsed.data && parsed.data.currencies);
        if (Array.isArray(currencies)) {
          const target = currencies.find(c => c.currency_code === targetCurrency);
          if (target && target.exchange_rate) {
            return {
              rate: parseFloat(target.exchange_rate),
              source: 'Zoho Books Currencies',
              timestamp: Date.now()
            };
          }
        }
      } catch (err) {
        console.warn('Could not fetch exchange rate from Zoho Books settings:', err);
      }
    }

    // 2. Check localStorage cache for live public rate (valid for 1 hour)
    const cacheKey = `koyson_fx_rate_AED_${targetCurrency}`;
    try {
      const cached = localStorage.getItem(cacheKey);
      if (cached) {
        const parsedCache = JSON.parse(cached);
        if (Date.now() - parsedCache.timestamp < 3600000 && parsedCache.rate > 0) {
          return parsedCache;
        }
      }
    } catch (e) {}

    // 3. Fetch live rate from public open.er-api.com (free, keyless, CORS enabled)
    try {
      const res = await fetch('https://open.er-api.com/v6/latest/AED');
      if (res.ok) {
        const data = await res.json();
        if (data && data.rates && data.rates[targetCurrency]) {
          const liveRate = parseFloat(data.rates[targetCurrency]);
          const result = {
            rate: liveRate,
            source: 'Live Market (Open Exchange)',
            timestamp: Date.now()
          };
          try {
            localStorage.setItem(cacheKey, JSON.stringify(result));
          } catch (e) {}
          return result;
        }
      }
    } catch (err) {
      console.warn('Could not fetch live exchange rate from forex API:', err);
    }

    // 4. Default fallback
    return {
      rate: defaultRate,
      source: 'Standard Fallback',
      timestamp: Date.now()
    };
  }

  /**
   * Wrapper for ZFWidget.request promisified.
   */
  function makeZFRequest(url, method = 'GET', urlQuery = {}) {
    return new Promise((resolve, reject) => {
      if (!isZohoAvailable()) {
        reject(new Error('ZFWidget not found'));
        return;
      }

      window.ZFWidget.request({
        url: url,
        method: method,
        url_query: urlQuery
      })
        .then((response) => {
          resolve(response);
        })
        .catch((error) => {
          reject(error);
        });
    });
  }

  return {
    isZohoAvailable,
    init,
    fetchInvoices,
    fetchInvoiceDetails,
    fetchExchangeRate,
    getOrganizationId: () => organizationId
  };
});
