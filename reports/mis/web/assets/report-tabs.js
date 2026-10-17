/* Report tab bar shared by the Reports and Category Master pages, so both list the same tabs. */
(() => {
  "use strict";

  const TABS = [
    { id: "exec", label: "Executive Summary", kind: "financials", statement: "Executive Summary", tree: 1 },
    { id: "pl", label: "Profit & Loss", kind: "financials", statement: "PL", tree: 2 },
    { id: "bs", label: "Balance Sheet", kind: "financials", statement: "BS" },
    { id: "tb", label: "Trial Balance", kind: "financials" },
    { id: "margin", label: "Margin", kind: "margin", api: "api/margin", pivot: true },
    { id: "mline", label: "Margin by Line", kind: "margin", detail: "line" },
    { id: "minv", label: "Margin by Invoice", kind: "margin", detail: "invoice" },
    { id: "purchases", label: "Purchases", kind: "purchases", api: "api/purchases", pivot: true },
  ];

  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const current = (on) => (on ? ' aria-current="page"' : "");

  window.MISTabs = {
    TABS,
    // `active` is a report tab id, or "categories" on the Category Master page.
    render(nav, active) {
      nav.innerHTML = TABS.map((t) =>
        `<a href="./?tab=${t.id}" data-tab="${t.id}"${current(t.id === active)}>${esc(t.label)}</a>`)
        .join("") + `<a href="categories"${current(active === "categories")}>Categories</a>`;
    },
  };
})();
