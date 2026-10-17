/* Shared date filter for MIS pages: a month range (presets or custom) plus up to 5 earlier (−) and
   5 later (+) comparison periods of the same length. The choice is kept in localStorage, so every
   report page and tab opens with the same range. Pure month maths lives here; pages only ask for
   `layout()` (columns) and `aggregate()` (values) and render the result. */
const MISDateFilter = (() => {
  "use strict";

  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const STORE = "mis.datefilter";
  const MAX_COMPARE = 5;
  const PRESETS = [
    ["run", "Full run"], ["this_month", "This month"], ["last_month", "Last month"],
    ["this_quarter", "This quarter"], ["last_quarter", "Last quarter"],
    ["this_year", "This year"], ["last_year", "Last year"], ["custom", "Custom"],
  ];

  // Month index = year * 12 + month0, so ranges and shifts are plain integer maths.
  const toIdx = (key) => {
    const m = /^(\d{4})-(\d{2})/.exec(key || "");
    return m ? Number(m[1]) * 12 + Number(m[2]) - 1 : NaN;
  };
  const toKey = (i) => `${String(Math.floor(i / 12)).padStart(4, "0")}-${String((i % 12) + 1).padStart(2, "0")}`;
  const label = (key) => `${MON[Number(key.slice(5, 7)) - 1]}-${key.slice(2, 4)}`;
  const spanLabel = (a, b) => (a === b ? label(a) : `${label(a)} – ${label(b)}`);

  let months = [];       // available month keys of the selected run, ascending
  let fyStart = 0;       // 0-based month the fiscal year starts in
  let compareOn = true;
  let mount = null;
  let notify = () => {};
  let sel = { preset: "run", from: "", to: "", before: 0, after: 0 };

  try {
    const saved = JSON.parse(localStorage.getItem(STORE) || "null");
    if (saved && PRESETS.some(([id]) => id === saved.preset)) sel = { ...sel, ...saved };
  } catch { /* storage blocked: defaults */ }
  const clampN = (n) => Math.max(0, Math.min(MAX_COMPARE, Number(n) || 0));
  sel.before = clampN(sel.before);
  sel.after = clampN(sel.after);

  const persist = () => { try { localStorage.setItem(STORE, JSON.stringify(sel)); } catch { /* ignore */ } };

  // The chosen range as month indexes, before clamping to the data that exists.
  function wanted() {
    const now = new Date();
    const t = now.getFullYear() * 12 + now.getMonth();
    const inYear = (t - fyStart + 12 * 100) % 12;   // months since the fiscal year began
    const yearStart = t - inYear;
    const quarterStart = t - (inYear % 3);
    switch (sel.preset) {
      case "this_month": return [t, t];
      case "last_month": return [t - 1, t - 1];
      case "this_quarter": return [quarterStart, quarterStart + 2];
      case "last_quarter": return [quarterStart - 3, quarterStart - 1];
      case "this_year": return [yearStart, yearStart + 11];
      case "last_year": return [yearStart - 12, yearStart - 1];
      case "custom": {
        const a = toIdx(sel.from), b = toIdx(sel.to);
        if (Number.isNaN(a) || Number.isNaN(b)) break;
        return a <= b ? [a, b] : [b, a];
      }
      default: break;
    }
    return months.length ? [toIdx(months[0]), toIdx(months[months.length - 1])] : [0, 0];
  }

  const within = (a, b) => months.filter((m) => { const i = toIdx(m); return i >= a && i <= b; });

  /* Columns to draw, oldest first: earlier periods, the range's months (+ Total for flow reports),
     later periods. Comparison periods are the same length as the range, stepped back / forward. */
  function layout({ total = true, compare = compareOn } = {}) {
    const [a, b] = wanted();
    const len = b - a + 1;
    const main = within(a, b);
    const cols = [];
    const period = (k) => {
      const ms = within(a + len * k, b + len * k);
      if (!ms.length) return;
      cols.push({ key: `p${k < 0 ? "-" : "+"}${Math.abs(k)}`, label: spanLabel(ms[0], ms[ms.length - 1]),
        months: ms, kind: "period", offset: k });
    };
    if (compare) for (let k = -sel.before; k < 0; k++) period(k);
    for (const m of main) cols.push({ key: m, label: label(m), months: [m], kind: "month" });
    if (total && main.length) cols.push({ key: "Total", label: "Total", months: main, kind: "total" });
    if (compare) for (let k = 1; k <= sel.after; k++) period(k);
    return {
      cols, main, empty: !main.length,
      from: main[0] || "", to: main[main.length - 1] || "",
      summary: main.length ? `${spanLabel(main[0], main[main.length - 1])} · ${main.length} month${main.length > 1 ? "s" : ""}` : "",
    };
  }

  /* One row of month values → one value per column. "flow" sums the months of a column,
     "balance" takes the last month (closing position). */
  function aggregate(byMonth, cols, mode = "flow") {
    const out = {};
    for (const c of cols) {
      if (mode === "balance") {
        out[c.key] = Number(byMonth[c.months[c.months.length - 1]] ?? 0);
      } else {
        out[c.key] = c.months.reduce((s, m) => s + Number(byMonth[m] ?? 0), 0);
      }
    }
    return out;
  }

  // First / last day of the chosen range as ISO dates, for date-stamped rows.
  function isoRange() {
    const { from, to } = layout({ total: false, compare: false });
    if (!from) return null;
    const i = toIdx(to) + 1;
    const end = new Date(Date.UTC(Math.floor(i / 12), i % 12, 0)).toISOString().slice(0, 10);
    return { from: `${from}-01`, to: end };
  }

  // ---------------------------------------------------------------- UI

  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  function stepper(side, title, n) {
    return `<div class="field"><span id="df-${side}-l">${title}</span>
      <div class="stepper" role="group" aria-labelledby="df-${side}-l">
        <button type="button" class="step" data-df="${side}-" aria-label="Fewer ${title.toLowerCase()}"${n <= 0 ? " disabled" : ""}>−</button>
        <output class="num" aria-live="polite">${n}</output>
        <button type="button" class="step" data-df="${side}+" aria-label="More ${title.toLowerCase()}"${n >= MAX_COMPARE ? " disabled" : ""}>+</button>
      </div></div>`;
  }

  function render() {
    if (!mount) return;
    const lo = months[0] || "", hi = months[months.length - 1] || "";
    const [wa, wb] = wanted();
    const custom = sel.preset === "custom";
    const info = layout({ total: false, compare: false });
    const hint = !months.length ? "" : info.empty
      ? `No data in ${spanLabel(toKey(wa), toKey(wb))} (data covers ${spanLabel(lo, hi)})`
      : info.summary;
    mount.innerHTML =
      `<label class="field"><span>Period</span><select class="input" id="dfPreset">${PRESETS.map(([id, text]) =>
        `<option value="${id}"${id === sel.preset ? " selected" : ""}>${text}</option>`).join("")}</select></label>` +
      (custom
        ? `<label class="field"><span>From</span><input class="input" type="month" id="dfFrom" min="${lo}" max="${hi}" value="${esc(sel.from || lo)}"></label>
           <label class="field"><span>To</span><input class="input" type="month" id="dfTo" min="${lo}" max="${hi}" value="${esc(sel.to || hi)}"></label>`
        : "") +
      (compareOn ? stepper("b", "Earlier periods", sel.before) + stepper("a", "Later periods", sel.after) : "") +
      `<p class="df-hint${info.empty && months.length ? " warn" : ""}" id="dfHint">${esc(hint)}</p>`;
  }

  function change(patch) {
    sel = { ...sel, ...patch };
    persist();
    render();
    notify();
  }

  function bind() {
    mount.addEventListener("change", (e) => {
      if (e.target.id === "dfPreset") {
        const patch = { preset: e.target.value };
        if (patch.preset === "custom" && !sel.from) {
          const [a, b] = wanted();
          patch.from = toKey(Math.max(a, toIdx(months[0]) || a));
          patch.to = toKey(Math.min(b, toIdx(months[months.length - 1]) || b));
        }
        change(patch);
      } else if (e.target.id === "dfFrom" || e.target.id === "dfTo") {
        const from = $v("dfFrom"), to = $v("dfTo");
        if (from && to) change({ from, to });
      }
    });
    mount.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-df]");
      if (!btn || btn.disabled) return;
      const [side, dir] = [btn.dataset.df[0], btn.dataset.df[1]];
      const key = side === "b" ? "before" : "after";
      change({ [key]: clampN(sel[key] + (dir === "+" ? 1 : -1)) });
      mount.querySelector(`[data-df="${btn.dataset.df}"]`)?.focus();
    });
  }
  const $v = (id) => mount.querySelector(`#${id}`)?.value || "";

  return {
    PRESETS,
    init(opts) {
      mount = opts.mount;
      notify = opts.onChange || notify;
      bind();
      render();
    },
    /** The run the pages are showing: which months exist and where its fiscal year starts. */
    setSource({ months: list, fiscalStart }) {
      const next = [...(list || [])].sort();
      const fs = toIdx(fiscalStart);
      const start = Number.isNaN(fs) ? 0 : fs % 12;
      const same = start === fyStart && next.join() === months.join();
      months = next;
      fyStart = start;
      if (!same) render();  // a re-render would drop focus from the control being used
    },
    /** Pages without period columns (e.g. trial balance) turn the ± steppers off. */
    setCompare(on) { if (compareOn !== on) { compareOn = on; render(); } },
    layout, aggregate, isoRange, label, spanLabel,
  };
})();
