/* Shared date filter for MIS pages: a date range (presets or custom) plus up to 5 earlier (−) and
   5 later (+) comparison periods of the same length. The choice is kept in localStorage, so every
   report page and tab opens with the same range.

   Two grains:
   - "month" (financials): the source is a stored run's month list; columns are its months, and pages
     `aggregate()` month values into them.
   - "day" (margin, purchases): the source is the loaded-date coverage; columns are date ranges
     (`{key, label, from, to}`) the server buckets itself — pass `colsParam()` to the API. */
const MISDateFilter = (() => {
  "use strict";

  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const STORE = "mis.datefilter.v2";
  const OLD_STORE = "mis.datefilter";
  const MAX_COMPARE = 5;
  const PRESETS = [
    ["run", "Full run"], ["this_month", "This month"], ["last_month", "Last month"],
    ["this_quarter", "This quarter"], ["last_quarter", "Last quarter"],
    ["this_year", "This year"], ["last_year", "Last year"], ["custom", "Custom"],
  ];
  const presetText = (id) => (id === "run" && grain === "day" ? "All loaded data" : PRESETS.find((p) => p[0] === id)[1]);

  // Month index = year * 12 + month0, so ranges and shifts are plain integer maths.
  const toIdx = (key) => {
    const m = /^(\d{4})-(\d{2})/.exec(key || "");
    return m ? Number(m[1]) * 12 + Number(m[2]) - 1 : NaN;
  };
  const toKey = (i) => `${String(Math.floor(i / 12)).padStart(4, "0")}-${String((i % 12) + 1).padStart(2, "0")}`;
  const label = (key) => `${MON[Number(key.slice(5, 7)) - 1]}-${key.slice(2, 4)}`;
  const spanLabel = (a, b) => (a === b ? label(a) : `${label(a)} – ${label(b)}`);

  // Day maths on ISO strings via UTC dates (no time-zone drift).
  const D = (iso) => new Date(`${iso}T00:00:00Z`);
  const iso = (d) => d.toISOString().slice(0, 10);
  const addDays = (s, n) => { const d = D(s); d.setUTCDate(d.getUTCDate() + n); return iso(d); };
  const daysBetween = (a, b) => Math.round((D(b) - D(a)) / 86400000);
  const monthFirst = (i) => `${toKey(i)}-01`;
  const monthLast = (i) => iso(new Date(Date.UTC(Math.floor(i / 12), (i % 12) + 1, 0)));
  const dayOf = (s) => Number(s.slice(8, 10));
  const todayIso = () => { const n = new Date(); return iso(new Date(Date.UTC(n.getFullYear(), n.getMonth(), n.getDate()))); };
  const minS = (a, b) => (a < b ? a : b);
  const maxS = (a, b) => (a > b ? a : b);
  const dayLabel = (s) => `${dayOf(s)} ${MON[Number(s.slice(5, 7)) - 1]}`;
  const dayLabelY = (s) => `${dayLabel(s)} ${s.slice(2, 4)}`;
  // "1 – 15 Oct", "28 Sep – 3 Oct", "Oct-26" for a whole month, "Apr-26 – Sep-26" for whole months.
  function rangeLabel(a, b) {
    if (dayOf(a) === 1 && b === monthLast(toIdx(b))) return spanLabel(a.slice(0, 7), b.slice(0, 7));
    if (a === b) return dayLabelY(a);
    if (a.slice(0, 7) === b.slice(0, 7)) return `${dayOf(a)} – ${dayOf(b)} ${MON[Number(a.slice(5, 7)) - 1]} ${a.slice(2, 4)}`;
    return `${dayLabel(a)}${a.slice(0, 4) === b.slice(0, 4) ? "" : ` ${a.slice(2, 4)}`} – ${dayLabelY(b)}`;
  }

  let grain = "month";
  let months = [];       // month grain: available month keys of the selected run, ascending
  let coverage = [];     // day grain: loaded [{from, to}] ranges, merged and sorted
  let fyStart = 0;       // 0-based month the fiscal year starts in
  let compareOn = true;
  let mount = null;
  let notify = () => {};
  let sel = { preset: "run", from: "", to: "", before: 0, after: 0 };  // from / to: YYYY-MM-DD

  try {
    let saved = JSON.parse(localStorage.getItem(STORE) || "null");
    if (!saved) {  // v1 kept months (YYYY-MM): widen them to whole months
      saved = JSON.parse(localStorage.getItem(OLD_STORE) || "null");
      if (saved && /^\d{4}-\d{2}$/.test(saved.from || "") && /^\d{4}-\d{2}$/.test(saved.to || "")) {
        saved.from = `${saved.from}-01`;
        saved.to = monthLast(toIdx(saved.to));
      }
    }
    if (saved && PRESETS.some(([id]) => id === saved.preset)) sel = { ...sel, ...saved };
  } catch { /* storage blocked: defaults */ }
  const clampN = (n) => Math.max(0, Math.min(MAX_COMPARE, Number(n) || 0));
  sel.before = clampN(sel.before);
  sel.after = clampN(sel.after);
  const validDay = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || "") && !Number.isNaN(D(s).getTime());
  if (!validDay(sel.from) || !validDay(sel.to)) sel = { ...sel, from: "", to: "", preset: sel.preset === "custom" ? "run" : sel.preset };

  const persist = () => { try { localStorage.setItem(STORE, JSON.stringify(sel)); } catch { /* ignore */ } };

  // ---------------------------------------------------------------- month grain (financials)

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
    if (grain === "day") {
      return coverage.length ? [toIdx(coverage[0].from), toIdx(coverage[coverage.length - 1].to)] : [0, 0];
    }
    return months.length ? [toIdx(months[0]), toIdx(months[months.length - 1])] : [0, 0];
  }

  const within = (a, b) => months.filter((m) => { const i = toIdx(m); return i >= a && i <= b; });

  /* Columns to draw, oldest first: earlier periods, the range's months (+ Total for flow reports),
     later periods. Comparison periods are the same length as the range, stepped back / forward. */
  function monthLayout({ total, compare }) {
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

  // ---------------------------------------------------------------- day grain (margin, purchases)

  // The chosen range as ISO dates. Presets stop at today; "All loaded data" is the coverage span.
  function wantedDays() {
    const today = todayIso();
    const [a, b] = wanted();
    switch (sel.preset) {
      case "custom": return sel.from <= sel.to ? [sel.from, sel.to] : [sel.to, sel.from];
      case "run": return coverage.length ? [coverage[0].from, coverage[coverage.length - 1].to] : null;
      default: {
        const start = monthFirst(a);
        return start > today ? [start, monthLast(b)] : [start, minS(monthLast(b), today)];
      }
    }
  }

  const loaded = (a, b) => coverage.some((r) => r.from <= b && r.to >= a);

  // Parts of [a, b] not covered by the loaded ranges.
  function gapsIn(a, b) {
    const out = [];
    let cur = a;
    for (const r of coverage) {
      if (r.to < cur) continue;
      if (r.from > b) break;
      if (r.from > cur) out.push([cur, minS(b, addDays(r.from, -1))]);
      cur = maxS(cur, addDays(r.to, 1));
      if (cur > b) break;
    }
    if (cur <= b) out.push([cur, b]);
    return out;
  }

  /* Same period one step back / forward: a range starting on the 1st steps by whole months (so
     1–17 Oct compares with 1–17 Sep); any other range steps by its own length in days. */
  function shifted(a, b, k) {
    if (dayOf(a) === 1) {
      const n = toIdx(b) - toIdx(a) + 1;
      const ei = toIdx(b) + n * k;
      const end = b === monthLast(toIdx(b)) ? monthLast(ei) : minS(`${toKey(ei)}-${b.slice(8, 10)}`, monthLast(ei));
      return [monthFirst(toIdx(a) + n * k), end];
    }
    const len = daysBetween(a, b) + 1;
    return [addDays(a, len * k), addDays(b, len * k)];
  }

  function dayLayout({ total, compare }) {
    const range = wantedDays();
    if (!range) return { cols: [], main: [], empty: true, from: "", to: "", summary: "", gaps: [] };
    const [a, b] = range;
    const cols = [];
    const period = (k) => {
      const [pa, pb] = shifted(a, b, k);
      if (!loaded(pa, pb)) return;
      cols.push({ key: `p${k < 0 ? "-" : "+"}${Math.abs(k)}`, label: rangeLabel(pa, pb), from: pa, to: pb,
        kind: "period", offset: k });
    };
    if (compare) for (let k = -sel.before; k < 0; k++) period(k);
    const main = [];
    for (let i = toIdx(a); i <= toIdx(b); i++) {
      const ca = maxS(a, monthFirst(i)), cb = minS(b, monthLast(i));
      const whole = ca === monthFirst(i) && cb === monthLast(i);
      main.push(toKey(i));
      cols.push({ key: toKey(i), label: whole ? label(toKey(i)) : `${label(toKey(i))} (${dayOf(ca)}–${dayOf(cb)})`,
        from: ca, to: cb, kind: "month" });
    }
    if (total) cols.push({ key: "Total", label: "Total", from: a, to: b, kind: "total" });
    if (compare) for (let k = 1; k <= sel.after; k++) period(k);
    const days = daysBetween(a, b) + 1;
    return {
      cols, main, empty: !loaded(a, b), from: a, to: b, gaps: gapsIn(a, b),
      summary: `${rangeLabel(a, b)} · ${days} day${days > 1 ? "s" : ""}`,
    };
  }

  function layout({ total = true, compare = compareOn } = {}) {
    return grain === "day" ? dayLayout({ total, compare }) : monthLayout({ total, compare });
  }

  /* One row of month values → one value per column. "flow" sums the months of a column,
     "balance" takes the last month (closing position). Month grain only. */
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

  // `cols=key:from:to,…` for the dated report API (day grain).
  const colsParam = (cols) => encodeURIComponent(cols.map((c) => `${c.key}:${c.from}:${c.to}`).join(","));

  // First / last day of the chosen range as ISO dates.
  function isoRange() {
    const L = layout({ total: false, compare: false });
    if (!L.from) return null;
    if (grain === "day") return { from: L.from, to: L.to };
    return { from: `${L.from}-01`, to: monthLast(toIdx(L.to)) };
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

  // Data bounds for the inputs and hint: month keys (month grain) or ISO dates (day grain).
  function bounds() {
    if (grain === "day") return coverage.length ? [coverage[0].from, coverage[coverage.length - 1].to] : ["", ""];
    return [months[0] || "", months[months.length - 1] || ""];
  }

  function hintText(info) {
    const [lo, hi] = bounds();
    if (!lo) return ["", false];
    if (grain === "day") {
      if (!info.from) return ["", false];
      if (info.empty) return [`Nothing loaded for ${rangeLabel(info.from, info.to)} (loaded: ${rangeLabel(lo, hi)})`, true];
      const g = info.gaps.map(([a, b]) => rangeLabel(a, b));
      return [g.length ? `${info.summary} · not loaded: ${g.join(", ")}` : info.summary, g.length > 0];
    }
    if (!info.empty) return [info.summary, false];
    const [wa, wb] = wanted();
    return [`No data in ${spanLabel(toKey(wa), toKey(wb))} (data covers ${spanLabel(lo, hi)})`, true];
  }

  function render() {
    if (!mount) return;
    const [lo, hi] = bounds();
    const custom = sel.preset === "custom";
    const info = layout({ total: false, compare: false });
    const [hint, warn] = hintText(info);
    const inputs = grain === "day"
      ? `<label class="field"><span>From</span><input class="input" type="date" id="dfFrom" value="${esc(sel.from || lo)}"></label>
         <label class="field"><span>To</span><input class="input" type="date" id="dfTo" value="${esc(sel.to || hi)}"></label>`
      : `<label class="field"><span>From</span><input class="input" type="month" id="dfFrom" min="${lo}" max="${hi}" value="${esc((sel.from || lo).slice(0, 7))}"></label>
         <label class="field"><span>To</span><input class="input" type="month" id="dfTo" min="${lo}" max="${hi}" value="${esc((sel.to || hi).slice(0, 7))}"></label>`;
    mount.innerHTML =
      `<label class="field"><span>Period</span><select class="input" id="dfPreset">${PRESETS.map(([id]) =>
        `<option value="${id}"${id === sel.preset ? " selected" : ""}>${presetText(id)}</option>`).join("")}</select></label>` +
      (custom ? inputs : "") +
      (compareOn ? stepper("b", "Earlier periods", sel.before) + stepper("a", "Later periods", sel.after) : "") +
      `<p class="df-hint${warn ? " warn" : ""}" id="dfHint">${esc(hint)}</p>`;
  }

  function change(patch) {
    sel = { ...sel, ...patch };
    persist();
    render();
    notify();
  }

  // The range currently shown, as ISO dates (seeds the custom inputs when switching to Custom).
  function shownRange() {
    if (grain === "day") return wantedDays() || ["", ""];
    const [a, b] = wanted();
    const lo = toIdx(months[0]), hi = toIdx(months[months.length - 1]);
    return [monthFirst(Number.isNaN(lo) ? a : Math.max(a, lo)), monthLast(Number.isNaN(hi) ? b : Math.min(b, hi))];
  }

  function bind() {
    mount.addEventListener("change", (e) => {
      if (e.target.id === "dfPreset") {
        const patch = { preset: e.target.value };
        if (patch.preset === "custom" && !sel.from) [patch.from, patch.to] = shownRange();
        change(patch);
      } else if (e.target.id === "dfFrom" || e.target.id === "dfTo") {
        let from = $v("dfFrom"), to = $v("dfTo");
        if (!from || !to) return;
        if (grain === "month") { from = `${from}-01`; to = monthLast(toIdx(to)); }
        change({ from, to });
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
    /** What the page is showing: a run's months (month grain) or loaded date ranges (day grain,
        `coverage` = [{from, to}] merged), and where the fiscal year starts. */
    setSource({ months: list, coverage: cov, fiscalStart }) {
      const nextGrain = cov ? "day" : "month";
      const next = cov ? cov.map((r) => ({ from: r.from, to: r.to })) : [...(list || [])].sort();
      const fs = toIdx(fiscalStart);
      const start = Number.isNaN(fs) ? 0 : fs % 12;
      const prev = grain === "day" ? coverage : months;
      const same = nextGrain === grain && start === fyStart && JSON.stringify(next) === JSON.stringify(prev);
      grain = nextGrain;
      if (cov) coverage = next; else months = next;
      fyStart = start;
      if (!same) render();  // a re-render would drop focus from the control being used
    },
    /** Open on a given date range (e.g. from a shared link) without notifying. */
    setRange(from, to) {
      if (!validDay(from) || !validDay(to)) return;
      sel = { ...sel, preset: "custom", from: minS(from, to), to: maxS(from, to) };
      persist();
      render();
    },
    /** Pages without period columns (e.g. trial balance) turn the ± steppers off. */
    setCompare(on) { if (compareOn !== on) { compareOn = on; render(); } },
    layout, aggregate, isoRange, colsParam, label, spanLabel, rangeLabel,
  };
})();
