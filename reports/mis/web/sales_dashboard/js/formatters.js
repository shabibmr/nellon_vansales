/**
 * Koyson Sales Dashboard - Formatters Utility
 * Pure string & number formatting utilities for currency, percentage, numbers, and dates.
 * Compatible with Browser (window.Formatters) and Node.js (CommonJS/ESM).
 */

(function (root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.Formatters = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DEFAULT_EXCHANGE_RATE_INR = 22.8;

  /**
   * Format currency values strictly in AED.
   * @param {number} amount - The numeric monetary value in AED
   * @param {string} currency - Ignored or 'AED' (strictly AED)
   * @param {boolean} compact - Whether to abbreviate (e.g. 6.88M, 783.3K) (default true)
   * @returns {string} Formatted currency string in AED
   */
  function formatCurrency(amount, currency = 'AED', compact = true) {
    if (amount === null || amount === undefined || isNaN(amount)) {
      return 'AED 0';
    }

    const isNegative = amount < 0;
    const absVal = Math.abs(amount);

    let formatted = '';
    if (compact) {
      if (absVal >= 1e6) {
        formatted = (absVal / 1e6).toFixed(2) + 'M';
      } else if (absVal >= 1e3) {
        formatted = (absVal / 1e3).toFixed(1) + 'K';
      } else {
        formatted = Math.round(absVal).toLocaleString('en-US');
      }
    } else {
      formatted = absVal.toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
      });
    }

    return `${isNegative ? '-' : ''}AED ${formatted}`;
  }

  /**
   * Format a percentage value.
   * @param {number} val - e.g. 51.2 or 0.512
   * @param {number} decimals - Number of decimal places (default 1)
   * @param {boolean} isRawRatio - Set true if val is in 0..1 range
   * @returns {string} e.g. "51.2%"
   */
  function formatPercent(val, decimals = 1, isRawRatio = false) {
    if (val === null || val === undefined || isNaN(val)) {
      return '0.0%';
    }
    const num = isRawRatio ? val * 100 : val;
    return `${num.toFixed(decimals)}%`;
  }

  /**
   * Format integer/number with thousands separators.
   * @param {number} val - e.g. 1284
   * @param {number} decimals - Number of decimals (default 0)
   * @returns {string} e.g. "1,284"
   */
  function formatNumber(val, decimals = 0) {
    if (val === null || val === undefined || isNaN(val)) {
      return '0';
    }
    return Number(val).toLocaleString('en-US', {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals
    });
  }

  /**
   * Format compact numbers without currency symbol.
   * @param {number} val - e.g. 1284 => "1.3K", 1650400 => "1.65M"
   */
  function formatCompactNumber(val) {
    if (val === null || val === undefined || isNaN(val)) return '0';
    const absVal = Math.abs(val);
    const sign = val < 0 ? '-' : '';
    if (absVal >= 1e6) return sign + (absVal / 1e6).toFixed(2) + 'M';
    if (absVal >= 1e3) return sign + (absVal / 1e3).toFixed(1) + 'K';
    return sign + Math.round(absVal).toLocaleString('en-US');
  }

  /**
   * Format standard date string into business display format (e.g. "14 Jun 2026").
   * @param {string|Date} dateVal - Date string "YYYY-MM-DD" or Date object
   * @returns {string} e.g. "14 Jun 2026"
   */
  function formatDate(dateVal) {
    if (!dateVal) return '-';
    let d;
    if (dateVal instanceof Date) {
      d = dateVal;
    } else {
      // Parse YYYY-MM-DD safely
      const parts = String(dateVal).split('-');
      if (parts.length === 3) {
        d = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
      } else {
        d = new Date(dateVal);
      }
    }

    if (isNaN(d.getTime())) return String(dateVal);

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const day = d.getDate();
    const month = months[d.getMonth()];
    const year = d.getFullYear();

    return `${day} ${month} ${year}`;
  }

  /**
   * Format change / delta between current and previous values.
   * @param {number} current
   * @param {number} previous
   * @returns {{ text: string, percent: number, direction: 'up'|'down'|'neutral', isPositive: boolean }}
   */
  function formatChange(current, previous) {
    if (!previous || previous === 0) {
      return {
        text: '0.0%',
        percent: 0,
        direction: 'neutral',
        isPositive: true
      };
    }
    const diff = current - previous;
    const pct = (diff / previous) * 100;
    const sign = pct > 0 ? '+' : '';
    return {
      text: `${sign}${pct.toFixed(1)}%`,
      percent: Math.round(pct * 10) / 10,
      direction: pct > 0 ? 'up' : pct < 0 ? 'down' : 'neutral',
      isPositive: pct >= 0
    };
  }

  return {
    DEFAULT_EXCHANGE_RATE_INR,
    formatCurrency,
    formatPercent,
    formatNumber,
    formatCompactNumber,
    formatDate,
    formatChange
  };
});
