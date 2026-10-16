/* Reports page: reads MariaDB through the local server API, never Zoho. */
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const icon = (name, cls = "") =>
    `<svg class="icon ${cls}" aria-hidden="true"><use href="assets/icons.svg#${name}"/></svg>`;

  const NUM = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

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

  // Pivot tabs (margin, purchases): rows = chosen dimension, columns = months + Total.
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
  const state = {
    tab: TABS.some((t) => t.id === qs.get("tab")) ? qs.get("tab") : "exec",
    runs: { financials: [], margin: [], purchases: [] },
    selected: { financials: null, margin: null, purchases: null },
    pivot: { margin: { dim: "item", measure: "net_sales" }, purchases: { dim: "vendor", measure: "amount" } },
    tbFilter: "",
    detailFilter: "",
    detailData: null,
    org: null,
    tbData: null,
    // Expandable statements: `tree` on a tab is its default outline level.
    tree: { nodes: null, cols: [], open: new Set(), q: "", sort: "statement", reveal: null },
  };

  // ---------------------------------------------------------------- helpers

  const tab = () => TABS.find((t) => t.id === state.tab) || TABS[0];
  const runOf = (kind) => state.runs[kind].find((r) => r.id === state.selected[kind]);

  const colLabel = (c) => {
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
  const skeleton = () => view(`<div class="skeleton" aria-label="Loading report">${"<div></div>".repeat(9)}</div>`);
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

  function syncUrl() {
    const p = new URLSearchParams({ tab: state.tab });
    history.replaceState(null, "", `?${p}`);
  }

  // ---------------------------------------------------------------- chrome

  function renderTabs() {
    $("tabs").innerHTML = TABS.map((t) =>
      `<a href="./?tab=${t.id}" data-tab="${t.id}"${t.id === state.tab ? ' aria-current="page"' : ""}>${t.label}</a>`)
      .join("") + `<a href="categories">Categories</a>`;
  }

  function pickRun() {
    const kind = tab().kind;
    const runs = state.runs[kind];
    if (!runs.length) return false;
    if (!runs.some((r) => r.id === state.selected[kind])) state.selected[kind] = runs[0].id;
    return true;
  }

  function renderExport() {
    // The workbook covers the selected financials run.
    const btn = $("exportBtn");
    const id = state.selected.financials || (state.runs.financials[0] || {}).id;
    if (id) {
      const extra = ["margin", "purchases"].map((k) => state.selected[k] ? `&${k}_run=${state.selected[k]}` : "").join("");
      btn.href = `api/export.xlsx?run_id=${id}${extra}`;
      btn.removeAttribute("aria-disabled");
      btn.title = `Run #${id}: Executive Summary, PL, BS, Trial Balance, Margin, Purchases and Category Master`;
    } else {
      btn.href = "api/export.xlsx";
      btn.setAttribute("aria-disabled", "true");
      btn.title = "Save a financials run first";
    }
  }

  function renderTools() {
    const t = tab();
    let html = "";
    if (t.detail) {
      html = `<label class="field grow"><span>Filter</span>
          <span class="search">${icon("search")}
            <input class="input" id="dtq" type="search" autocomplete="off"
                   placeholder="Invoice, customer or item" value="${esc(state.detailFilter)}"></span></label>`;
    }
    if (t.tree) {
      html = `<div class="field"><span id="lvlLabel">Outline level</span>
                <div class="outline" id="treeLevels" role="group" aria-labelledby="lvlLabel"></div></div>
        <label class="field"><span>Order</span><select class="input" id="treeSort">
          <option value="statement"${state.tree.sort === "statement" ? " selected" : ""}>Statement order</option>
          <option value="size"${state.tree.sort === "size" ? " selected" : ""}>Largest first</option></select></label>
        <label class="field grow"><span>Find</span>
          <span class="search">${icon("search")}
            <input class="input" id="treeq" type="search" autocomplete="off"
                   placeholder="Category, sub-category, account or code" value="${esc(state.tree.q)}"></span></label>`;
    }
    if (t.id === "tb") {
      html = `<label class="field grow"><span>Filter</span>
                <span class="search">${icon("search")}
                  <input class="input" id="tbq" type="search" autocomplete="off"
                         placeholder="Account, code or category" value="${esc(state.tbFilter)}"></span></label>`;
    }
    if (t.pivot) {
      const cfg = PIVOTS[t.id], cur = state.pivot[t.id];
      const opts = (list, sel) => list.map(([v, l]) =>
        `<option value="${v}"${v === sel ? " selected" : ""}>${esc(l)}</option>`).join("");
      html = `<label class="field"><span>Rows</span><select class="input" id="pvDim">${opts(cfg.dims, cur.dim)}</select></label>
        <label class="field"><span>Measure</span><select class="input" id="pvMeasure">${opts(cfg.measures, cur.measure)}</select></label>`;
    }
    $("toolbar").innerHTML = html;
    if ($("pvDim")) {
      $("pvDim").onchange = (e) => { state.pivot[t.id].dim = e.target.value; load(); };
      $("pvMeasure").onchange = (e) => { state.pivot[t.id].measure = e.target.value; load(); };
    }
    if ($("dtq")) $("dtq").oninput = (e) => { state.detailFilter = e.target.value; renderDetail(state.detailData, t); };
    if ($("tbq")) $("tbq").oninput = (e) => { state.tbFilter = e.target.value; renderTb(state.tbData); };
    if ($("treeq")) {
      $("treeq").oninput = (e) => { state.tree.q = e.target.value; renderTree(); };
      $("treeSort").onchange = (e) => { state.tree.sort = e.target.value; renderTree(); };
      $("treeLevels").onclick = (e) => {
        const b = e.target.closest("[data-level]");
        if (b) setLevel(Number(b.dataset.level));
      };
    }
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
    $("orgName").textContent = (state.org && state.org.name) || "";
    document.title = `${title} · ${(state.org && state.org.name) || "MIS"}`;
  }

  // ---------------------------------------------------------------- reports

  function renderStatement(data) {
    const cols = data.columns;
    if (!data.lines.length) {
      stateView("database", "Nothing in this statement", `This run has no ${esc(data.statement)} lines.`);
      return;
    }
    const body = data.lines.map((ln) => {
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

    const levels = levelCount(nodes), lv = currentLevel();
    if ($("treeLevels")) $("treeLevels").innerHTML = Array.from({ length: levels }, (_, k) => k + 1).map((l) =>
      `<button type="button" data-level="${l}" aria-pressed="${l === lv}" title="${
        l === 1 ? "Collapse everything" : l === levels ? "Expand down to accounts" : `Open ${l - 1} level${l > 2 ? "s" : ""} down`
      }">${l}</button>`).join("");

    if (q && !found) {
      stateView("search", "Nothing matches", "Try a different category, account name or code.");
      return;
    }

    const order = (list) => sort === "size" && list[0]?.depth > 0
      ? [...list].sort((a, b) => Math.abs(nodeTotal(b)) - Math.abs(nodeTotal(a))) : list;

    let seq = 0;
    const row = (n, { isOpen = false, kids = false, revealing = false, dim = false } = {}) => {
      const p = n.parent;
      const cls = [n.kind, `d${n.depth}`, kids && "parent", isOpen && "open", revealing && "reveal", dim && "dim"];
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

  function renderPivot(data, t) {
    if (!data.rows.length) {
      stateView("database", "Nothing in this run", "This run has no lines.");
      return;
    }
    const pct = data.measure === "gm_pct";
    const cols = data.columns;
    const body = data.rows.map((r) =>
      `<tr>${t.kind === "margin" ? txt(r.label, r.flagged ? `<span class="tag review">${r.flagged} flagged</span>` : "")
        : `<td>${esc(r.label)}${r.flagged ? `<span class="tag review">${r.flagged} flagged</span>` : ""}</td>`}` +
      cols.map((c) => numCell(r.values[c] ?? 0, { pct, total: c === "Total" })).join("") + `</tr>`).join("");
    const foot = `<tr class="total"><td>Total</td>` +
      cols.map((c) => numCell(data.total[c] ?? 0, { pct, total: c === "Total" })).join("") + `</tr>`;
    const dimLabel = PIVOTS[t.id].dims.find(([v]) => v === data.dimension)?.[1] || "Rows";
    view(`<table class="data">${headRow(dimLabel, cols, "Total")}<tbody>${body}${foot}</tbody></table>`);
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
    view(`<table class="data"><thead><tr>${head.join("")}</tr></thead><tbody>${body}${foot}</tbody></table>`);
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
    if (q) body += `<tr class="total"><td>Total of filtered accounts</td>${cells(totals)}</tr>`;

    view(`<table class="data"><thead><tr><th scope="col">Account</th>${labels.map((l, i) =>
      `<th scope="col" class="${i === labels.length - 1 ? "tot" : ""}">${esc(colLabel(l))}</th>`).join("")}</tr></thead>` +
      `<tbody>${body}</tbody></table>`);
  }

  // ---------------------------------------------------------------- load

  async function load() {
    const t = tab();
    renderTabs();
    const hasRuns = pickRun();
    renderTools();
    renderExport();
    syncUrl();

    if (!hasRuns) {
      setHead(null, t.label);
      stateView(
        "database",
        "No report runs saved yet",
        t.kind === "financials"
          ? "Run <code>main.py financials --from-date … --to-date …</code>, or import a saved trial balance " +
            "with <code>main.py db-load --tb-json …</code>."
          : `Run <code>main.py ${t.kind === "margin" ? "margin" : "purchases"} --from-date … --to-date …</code>, ` +
            `or import a saved file with <code>main.py db-load --${t.kind}-json …</code>.`,
      );
      return;
    }

    const runId = state.selected[t.kind];
    setHead(runOf(t.kind), t.label);
    skeleton();
    try {
      if (t.detail) {
        state.detailData = await api(`api/margin-detail?run_id=${runId}&view=${t.detail}`);
        renderDetail(state.detailData, t);
      } else if (t.pivot) {
        const cur = state.pivot[t.id];
        renderPivot(await api(`${t.api}?run_id=${runId}&dim=${cur.dim}&measure=${cur.measure}`), t);
      } else if (t.statement) {
        const data = await api(`api/statement?run_id=${runId}&name=${encodeURIComponent(t.statement)}`);
        state.tree.nodes = null;
        if (t.tree && data.tree?.length) {
          showTree(data, t);
        } else {
          if (t.tree) $("toolbar").innerHTML = "";  // no stored TB to expand from: plain statement
          renderStatement(data);
        }
      } else {
        state.tbData = await api(`api/tb?run_id=${runId}`);
        renderTb(state.tbData);
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

  // The workbook needs the Bearer token, so fetch it and save the blob instead of following a link.
  $("exportBtn").addEventListener("click", async (e) => {
    e.preventDefault();
    const btn = $("exportBtn");
    if (btn.getAttribute("aria-disabled") === "true") return;
    snackbar("Preparing the Excel workbook");
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

  renderTabs();
  skeleton();
  Promise.all([
    ...["financials", "margin", "purchases"].map((k) => api(`api/runs?kind=${k}`)),
    api("api/org").catch(() => ({})),  // company profile from MariaDB; the page still works without it
  ])
    .then(([fin, mar, pur, org]) => {
      state.org = org && org.name ? org : null;
      state.runs = { financials: fin.runs, margin: mar.runs, purchases: pur.runs };
      load();
    })
    .catch((e) => stateView("error", "Could not reach the report database", esc(e.message), "error"));
})();
