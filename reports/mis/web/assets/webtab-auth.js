/* Zoho Books web-tab auth: Zoho postMessages a JWT to this iframe; every API call carries it as a Bearer header. */
(() => {
  "use strict";

  const ZOHO_ORIGIN = /^https:\/\/([a-z0-9-]+\.)*zoho\.(com|ae|eu|in|sa|jp|ca|uk|com\.au|com\.cn)$/;
  const WAIT_MS = 6000;
  let token = null, expMs = 0, waiters = [], refreshTimer = null;

  const claims = (jwt) => {
    try { return JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))); } catch { return {}; }
  };
  const requestRefresh = () => window.parent.postMessage({ type: "ZOHO_WEBTAB_REQUEST_TOKEN_REFRESH" }, "*");

  window.addEventListener("message", (e) => {
    if (e.source !== window.parent || !ZOHO_ORIGIN.test(e.origin)) return;
    if (!e.data || e.data.type !== "ZOHO_WEBTAB_AUTH_TOKENS") return;
    token = e.data.jwt_token || null;
    clearTimeout(refreshTimer);
    if (!token) { expMs = 0; return; }
    expMs = (claims(token).exp || 0) * 1000;
    // ask for a fresh token a minute before this one expires
    refreshTimer = setTimeout(requestRefresh, Math.max(5000, expMs - Date.now() - 60000));
    waiters.splice(0).forEach((w) => w(token));
  });

  function ready() {
    if (token && Date.now() < expMs) return Promise.resolve(token);
    return new Promise((resolve, reject) => {
      waiters.push(resolve);
      if (window.parent !== window) requestRefresh();
      setTimeout(() => reject(new Error("Open this report from the Zoho Books web tab.")), WAIT_MS);
    });
  }

  // Where "api/..." calls go. The Python server answers api/ itself; a static copy (deploy/test-web) sets
  // <meta name="mis-api-base" content="api.php/"> so a PHP shim forwards them instead.
  const API_BASE = document.querySelector('meta[name="mis-api-base"]')?.content || "api/";
  const url = (path) => (path.startsWith("api/") ? API_BASE + path.slice(4) : path);

  window.MISAuth = {
    url,
    async fetch(path, opts = {}) {
      // Outside an iframe no token will ever arrive; let the server decide (401 unless auth is disabled).
      if (window.parent === window && !token) return fetch(url(path), opts);
      const jwt = await ready();
      return fetch(url(path), { ...opts, headers: { ...(opts.headers || {}), Authorization: `Bearer ${jwt}` } });
    },
  };
})();
