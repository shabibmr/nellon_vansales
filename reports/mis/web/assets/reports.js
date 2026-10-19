/* Reports page: margin / purchases (and stored financials runs) come from MariaDB through the local
   server API; with live financials on, Executive Summary, P&L, BS and TB come from Zoho through the
   server's cache (reports/live_financials.py). */
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const icon = (name, cls = "") =>
    `<svg class="icon ${cls}" aria-hidden="true"><use href="assets/icons.svg#${name}"/></svg>`;

  const NUM = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

  const { TABS } = window.MISTabs;  // assets/report-tabs.js

  // Pivot tabs (margin, purchases): rows = chosen dimension, columns = months + Total.
  const MARGIN_MEASURES = [["net_sales", "Net sales"], ["cost", "Cost"], ["gross_margin", "Margin"], ["gm_pct", "GM %"]];
  const PIVOTS = {
    margin: {
      dims: [["item", "Item"], ["customer", "Customer"], ["salesperson", "Salesperson"], ["van", "Van"]],
      measures: [["net_sales", "Net sales"], ["cost", "Cost"], ["gross_margin", "Gross margin"],
        ["gm_pct", "GM %"], ["base_quantity", "Base quantity"]],
    },
    purchases: {
      dims: [["vendor", "Vendor"], ["item", "Item"], ["kind", "Bills / POs"]],
      measures: [["amount", "Amount"], ["quantity", "Quantity"], ["documents", "Documents"]],
    },
  };

  const qs = new URLSearchParams(location.search);
  // Margin and purchases read the dated tables for any range; financials are live from Zoho when the
  // server allows it (`/api/config`), else they read one stored run.
  const DATASET = { margin: "sales", purchases: "purchases" };
  const COMMAND = { margin: "margin", purchases: "purchases" };
  const state = {
    tab: TABS.some((t) => t.id === qs.get("tab")) ? qs.get("tab") : "exec",
    runs: { financials: [] },
    selected: { financials: null },
    coverage: { sales: null, purchases: null },  // /api/coverage per dataset
    pivot: { margin: { dim: "item", measure: "net_sales" }, purchases: { dim: "vendor", measure: "amount" } },
    query: "",           // header search; mirrored into the per-view filters below
    tbFilter: "",
    detailFilter: "",
    detailData: null,
    stmtData: null,      // last plain statement / pivot drawn, so a search can redraw without a fetch
    pivotData: null,
    org: null,
    live: false,         // server serves live financials
    fiscalStart: null,   // "2000-MM" from /api/config: quarters / years follow it
    seq: 0,              // newest live request; older answers are dropped
    tbData: null,
    labels: {},  // column key → heading for the date filter's columns (periods, Total)
    // Expandable statements: `tree` on a tab is its default outline level.
    tree: { nodes: null, cols: [], open: new Set(), q: "", sort: "statement", reveal: null },
  };

  // ---------------------------------------------------------------- helpers

  const tab = () => TABS.find((t) => t.id === state.tab) || TABS[0];
  const isLive = (t) => state.live && t.kind === "financials";
  const fiscalStart = () => state.fiscalStart || (state.runs.financials[0] || {}).fiscal_year_start;
  const runOf = (kind) => state.runs[kind].find((r) => r.id === state.selected[kind]);

  const colLabel = (c) => {
    if (state.labels[c]) return state.labels[c];
    const m = /^(\d{4})-(\d{2})$/.exec(c);
    return m ? `${MON[Number(m[2]) - 1]}-${m[1].slice(2)}` : c;
  };

  const fmt = (v, pct) => {
    if (v === "" || v === null || v === undefined) return "";
    const n = Number(v);
    if (pct) return n < 0 ? `(${(-n * 100).toFixed(1)}%)` : `${(n * 100).toFixed(1)}%`;  // accounting: negatives in brackets
    if (Math.abs(n) < 0.005) return "-";
    return n < 0 ? `(${NUM.format(-n)})` : NUM.format(n);
  };

  const numCell = (v, { pct = false, total = false } = {}) =>
    `<td class="n${Number(v) < -0.004 ? " neg" : ""}${total ? " tot" : ""}">${fmt(v, pct)}</td>`;

  const headRow = (first, cols, totalCol) =>
    `<thead><tr><th scope="col">${esc(first)}</th>${cols.map((c) =>
      `<th scope="col" class="${c === totalCol ? "tot" : ""}">${esc(colLabel(c))}</th>`).join("")}</tr></thead>`;

  const view = (html) => { $("out").innerHTML = html; };
  const skeleton = (note = "") => view((note ? `<p class="loading-note">${esc(note)}</p>` : "") +
    `<div class="skeleton" aria-label="Loading report">${"<div></div>".repeat(9)}</div>`);
  const stateView = (iconName, title, body, cls = "") =>
    view(`<div class="state ${cls}">${icon(iconName, "xl")}<h2>${esc(title)}</h2><p>${body}</p></div>`);

  function snackbar(msg, isErr = false) {
    const s = $("snackbar");
    s.textContent = msg;
    s.className = `snackbar show${isErr ? " err" : ""}`;
    clearTimeout(snackbar.timer);
    snackbar.timer = setTimeout(() => (s.className = "snackbar"), isErr ? 6000 : 3500);
  }

  async function api(path) {
    const res = await MISAuth.fetch(path, { cache: "no-store" });
    const body = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    return body;
  }

  // A dated tab's link carries its range, so it reproduces the view.
  function syncUrl() {
    const p = new URLSearchParams({ tab: state.tab });
    const r = (DATASET[tab().kind] || isLive(tab())) && DF.isoRange();
    if (r) { p.set("from", r.from); p.set("to", r.to); p.set("by", DF.split()); }
    history.replaceState(null, "", `?${p}`);
  }

  // ---------------------------------------------------------------- chrome

  function renderTabs() {
    MISTabs.render($("tabs"), state.tab);
  }

  function pickRun() {
    const kind = tab().kind;
    const runs = state.runs[kind];
    if (!runs.length) return false;
    if (!runs.some((r) => r.id === state.selected[kind])) state.selected[kind] = runs[0].id;
    return true;
  }

  function renderExport() {
    // Live: the workbook covers the date filter's columns (its href is set on click).
    // Else it covers the selected financials run (margin / purchases: the run matching its period).
    const btn = $("exportBtn");
    const id = state.selected.financials || (state.runs.financials[0] || {}).id;
    if (state.live) {
      btn.removeAttribute("aria-disabled");
      btn.title = "Executive Summary, PL, BS, Trial Balance (live from Zoho), Margin, Purchases and Category Master for the selected dates";
    } else if (id) {
      btn.href = `api/export.xlsx?run_id=${id}`;
      btn.removeAttribute("aria-disabled");
      btn.title = `Run #${id}: Executive Summary, PL, BS, Trial Balance, Margin, Purchases and Category Master`;
    } else {
      btn.href = "api/export.xlsx";
      btn.setAttribute("aria-disabled", "true");
      btn.title = "Save a financials run first";
    }
  }

  // The header search box: what it searches on this tab.
  const searchHint = (t) => (t.id === "tb" ? "Search accounts, codes or categories"
    : t.detail ? "Search invoices, customers or items"
      : t.pivot ? "Search rows" : "Search lines");

  // Row 2 of the header holds the tab's own controls (pivot rows / measure); search lives in row 1.
  function renderTools() {
    const t = tab();
    $("q").placeholder = searchHint(t);
    let html = "";
    if (t.pivot) {
      const cfg = PIVOTS[t.id], cur = state.pivot[t.id];
      const opts = (list, sel) => list.map(([v, l]) =>
        `<option value="${v}"${v === sel ? " selected" : ""}>${esc(l)}</option>`).join("");
      html = `<label class="mh-field"><span>Rows</span><select class="input" id="pvDim">${opts(cfg.dims, cur.dim)}</select></label>
        ${t.id === "margin" ? "" : `<label class="mh-field"><span>Measure</span><select class="input" id="pvMeasure">${opts(cfg.measures, cur.measure)}</select></label>`}`;
    }
    $("toolbar").innerHTML = html;
    if ($("pvDim")) {
      $("pvDim").onchange = (e) => { state.pivot[t.id].dim = e.target.value; load(); };
      if ($("pvMeasure")) $("pvMeasure").onchange = (e) => { state.pivot[t.id].measure = e.target.value; load(); };
    }
  }

  // Redraw the current view from the data already loaded (after the search changes).
  function redraw() {
    const t = tab();
    if (t.id === "tb") return renderTb(state.tbData);
    if (t.detail) return renderDetail(state.detailData, t);
    if (t.pivot) return state.pivotData && renderPivot(state.pivotData, t);
    if (state.tree.nodes) return renderTree();
    if (state.stmtData) return renderStatement(state.stmtData);
  }

  // "2026-04-01" → "Apr-26"; the period reads "Apr-26 – Sep-26", or one month when both ends fall in it.
  const monthYear = (iso) => {
    const m = /^(\d{4})-(\d{2})/.exec(iso || "");
    return m ? `${MON[Number(m[2]) - 1]}-${m[1].slice(2)}` : "";
  };
  const periodLabel = (from, to) => {
    const a = monthYear(from), b = monthYear(to);
    return !a || a === b ? a || b : `${a} – ${b}`;
  };

  function setHead(run, title) {
    $("reportTitle").textContent = title;
    $("period").textContent = run ? periodLabel(run.from_date, run.to_date) : "";
    const ccy = (state.org && state.org.currency_code) || (run && run.currency_code) || "";
    $("ccy").textContent = ccy;
    $("ccy").hidden = !ccy;
    document.title = `${title} · ${(state.org && state.org.name) || "MIS"}`;
  }

  // ---------------------------------------------------------------- reports

  function renderStatement(data) {
    state.stmtData = data;
    const cols = data.columns;
    if (!data.lines.length) {
      stateView("database", "Nothing in this statement", `This run has no ${esc(data.statement)} lines.`);
      return;
    }
    const q = state.query.trim().toLowerCase();
    const lines = q ? data.lines.filter((ln) => ln.kind !== "title" && String(ln.label).toLowerCase().includes(q)) : data.lines;
    if (!lines.length) {
      stateView("search", "Nothing matches", "Try a different line name.");
      return;
    }
    const body = lines.map((ln) => {
      if (ln.kind === "title") {
        return `<tr class="title"><td colspan="${cols.length + 1}">${esc(ln.label)}</td></tr>`;
      }
      let cls = ln.kind;
      if (ln.kind === "check") {
        cls += Object.values(ln.values).every((v) => Math.abs(v) < 0.015) ? " ok" : " bad";
      }
      return `<tr class="${cls}"><td>${esc(ln.label)}</td>` +
        cols.map((c) => numCell(ln.values[c] ?? 0, { pct: ln.kind === "pct", total: c === "Total" })).join("") +
        `</tr>`;
    }).join("");
    view(`<table class="data">${headRow("Particulars", cols, "Total")}<tbody>${body}</tbody></table>`);
  }

  // Margin text cells: max 50 chars, longer values cut with "…" (full text in the tooltip).
  const TXT_MAX = 50;
  const txt = (v, extra = "") => {
    const t = String(v ?? "");
    const cut = t.length > TXT_MAX ? `${t.slice(0, TXT_MAX - 1)}…` : t;
    return `<td class="txt"${t.length > TXT_MAX ? ` title="${esc(t)}"` : ""}>${esc(cut)}${extra}</td>`;
  };

  // ---------------------------------------------------------------- expandable statements

  // Each node gets a stable key (its label path), its depth and its parent.
  function prepTree(nodes, parent = null, depth = 0, byKey = new Map()) {
    for (const n of nodes) {
      n.children = n.children || [];
      n.parent = parent;
      n.depth = depth;
      n.key = parent ? `${parent.key} › ${n.label}` : n.label;
      byKey.set(n.key, n);
      prepTree(n.children, n, depth + 1, byKey);
    }
    state.tree.byKey = byKey;
    return nodes;
  }

  const parentNodes = (nodes, out = []) => {
    for (const n of nodes) if (n.children.length) { out.push(n); parentNodes(n.children, out); }
    return out;
  };
  // Outline levels: 1 = top rows only, each step opens one more level of children.
  const levelCount = (nodes) =>
    1 + nodes.reduce((m, n) => Math.max(m, n.children.length ? levelCount(n.children) : 0), 0);
  const nodeTotal = (n) => Number(n.values.Total ?? 0);

  // Open rows live in this browser only, per tab; a blocked storage just means the default level.
  const treeStore = () => `mis.tree.${state.tab}`;
  function saveOpen() {
    try { localStorage.setItem(treeStore(), JSON.stringify([...state.tree.open])); } catch { /* storage blocked */ }
  }
  function loadOpen() {
    try {
      const v = JSON.parse(localStorage.getItem(treeStore()) || "null");
      return Array.isArray(v) ? new Set(v) : null;
    } catch { return null; }
  }

  function setLevel(level, { save = true } = {}) {
    state.tree.open = new Set(parentNodes(state.tree.nodes).filter((n) => n.depth < level - 1).map((n) => n.key));
    state.tree.reveal = null;
    if (save) saveOpen();
    renderTree();
  }

  function currentLevel() {
    const ps = parentNodes(state.tree.nodes);
    for (let l = 1; l <= levelCount(state.tree.nodes); l++) {
      if (ps.every((n) => state.tree.open.has(n.key) === n.depth < l - 1)) return l;
    }
    return 0;
  }

  // → true when the row changed state.
  function toggle(key, want) {
    const open = state.tree.open;
    const next = want ?? !open.has(key);
    if (next === open.has(key)) return false;
    if (next) open.add(key); else open.delete(key);
    state.tree.reveal = next ? key : null;
    saveOpen();
    renderTree();
    return true;
  }

  const focusTwisty = (key) =>
    $("out").querySelector(`tr[data-key="${CSS.escape(key)}"] .twisty`)?.focus();

  const highlight = (text, q) => {
    const s = String(text ?? "");
    const i = q ? s.toLowerCase().indexOf(q) : -1;
    return i < 0 ? esc(s)
      : `${esc(s.slice(0, i))}<mark>${esc(s.slice(i, i + q.length))}</mark>${esc(s.slice(i + q.length))}`;
  };

  function showTree(data, t) {
    const tr = state.tree;
    tr.nodes = prepTree(data.tree);
    tr.cols = data.columns;
    tr.reveal = null;
    const saved = loadOpen();
    if (!saved) return setLevel(t.tree, { save: false });
    tr.open = saved;
    renderTree();
  }

  function renderTree() {
    const { nodes, cols, open, sort, reveal } = state.tree;
    if (!nodes) return;
    const q = state.tree.q.trim().toLowerCase();

    // With a search, a row shows when it, an ancestor or a descendant matches; ancestors of a match open.
    const mark = (n, underHit) => {
      n.hit = !!q && (n.label.toLowerCase().includes(q) || String(n.meta || "").toLowerCase().includes(q));
      n.under = underHit;
      n.holds = false;
      for (const c of n.children) n.holds = mark(c, underHit || n.hit) || n.holds;
      return n.hit || n.holds;
    };
    const found = nodes.map((n) => mark(n, false)).some(Boolean);

    if (q && !found) {
      stateView("search", "Nothing matches", "Try a different category, account name or code.");
      return;
    }

    const order = (list) => sort === "size" && list[0]?.depth > 0
      ? [...list].sort((a, b) => Math.abs(nodeTotal(b)) - Math.abs(nodeTotal(a))) : list;

    let seq = 0;
    const row = (n, { isOpen = false, kids = false, revealing = false, dim = false } = {}) => {
      const p = n.parent;
      const cls = [n.kind, `d${n.depth}`, kids && "parent", isOpen && "open", revealing && "reveal", dim && "dim",
        n.kind === "check" && (Object.values(n.values).every((v) => Math.abs(v) < 0.015) ? "ok" : "bad")];
      const guides = Array.from({ length: n.depth }, (_, g) => `<span class="guide" style="--g:${g}"></span>`).join("");
      const twisty = kids
        ? `<button type="button" class="twisty" aria-expanded="${isOpen}" ` +
          `aria-label="${isOpen ? "Collapse" : "Expand"} ${esc(n.label)}">${icon("chevron_right")}</button>`
        : `<span class="twisty-sp"></span>`;
      // Share of the parent's Total; red when the row pulls against its parent (e.g. a refund inside revenue).
      let share = "";
      if (p && Math.abs(nodeTotal(p)) >= 0.005 && Math.abs(nodeTotal(n)) >= 0.005) {
        const r = nodeTotal(n) / nodeTotal(p);
        share = `<span class="share${r < 0 ? " contra" : ""}" title="${(r * 100).toFixed(1)}% of ${esc(p.label)}">` +
          `<i style="--share:${Math.min(1, Math.abs(r)).toFixed(3)}"></i><b>${r < 0 ? `(${Math.round(-r * 100)}%)` : `${Math.round(r * 100)}%`}</b></span>`;
      }
      const label = `<td class="tl" style="--depth:${n.depth}">${guides}<span class="tl-in">${twisty}` +
        `<span class="lbl">${highlight(n.label, q)}</span>` +
        (n.meta ? `<span class="code">${highlight(n.meta, q)}</span>` : "") +
        (kids && !isOpen ? `<span class="kids" title="${n.children.length} rows inside">${n.children.length}</span>` : "") +
        `${share}</span></td>`;
      return `<tr class="${cls.filter(Boolean).join(" ")}"${kids ? ` data-key="${esc(n.key)}"` : ""}` +
        `${revealing ? ` style="--i:${seq++}"` : ""}>${label}` +
        cols.map((c) => numCell(n.values[c] ?? 0, { pct: n.kind === "pct", total: c === "Total" })).join("") + `</tr>`;
    };

    let body = "";
    const walk = (list, revealing) => {
      for (const n of order(list)) {
        const kids = n.children.length > 0;
        if (q && !n.hit && !n.holds && !n.under) {
          if (n.depth === 0 && !kids) body += row(n, { dim: true });  // result lines stay for context
          continue;
        }
        const isOpen = kids && (open.has(n.key) || (!!q && n.holds));
        body += row(n, { isOpen, kids, revealing });
        if (isOpen) walk(n.children, revealing || n.key === reveal);
      }
    };
    walk(nodes, false);
    state.tree.reveal = null;
    view(`<table class="data tree">${headRow("Particulars", cols, "Total")}<tbody>${body}</tbody></table>`);
  }

  function renderPivot(all, t) {
    state.pivotData = all;
    if (!all.rows.length) {
      stateView("database", "Nothing in this period", "No lines were loaded for these dates.");
      return;
    }
    // The search narrows the rows; the Total row stays the total of every row.
    const q = state.query.trim().toLowerCase();
    const data = q ? { ...all, rows: all.rows.filter((r) => String(r.label).toLowerCase().includes(q)) } : all;
    if (!data.rows.length) {
      stateView("search", "Nothing matches", "Try a different name.");
      return;
    }
    if (data.multi) return renderMarginPivot(data, t);
    const pct = data.measure === "gm_pct";
    const cols = data.columns;
    const body = data.rows.map((r) =>
      `<tr>${t.kind === "margin" ? txt(r.label, r.flagged ? `<span class="tag review">${r.flagged} flagged</span>` : "")
        : `<td>${esc(r.label)}${r.flagged ? `<span class="tag review">${r.flagged} flagged</span>` : ""}</td>`}` +
      cols.map((c) => numCell(r.values[c] ?? 0, { pct, total: c === "Total" })).join("") + `</tr>`).join("");
    const foot = `<tr class="total"><td>${q ? "Total of all rows" : "Total"}</td>` +
      cols.map((c) => numCell(data.total[c] ?? 0, { pct, total: c === "Total" })).join("") + `</tr>`;
    const dimLabel = PIVOTS[t.id].dims.find(([v]) => v === data.dimension)?.[1] || "Rows";
    view(`<table class="data">${headRow(dimLabel, cols, "Total")}<tbody>${body}</tbody><tfoot>${foot}</tfoot></table>`);
  }

  function renderMarginPivot(data, t) {
    const cols = data.columns, M = MARGIN_MEASURES;
    const dimLabel = PIVOTS[t.id].dims.find(([v]) => v === data.dimension)?.[1] || "Rows";
    const cells = (src, c) => M.map(([m]) => numCell(src[m][c] ?? 0, { pct: m === "gm_pct", total: c === "Total" })).join("");
    const head = `<thead><tr><th scope="col" rowspan="2">${esc(dimLabel)}</th>${cols.map((c) =>
      `<th scope="colgroup" colspan="${M.length}" class="grp${c === "Total" ? " tot" : ""}">${esc(colLabel(c))}</th>`).join("")}</tr>` +
      `<tr>${cols.map((c) => M.map(([, l]) => `<th scope="col" class="n${c === "Total" ? " tot" : ""}">${l}</th>`).join("")).join("")}</tr></thead>`;
    const body = data.rows.map((r) =>
      `<tr>${txt(r.label, r.flagged ? `<span class="tag review">${r.flagged} flagged</span>` : "")}` +
      cols.map((c) => cells(r.m, c)).join("") + `</tr>`).join("");
    const foot = `<tr class="total"><td>${state.query.trim() ? "Total of all rows" : "Total"}</td>${cols.map((c) => cells(data.mtotal, c)).join("")}</tr>`;
    view(`<table class="data">${head}<tbody>${body}</tbody><tfoot>${foot}</tfoot></table>`);
  }

  function renderDetail(data, t) {
    if (!data) return;
    const q = state.detailFilter.trim().toLowerCase();
    const rows = data.rows.filter((r) => !q || [r.invoice_number, r.customer_name, r.item_name, r.salesperson_name]
      .some((v) => String(v ?? "").toLowerCase().includes(q)));
    if (!rows.length) {
      stateView("search", "Nothing matches", "Try a different invoice number, customer or item.");
      return;
    }
    const byLine = t.detail === "line";
    const th = (l, n, c) => `<th scope="col"${n ? ' class="n"' : c ? ` class="${c}"` : ""}>${l}</th>`;
    const head = byLine
      ? [th("Date", 0, "date"), th("Invoice"), th("Customer"), th("Item"), th("Unit"), th("Qty", 1), th("Rate", 1),
        th("Net sales", 1), th("Cost", 1), th("Margin", 1), th("GM %", 1)]
      : [th("Date", 0, "date"), th("Invoice"), th("Customer"), th("Salesperson"), th("Lines", 1),
        th("Net sales", 1), th("Cost", 1), th("Margin", 1), th("GM %", 1)];
    const sum = (k) => rows.reduce((s, r) => s + r[k], 0);
    const tn = sum("net_sales"), tc = sum("cost"), tm = sum("gross_margin");
    const flag = (r) => (byLine ? r.flag : r.flagged)
      ? `<span class="tag review">${byLine ? esc(r.flag) : `${r.flagged} flagged`}</span>` : "";
    const body = rows.map((r) => byLine
      ? `<tr><td class="date">${esc(r.date)}</td>${txt(r.invoice_number)}${txt(r.customer_name)}` +
        `${txt(r.item_name, flag(r))}${txt(r.unit)}${numCell(r.quantity)}${numCell(r.rate)}` +
        `${numCell(r.net_sales)}${numCell(r.cost)}${numCell(r.gross_margin)}${numCell(r.gm_pct, { pct: true })}</tr>`
      : `<tr><td class="date">${esc(r.date)}</td>${txt(r.invoice_number, flag(r))}${txt(r.customer_name)}` +
        `${txt(r.salesperson_name)}<td class="n">${r.line_count}</td>${numCell(r.net_sales)}${numCell(r.cost)}` +
        `${numCell(r.gross_margin)}${numCell(r.gm_pct, { pct: true })}</tr>`).join("");
    const span = byLine ? 7 : 4;
    const foot = `<tr class="total"><td colspan="${span}">Total${q ? " of filtered rows" : ""}</td>` +
      (byLine ? "" : `<td class="n">${rows.reduce((s, r) => s + r.line_count, 0)}</td>`) +
      `${numCell(tn)}${numCell(tc)}${numCell(tm)}${numCell(tn ? tm / tn : 0, { pct: true })}</tr>`;
    view(`<table class="data"><thead><tr>${head.join("")}</tr></thead><tbody>${body}</tbody><tfoot>${foot}</tfoot></table>`);
  }

  function renderTb(data) {
    if (!data) return;
    const months = data.months;
    const keys = ["opening", ...months, "closing"];
    const labels = ["Opening", ...months, "Closing"];
    const q = state.tbFilter.trim().toLowerCase();
    const rows = data.rows.filter((r) => !q || [r.account_name, r.account_code, r.category, r.sub_category, r.pl_bs]
      .some((v) => String(v ?? "").toLowerCase().includes(q)));
    if (!rows.length) {
      stateView("search", "No accounts match", "Try a different account name, code or category.");
      return;
    }

    const groups = new Map();
    for (const r of rows) {
      const k = `${r.pl_bs}|${r.category || "Uncategorised"}`;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(r);
    }
    const sum = (list, k) => list.reduce((s, r) => s + (Number(r[k]) || 0), 0);
    const cells = (src) => keys.map((k) => numCell(src[k], { total: k === "closing" })).join("");

    let body = "";
    for (const [k, list] of groups) {
      const [plbs, cat] = k.split("|");
      const sub = Object.fromEntries(keys.map((key) => [key, sum(list, key)]));
      body += `<tr class="category"><td>${esc(cat)}<span class="tag">${plbs}</span></td>${cells(sub)}</tr>`;
      for (const r of list) {
        body += `<tr class="sub"><td>${esc(r.account_name)}<span class="meta">${esc(r.account_code)}` +
          `${r.sub_category ? ` · ${esc(r.sub_category)}` : ""}</span></td>${cells(r)}</tr>`;
      }
    }
    const totals = Object.fromEntries(keys.map((key) => [key, sum(rows, key)]));
    const foot = `<tr class="total"><td>Total${q ? " of filtered accounts" : ""}</td>${cells(totals)}</tr>`;

    view(`<table class="data"><thead><tr><th scope="col">Account</th>${labels.map((l, i) =>
      `<th scope="col" class="${i === labels.length - 1 ? "tot" : ""}">${esc(colLabel(l))}</th>`).join("")}</tr></thead>` +
      `<tbody>${body}</tbody><tfoot>${foot}</tfoot></table>`);
  }

  // ---------------------------------------------------------------- date filter

  const DF = MISDateFilter;
  const NO_DATA = ["search", "No data in this period",
    "The selected range has no months in this report run. Pick another period or a Full run."];

  // Sum / last-month the stored month columns into the filter's columns (months, Total, comparison periods).
  const REVENUE = ["Revenue", "Revenue Booked", "Total Revenue"];
  function remapLines(list, L, mode) {
    for (const n of list) {
      n.values = DF.aggregate(n.values, L.cols, mode);
      if (n.children) remapLines(n.children, L, mode);
    }
    // Ratios can't be summed: rebuild each % row from the row above it over revenue.
    list.forEach((n, i) => {
      if (n.kind !== "pct" || !i) return;
      const num = list[i - 1].values, den = (list.find((x) => REVENUE.includes(x.label)) || list[0]).values;
      n.values = Object.fromEntries(L.cols.map((c) => [c.key, den[c.key] ? num[c.key] / den[c.key] : 0]));
    });
  }

  function filterStatement(data, t) {
    const mode = t.id === "bs" ? "balance" : "flow";
    const L = DF.layout({ total: mode === "flow" });
    state.labels = Object.fromEntries(L.cols.map((c) => [c.key, c.label]));
    $("period").textContent = L.summary;
    if (L.empty) return null;
    remapLines(data.lines, L, mode);
    remapLines(data.tree || [], L, mode);
    data.columns = L.cols.map((c) => c.key);
    return data;
  }

  // Dated pivots: the server buckets the lines into the filter's columns (months, Total, comparisons).
  async function loadPivot(t, L) {
    const cur = state.pivot[t.id];
    const get = (measure) => api(`${t.api}?cols=${DF.colsParam(L.cols)}&dim=${cur.dim}&measure=${measure}`);
    if (t.id === "margin") {
      // Every measure side by side: Net sales, Cost, Margin, GM % for each period.
      const [ns, cost, gm] = await Promise.all(MARGIN_MEASURES.slice(0, 3).map(([m]) => get(m)));
      const ratio = (g, n) => Object.fromEntries(L.cols.map((c) => [c.key, n[c.key] ? (g[c.key] || 0) / n[c.key] : 0]));
      const by = (d) => new Map(d.rows.map((r) => [r.label, r]));
      const cm = by(cost), gmm = by(gm);
      const rows = ns.rows.map((r) => {
        const v = { net_sales: r.values, cost: (cm.get(r.label) || {}).values || {}, gross_margin: (gmm.get(r.label) || {}).values || {} };
        v.gm_pct = ratio(v.gross_margin, v.net_sales);
        return { ...r, m: v };
      }).filter((r) => L.cols.some((c) => Math.abs(r.m.net_sales[c.key] || 0) > 0.004 || Math.abs(r.m.cost[c.key] || 0) > 0.004));
      const tot = { net_sales: ns.total, cost: cost.total, gross_margin: gm.total };
      tot.gm_pct = ratio(tot.gross_margin, tot.net_sales);
      return { ...ns, multi: true, rows, mtotal: tot };
    }
    const out = await get(cur.measure);  // gm % arrives as a ratio of sums per column
    out.rows = out.rows.filter((r) => L.cols.some((c) => Math.abs(r.values[c.key] || 0) > 0.004));
    return out;
  }

  // Trial balance: opening rolls forward over the months before the range, closing over the range.
  function filterTb(data) {
    const L = DF.layout({ total: false, compare: false });
    $("period").textContent = L.summary;
    if (L.empty) return null;
    const sum = (r, ms) => ms.reduce((s, m) => s + (Number(r[m]) || 0), 0);
    const earlier = data.months.filter((m) => m < L.from);
    const rows = data.rows.map((r) => {
      const opening = (Number(r.opening) || 0) + sum(r, earlier);
      return { ...r, opening, closing: opening + sum(r, L.main) };
    });
    return { months: L.main, rows };
  }

  // ---------------------------------------------------------------- load

  const fetchHint = (kind, from, to) =>
    `Run <code>main.py ${COMMAND[kind]} --from-date ${esc(from)} --to-date ${esc(to)}</code> to load them.`;

  // Margin / purchases: any date range over everything loaded so far.
  async function loadDated(t) {
    const cov = state.coverage[DATASET[t.kind]];
    const what = t.kind === "margin" ? "sales" : "purchases";
    setHead(null, t.label);
    if (!cov || !cov.ranges.length) {
      stateView("database", `No ${what} loaded yet`,
        `Run <code>main.py ${COMMAND[t.kind]} --from-date … --to-date …</code>, ` +
        `or import a saved file with <code>main.py db-load --${t.kind}-json …</code>.`);
      return;
    }
    DF.setSource({ coverage: cov.merged, fiscalStart: fiscalStart() });
    DF.setCompare(!t.detail);  // flat lists have no period columns to compare
    const L = DF.layout();
    state.labels = Object.fromEntries(L.cols.map((c) => [c.key, c.label]));
    $("period").textContent = L.summary;
    syncUrl();
    if (L.tooMany) {
      stateView("search", `Too many columns (${L.tooMany})`,
        "Shorten the range, split by a longer period, or drop comparison periods.");
      return;
    }
    if (L.empty) {
      stateView("search", `No ${what} loaded for ${DF.rangeLabel(L.from, L.to)}`,
        `Loaded: ${esc(DF.rangeLabel(cov.min, cov.max))}. ${fetchHint(t.kind, L.from, L.to)}`);
      return;
    }
    skeleton();
    if (t.detail) {
      state.detailData = await api(`api/margin-detail?from=${L.from}&to=${L.to}&view=${t.detail}`);
      renderDetail(state.detailData, t);
    } else {
      renderPivot(await loadPivot(t, L), t);
    }
  }

  // When the shown figures were fetched from Zoho, and a Refresh button.
  function showLive(data) {
    const el = $("live");
    const at = new Date(data.fetched_at);
    const sameDay = at.toDateString() === new Date().toDateString();
    const when = at.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) +
      (sameDay ? "" : ` ${at.toLocaleDateString([], { day: "numeric", month: "short" })}`);
    el.className = `rpt-live${data.stale ? " stale" : ""}`;
    el.innerHTML = (data.stale ? `${icon("error")}<span>Zoho unavailable — showing data from ${esc(when)}</span>`
      : `<span title="${data.zoho_calls ? `${data.zoho_calls} Zoho calls` : "From the 15-minute cache"}">Zoho · ${esc(when)}</span>`) +
      `<button type="button" class="btn text" id="liveRefresh">${icon("refresh")}Refresh</button>`;
    el.hidden = false;
  }

  // Executive Summary, P&L, BS, TB live from Zoho for any dates; the server caches for 15 minutes.
  async function loadLive(t, refresh = false) {
    DF.setSource({ live: true, fiscalStart: fiscalStart() });
    DF.setCompare(t.id !== "tb");  // the trial balance has no period columns to compare
    const L = t.id === "tb" ? DF.layout({ total: false, compare: false }) : DF.layout({ total: t.id !== "bs" });
    state.labels = Object.fromEntries(L.cols.map((c) => [c.key, c.label]));
    setHead(null, t.label);
    $("period").textContent = L.summary;
    syncUrl();
    if (L.tooMany) {
      stateView("search", `Too many columns (${L.tooMany})`,
        "Each column is a Zoho call. Shorten the range, split by a longer period, or drop comparison periods.");
      return;
    }
    if (!L.cols.length) return stateView(...NO_DATA);
    const seq = ++state.seq;
    skeleton("Fetching from Zoho… a long range can take a minute the first time.");
    const cols = `cols=${DF.colsParam(L.cols)}${refresh ? "&refresh=1" : ""}`;
    const data = await api(t.statement ? `api/statement?name=${encodeURIComponent(t.statement)}&${cols}` : `api/tb?${cols}`);
    if (seq !== state.seq || tab() !== t) return;  // the user moved on while Zoho answered
    showLive(data);
    if (!t.statement) {
      state.tbData = { months: data.months, rows: data.rows };
      renderTb(state.tbData);
      return;
    }
    data.columns = L.cols.map((c) => c.key);
    state.tree.nodes = null;
    if (t.tree && data.tree?.length) {
      showTree(data, t);
    } else {
      if (t.tree) $("toolbar").innerHTML = "";
      renderStatement(data);
    }
  }

  async function load() {
    const t = tab();
    state.tree.nodes = null;  // drop the previous tab's data so a search never redraws it here
    state.stmtData = null;
    state.pivotData = null;
    state.detailData = null;
    renderTabs();
    renderTools();
    renderExport();
    $("live").hidden = true;
    if (DATASET[t.kind] || isLive(t)) {
      try {
        await (isLive(t) ? loadLive(t) : loadDated(t));
      } catch (e) {
        stateView("error", "Could not load this report", esc(e.message), "error");
      }
      return;
    }
    const hasRuns = pickRun();
    syncUrl();

    if (!hasRuns) {
      setHead(null, t.label);
      stateView(
        "database",
        "No report runs saved yet",
        "Run <code>main.py financials --from-date … --to-date …</code>, or import a saved trial balance " +
          "with <code>main.py db-load --tb-json …</code>.",
      );
      return;
    }

    const runId = state.selected[t.kind];
    const run = runOf(t.kind);
    DF.setSource({ months: run.months, fiscalStart: run.fiscal_year_start });
    DF.setCompare(t.id !== "tb");  // the trial balance has no period columns to compare
    state.labels = {};
    setHead(run, t.label);
    skeleton();
    try {
      if (t.statement) {
        const data = filterStatement(await api(`api/statement?run_id=${runId}&name=${encodeURIComponent(t.statement)}`), t);
        state.tree.nodes = null;
        if (!data) {
          if (t.tree) $("toolbar").innerHTML = "";
          stateView(...NO_DATA);
        } else if (t.tree && data.tree?.length) {
          showTree(data, t);
        } else {
          if (t.tree) $("toolbar").innerHTML = "";  // no stored TB to expand from: plain statement
          renderStatement(data);
        }
      } else {
        state.tbData = filterTb(await api(`api/tb?run_id=${runId}`));
        if (state.tbData) renderTb(state.tbData); else stateView(...NO_DATA);
      }
    } catch (e) {
      stateView("error", "Could not load this report", esc(e.message), "error");
    }
  }

  // ---------------------------------------------------------------- events

  // Report tabs switch in place; the Categories link navigates normally.
  $("tabs").addEventListener("click", (e) => {
    const a = e.target.closest("[data-tab]");
    if (!a || e.ctrlKey || e.metaKey || e.shiftKey) return;
    e.preventDefault();
    if (a.dataset.tab === state.tab) return;
    state.tab = a.dataset.tab;
    load().then(() => $("tabs").querySelector(`[data-tab="${state.tab}"]`)?.focus());
  });

  // Expandable statements: click a parent row (or its chevron) to open it; arrow keys walk the chevrons.
  $("out").addEventListener("click", (e) => {
    const tr = e.target.closest("tr[data-key]");
    if (!tr || (!e.target.closest(".twisty") && String(getSelection()))) return;  // a text drag isn't a click
    const fromButton = !!e.target.closest(".twisty");
    toggle(tr.dataset.key);
    if (fromButton) focusTwisty(tr.dataset.key);
  });
  $("out").addEventListener("keydown", (e) => {
    const b = e.target.closest(".twisty");
    if (!b || !["ArrowRight", "ArrowLeft", "ArrowDown", "ArrowUp"].includes(e.key)) return;
    e.preventDefault();
    const key = b.closest("tr").dataset.key;
    const all = [...$("out").querySelectorAll(".twisty")];
    const at = all.indexOf(b);
    if (e.key === "ArrowDown") return all[at + 1]?.focus();
    if (e.key === "ArrowUp") return all[at - 1]?.focus();
    if (e.key === "ArrowRight") return toggle(key, true) ? focusTwisty(key) : all[at + 1]?.focus();
    if (toggle(key, false)) return focusTwisty(key);
    const parent = state.tree.byKey.get(key)?.parent;  // already closed: step out to the parent
    if (parent) focusTwisty(parent.key);
  });

  $("live").addEventListener("click", (e) => {
    if (!e.target.closest("#liveRefresh")) return;
    loadLive(tab(), true).catch((err) => stateView("error", "Could not load this report", esc(err.message), "error"));
  });

  // Header search: one box for every tab; each view filters its own rows.
  $("q").addEventListener("input", (e) => {
    const v = e.target.value;
    state.query = v;
    state.tbFilter = v;
    state.detailFilter = v;
    state.tree.q = v;
    redraw();
  });

  // More actions menu (Export to Excel, Print). Escape or a click outside closes it.
  const moreMenu = $("moreMenu"), moreBtn = $("moreBtn");
  function setMenu(on) {
    moreMenu.hidden = !on;
    moreBtn.setAttribute("aria-expanded", String(on));
    if (on) moreMenu.querySelector('[role="menuitem"]:not([aria-disabled="true"])')?.focus();
  }
  moreBtn.addEventListener("click", () => setMenu(moreMenu.hidden));
  document.addEventListener("click", (e) => {
    if (!moreMenu.hidden && !e.composedPath().includes($("moreWrap"))) setMenu(false);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !moreMenu.hidden) { setMenu(false); moreBtn.focus(); }
  });
  $("printBtn").addEventListener("click", () => { setMenu(false); window.print(); });

  // The workbook needs the Bearer token, so fetch it and save the blob instead of following a link.
  $("exportBtn").addEventListener("click", async (e) => {
    e.preventDefault();
    const btn = $("exportBtn");
    if (btn.getAttribute("aria-disabled") !== "true") setMenu(false);
    if (btn.getAttribute("aria-disabled") === "true") return;
    if (state.live) {
      const L = DF.layout({ total: true });
      if (!L.cols.length) return snackbar(L.tooMany ? `Too many columns (${L.tooMany})` : "Pick a date range first", true);
      btn.setAttribute("href", `api/export.xlsx?cols=${DF.colsParam(L.cols)}`);
    }
    snackbar(state.live ? "Preparing the Excel workbook (financials live from Zoho)" : "Preparing the Excel workbook");
    try {
      const res = await MISAuth.fetch(btn.getAttribute("href"));
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
      const m = /filename="([^"]+)"/.exec(res.headers.get("Content-Disposition") || "");
      const a = Object.assign(document.createElement("a"), {
        href: URL.createObjectURL(await res.blob()), download: m ? m[1] : "mis-report.xlsx" });
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 10000);
    } catch (err) {
      snackbar(err.message, true);
    }
  });

  if (qs.get("from") && qs.get("to")) DF.setRange(qs.get("from"), qs.get("to"), qs.get("by"));  // a shared link's range
  DF.init({ mount: $("datebar"), onChange: () => load() });
  renderTabs();
  skeleton();
  const noCoverage = { ranges: [], merged: [], gaps: [], min: null, max: null };
  Promise.all([
    api("api/runs?kind=financials"),
    ...Object.values(DATASET).map((ds) => api(`api/coverage?dataset=${ds}`).catch(() => noCoverage)),
    api("api/org").catch(() => ({})),  // company profile from MariaDB; the page still works without it
    api("api/config").catch(() => ({})),
  ])
    .then(([fin, sales, purchases, org, config]) => {
      state.org = org && org.name ? org : null;
      state.live = !!config.live_financials;
      const fy = Number(config.fiscal_year_start_month);
      if (fy >= 1 && fy <= 12) state.fiscalStart = `2000-${String(fy).padStart(2, "0")}`;
      state.runs = { financials: fin.runs };
      state.coverage = { sales, purchases };
      load();
    })
    .catch((e) => stateView("error", "Could not reach the report database", esc(e.message), "error"));
})();
