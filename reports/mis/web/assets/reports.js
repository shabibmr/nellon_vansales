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
    { id: "exec", label: "Executive Summary", kind: "financials", statement: "Executive Summary" },
    { id: "pl", label: "Profit & Loss", kind: "financials", statement: "PL" },
    { id: "bs", label: "Balance Sheet", kind: "financials", statement: "BS" },
    { id: "tb", label: "Trial Balance", kind: "financials" },
  ];

  const qs = new URLSearchParams(location.search);
  const state = {
    tab: TABS.some((t) => t.id === qs.get("tab")) ? qs.get("tab") : "exec",
    runs: { financials: [] },
    selected: { financials: null },
    tbFilter: "",
    tbData: null,
  };
  const initialRun = Number(qs.get("run")) || null;

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
    if (pct) return `${(n * 100).toFixed(1)}%`;
    return Math.abs(n) < 0.005 ? "-" : NUM.format(n);
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
    const res = await fetch(path, { cache: "no-store" });
    const body = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
    if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
    return body;
  }

  function syncUrl() {
    const p = new URLSearchParams({ tab: state.tab });
    if (initialRun && state.selected.financials === initialRun) p.set("run", initialRun);
    history.replaceState(null, "", `?${p}`);
  }

  // ---------------------------------------------------------------- chrome

  function renderTabs() {
    $("tabs").innerHTML = TABS.map((t) =>
      `<a href="./?tab=${t.id}" data-tab="${t.id}"${t.id === state.tab ? ' aria-current="page"' : ""}>${t.label}</a>`)
      .join("") + `<a href="categories">Categories</a>`;
  }

  function pickRun() {
    const runs = state.runs.financials;
    if (!runs.length) return false;
    if (!runs.some((r) => r.id === state.selected.financials)) state.selected.financials = runs[0].id;
    return true;
  }

  function renderExport() {
    // The workbook covers the selected financials run.
    const btn = $("exportBtn");
    const id = state.selected.financials || (state.runs.financials[0] || {}).id;
    if (id) {
      btn.href = `api/export.xlsx?run_id=${id}`;
      btn.removeAttribute("aria-disabled");
      btn.title = `Run #${id}: Executive Summary, PL, BS and Trial Balance, one sheet each`;
    } else {
      btn.href = "api/export.xlsx";
      btn.setAttribute("aria-disabled", "true");
      btn.title = "Save a financials run first";
    }
  }

  function renderTools() {
    const t = tab();
    let html = "";
    if (t.id === "tb") {
      html = `<label class="field grow"><span>Filter</span>
                <span class="search">${icon("search")}
                  <input class="input" id="tbq" type="search" autocomplete="off"
                         placeholder="Account, code or category" value="${esc(state.tbFilter)}"></span></label>`;
    }
    $("toolbar").innerHTML = html;
    if ($("tbq")) $("tbq").oninput = (e) => { state.tbFilter = e.target.value; renderTb(state.tbData); };
  }

  function setHead(run, title) {
    $("org").textContent = run ? run.organization_name : title;
    $("reportTitle").textContent = run
      ? `${title}, ${run.from_date} to ${run.to_date}, currency ${run.currency_code || "not set"}`
      : "";
    document.title = `${title} · Nellon MIS`;
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
    const balanced = keys.every((key) => Math.abs(totals[key]) < 0.015);
    body += q
      ? `<tr class="total"><td>Total of filtered accounts</td>${cells(totals)}</tr>`
      : `<tr class="check ${balanced ? "ok" : "bad"}"><td>Total, Dr + / Cr - (should be 0)</td>${cells(totals)}</tr>`;

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
        "Run <code>main.py financials --from-date … --to-date …</code>, or import a saved trial balance " +
          "with <code>main.py db-load --tb-json …</code>.",
      );
      return;
    }

    const runId = state.selected[t.kind];
    setHead(runOf(t.kind), t.label);
    skeleton();
    try {
      if (t.statement) {
        renderStatement(await api(`api/statement?run_id=${runId}&name=${encodeURIComponent(t.statement)}`));
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

  $("exportBtn").addEventListener("click", (e) => {
    if ($("exportBtn").getAttribute("aria-disabled") === "true") {
      e.preventDefault();
      return;
    }
    snackbar("Preparing the Excel workbook");
  });

  renderTabs();
  skeleton();
  api("api/runs?kind=financials")
    .then((fin) => {
      state.runs.financials = fin.runs;
      if (initialRun && fin.runs.some((r) => r.id === initialRun)) state.selected.financials = initialRun;
      load();
    })
    .catch((e) => stateView("error", "Could not reach the report database", esc(e.message), "error"));
})();
