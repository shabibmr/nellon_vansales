/* Shared date filter for MIS pages: a From / To range (presets or any dates), split into one column
   per week / month / quarter / 6 months / year (earlier/later comparison steppers removed from the UI)
   periods of the same length. The choice is kept in localStorage, so every report page and tab opens
   with the same range. Quarters, halves and years follow the fiscal year; weeks run Monday–Sunday.

   Two grains:
   - "month" (stored financials runs): the source is a run's month list; columns are its months, and
     pages `aggregate()` month values into them.
   - "day" (margin, purchases; live financials): the source is the loaded-date coverage, or `live`
     (any dates, fetched on demand); columns are date ranges (`{key, label, from, to}`) the server
     buckets itself — pass `colsParam()` to the API. */
const MISDateFilter = (() => {
  "use strict";

  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const STORE = "mis.datefilter.v3";
  const OLD_STORE = "mis.datefilter";
  const MAX_COMPARE = 5;
  const PRESETS = [
    ["run", "Full run"], ["last_3m", "Last 3 months"], ["this_month", "This month"], ["last_month", "Last month"],
    ["this_quarter", "This quarter"], ["last_quarter", "Last quarter"],
    ["this_year", "This year"], ["last_year", "Last year"], ["custom", "Custom"],
  ];
  const presetText = (id) => (id !== "run" || grain === "month" ? PRESETS.find((p) => p[0] === id)[1]
    : live ? "Year to date" : "All loaded data");
  const SPLITS = [["week", "Weekly"], ["month", "Monthly"], ["quarter", "Quarterly"], ["half", "6 months"], ["year", "Annual"]];
  const SPLIT_MONTHS = { month: 1, quarter: 3, half: 6, year: 12 };
  const MAX_COLS = 40;  // the dated report API refuses more (reports/periods.py MAX_COLS)

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
  let live = false;      // day grain without coverage: any dates (live financials)
  let fyStart = 0;       // 0-based month the fiscal year starts in
  let compareOn = false;
  let mount = null;
  let notify = () => {};
  let sel = { preset: "last_3m", from: "", to: "", split: "month", before: 0, after: 0 };  // from / to: YYYY-MM-DD

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
  sel.before = 0;  // earlier / later period steppers were removed from the UI
  sel.after = 0;
  if (!SPLITS.some(([id]) => id === sel.split)) sel.split = "month";
  const validDay = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || "") && !Number.isNaN(D(s).getTime());
  if (!validDay(sel.from) || !validDay(sel.to)) sel = { ...sel, from: "", to: "", preset: sel.preset === "custom" ? "last_3m" : sel.preset };

  const persist = () => { try { localStorage.setItem(STORE, JSON.stringify(sel)); } catch { /* ignore */ } };

  // Weekly needs day data; month-grain sources (stored financials runs) fall back to monthly.
  const split = () => (grain === "month" && sel.split === "week" ? "month" : sel.split);
  // First month index of the fiscal-aligned block of `n` months containing month index i.
  const blockStart = (i, n) => i - ((((i - fyStart) % n) + n) % n);

  // ---------------------------------------------------------------- month grain (financials)

  // The chosen range as month indexes, before clamping to the data that exists.
  function wanted() {
    const now = new Date();
    const t = now.getFullYear() * 12 + now.getMonth();
    const inYear = (t - fyStart + 12 * 100) % 12;   // months since the fiscal year began
    const yearStart = t - inYear;
    const quarterStart = t - (inYear % 3);
    switch (sel.preset) {
      case "last_3m": return [t - 2, t];
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
    if (live) return [yearStart, t];
    if (grain === "day") {
      return coverage.length ? [toIdx(coverage[0].from), toIdx(coverage[coverage.length - 1].to)] : [0, 0];
    }
    return months.length ? [toIdx(months[0]), toIdx(months[months.length - 1])] : [0, 0];
  }

  const within = (a, b) => months.filter((m) => { const i = toIdx(m); return i >= a && i <= b; });

  /* Columns to draw, oldest first: earlier periods, one column per split block of the range's months
     (+ Total for flow reports), later periods. Comparison periods are the same length as the range,
     stepped back / forward. `main` stays the list of months (the trial balance rolls over it). */
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
    const n = SPLIT_MONTHS[split()];
    for (const m of main) {
      const key = n === 1 ? m : toKey(blockStart(toIdx(m), n));
      const last = cols[cols.length - 1];
      if (last && last.key === key) {
        last.months.push(m);
        last.label = spanLabel(last.months[0], m);
      } else {
        cols.push({ key, label: label(m), months: [m], kind: "split" });
      }
    }
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
      case "run":
        if (live) return [monthFirst(a), today];
        return coverage.length ? [coverage[0].from, coverage[coverage.length - 1].to] : null;
      default: {
        const start = monthFirst(a);
        return start > today ? [start, monthLast(b)] : [start, minS(monthLast(b), today)];
      }
    }
  }

  const loaded = (a, b) => live || coverage.some((r) => r.from <= b && r.to >= a);

  // Parts of [a, b] not covered by the loaded ranges.
  function gapsIn(a, b) {
    if (live) return [];
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

  // Last day of the split block (week, month, quarter, half, year) that contains day s.
  function blockEnd(s) {
    if (split() === "week") return addDays(s, 6 - ((D(s).getUTCDay() + 6) % 7));
    const n = SPLIT_MONTHS[split()];
    return monthLast(blockStart(toIdx(s), n) + n - 1);
  }

  // [a, b] cut into split blocks; the first and last may be partial.
  function blocks(a, b) {
    const out = [];
    for (let s = a; s <= b;) {
      const e = minS(b, blockEnd(s));
      out.push([s, e]);
      s = addDays(e, 1);
    }
    return out;
  }

  function blockCol([ca, cb]) {
    const sp = split();
    if (sp === "month") {
      const key = ca.slice(0, 7);
      const whole = dayOf(ca) === 1 && cb === monthLast(toIdx(cb));
      return { key, label: whole ? label(key) : `${label(key)} (${dayOf(ca)}–${dayOf(cb)})`, from: ca, to: cb, kind: "split" };
    }
    return { key: `${sp[0]}${ca}`, label: rangeLabel(ca, cb), from: ca, to: cb, kind: "split" };
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
    const parts = blocks(a, b).map(blockCol);
    const main = parts.map((c) => c.key);
    cols.push(...parts);
    if (total) cols.push({ key: "Total", label: "Total", from: a, to: b, kind: "total" });
    if (compare) for (let k = 1; k <= sel.after; k++) period(k);
    const days = daysBetween(a, b) + 1;
    const tooMany = cols.length > MAX_COLS ? cols.length : 0;
    return {
      cols: tooMany ? [] : cols, main, empty: tooMany > 0 || !loaded(a, b), tooMany, from: a, to: b, gaps: gapsIn(a, b),
      summary: `${rangeLabel(a, b)} · ${days} day${days > 1 ? "s" : ""} · ${parts.length} column${parts.length > 1 ? "s" : ""}`,
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

  // Data bounds for the inputs and hint: month keys (month grain) or ISO dates (day grain).
  function bounds() {
    if (grain === "day") return coverage.length ? [coverage[0].from, coverage[coverage.length - 1].to] : ["", ""];
    return [months[0] || "", months[months.length - 1] || ""];
  }

  function hintText(info) {
    const [lo, hi] = bounds();
    if (live && info.tooMany) return [`${info.tooMany} columns — at most ${MAX_COLS}. Shorten the range, split by a longer period or drop comparisons.`, true];
    if (live) return [info.from ? `${info.summary} · live from Zoho` : "", false];
    if (!lo) return ["", false];
    if (grain === "day") {
      if (!info.from) return ["", false];
      if (info.tooMany) return [`${info.tooMany} columns — at most ${MAX_COLS}. Shorten the range, split by a longer period or drop comparisons.`, true];
      if (info.empty) return [`Nothing loaded for ${rangeLabel(info.from, info.to)} (loaded: ${rangeLabel(lo, hi)})`, true];
      const g = info.gaps.map(([a, b]) => rangeLabel(a, b));
      return [g.length ? `${info.summary} · not loaded: ${g.join(", ")}` : info.summary, g.length > 0];
    }
    if (!info.empty) return [sel.split === "week" ? `${info.summary} · weekly needs live financials, shown monthly` : info.summary, false];
    const [wa, wb] = wanted();
    return [`No data in ${spanLabel(toKey(wa), toKey(wb))} (data covers ${spanLabel(lo, hi)})`, true];
  }

  /* The period control: ‹ [period button] › opening a popover. The popover edits a draft copy of
     the selection (presets, From / To, split) and only Apply commits it, so a live report is not
     re-fetched from Zoho on every click. */
  let open = false;
  let draft = null;

  // Run fn with `s` as the selection, so the layout maths can preview the draft.
  function withSel(s, fn) {
    const keep = sel;
    sel = s;
    try { return fn(); } finally { sel = keep; }
  }

  // [name, dates] for the button: "Last 3 months" + "Jul-26 – Sep-26"; a custom range is just its dates.
  function periodParts(info) {
    let range;
    if (info.from) range = grain === "day" ? rangeLabel(info.from, info.to) : spanLabel(info.from, info.to);
    else { const [a, b] = wanted(); range = spanLabel(toKey(a), toKey(b)); }
    return sel.preset === "custom" ? [range, ""] : [presetText(sel.preset), range];
  }

  // The shown range moved back (-1) or forward (+1) by its own length; null once it leaves the data.
  function stepped(k) {
    const r = isoRange();
    if (!r) return null;
    const [a, b] = shifted(r.from, r.to, k);
    if (live) return a > todayIso() ? null : [a, b];
    let [lo, hi] = bounds();
    if (!lo) return null;
    if (grain === "month") { lo = `${lo}-01`; hi = monthLast(toIdx(hi)); }
    return b < lo || a > hi ? null : [maxS(a, lo), minS(b, hi)];
  }

  const chev = (dir) => `<svg class="icon df-chev ${dir}" aria-hidden="true"><use href="assets/icons.svg#chevron_right"/></svg>`;
  const CALENDAR = `<svg class="icon df-cal" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 2h2v2h6V2h2v2h2a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2V2Zm12 8H5v9h14v-9ZM5 8h14V6H5v2Z"/></svg>`;

  function dateField(text, id, value) {
    const [lo, hi] = bounds();
    const attrs = grain === "day"
      ? `type="date" value="${esc(value || "")}"`
      : `type="month" min="${esc(lo)}" max="${esc(hi)}" value="${esc((value || "").slice(0, 7))}"`;
    return `<label class="df-field"><span>${text}</span><input class="input" id="${id}" data-focus="${id}" ${attrs}></label>`;
  }

  // Popover body for the draft selection.
  function popover() {
    return withSel(draft, () => {
      const [lo, hi] = bounds();
      const info = layout({ total: false, compare: false });
      const [hint, warn] = hintText(info);
      const [fa, fb] = draft.preset === "custom" ? [draft.from, draft.to] : shownRange();
      const [name, dates] = periodParts(info);
      const cur = split();
      const cols = info.cols.length;
      const splits = SPLITS.filter(([id]) => grain === "day" || id !== "week");
      const shown = dates ? `${name} · ${dates}` : name;
      const shows = cols ? `${shown} · ${cols} column${cols > 1 ? "s" : ""}` : shown;
      return `<div class="df-pop" id="dfPop" role="dialog" aria-label="Choose period">` +
        `<div class="df-body">` +
          `<div class="df-nav" role="group" aria-label="Period">${PRESETS.map(([id]) =>
            `<button type="button" class="df-preset" data-preset="${id}" data-focus="p-${id}" aria-pressed="${id === draft.preset}">${esc(presetText(id))}</button>`).join("")}</div>` +
          `<div class="df-pane">` +
            `<div class="df-dates">${dateField("From", "dfFrom", fa || lo)}${dateField("To", "dfTo", fb || hi)}</div>` +
            (hint ? `<p class="df-note${warn ? " warn" : ""}">${esc(hint)}</p>` : "") +
          `</div>` +
        `</div>` +
        `<div class="df-split"><span class="df-split-label" id="dfSl">Split into columns</span>` +
          `<div class="seg" role="group" aria-labelledby="dfSl">${splits.map(([id, text]) =>
            `<button type="button" data-split="${id}" data-focus="s-${id}" aria-pressed="${id === cur}">${text}</button>`).join("")}</div>` +
        `</div>` +
        `<div class="df-foot">` +
          `<span class="df-shows">Shows <strong>${esc(shows)}</strong></span>` +
          `<button type="button" class="btn outlined df-btn" data-act="cancel" data-focus="cancel">Cancel</button>` +
          `<button type="button" class="btn filled df-btn" data-act="apply" data-focus="apply">Apply</button>` +
        `</div>` +
      `</div>`;
    });
  }

  function render() {
    if (!mount) return;
    // Re-rendering replaces the controls; keep focus on the one in use.
    const focused = mount.contains(document.activeElement) ? document.activeElement.dataset.focus : null;
    const info = layout({ total: false, compare: false });
    const [hint, warn] = hintText(info);
    const [name, dates] = periodParts(info);
    const prev = stepped(-1), next = stepped(1);
    const splitName = (SPLITS.find(([id]) => id === split()) || SPLITS[1])[1];
    mount.innerHTML =
      `<button type="button" class="icon-btn df-step" data-step="-1" data-focus="prev" aria-label="Previous period"${prev ? "" : " disabled"}>${chev("left")}</button>` +
      `<button type="button" class="df-trigger" data-focus="trigger" aria-haspopup="dialog" aria-expanded="${open}" aria-controls="dfPop"${hint ? ` title="${esc(hint)}"` : ""}>` +
        `${CALENDAR}<span class="df-name">${esc(name)}</span>` +
        (dates ? `<span class="df-dates-text">· ${esc(dates)}</span>` : "") +
        `<span class="df-tag">${esc(splitName)}</span>` +
        (warn ? `<span class="df-tag warn">Check dates</span>` : "") +
        `${chev("down")}</button>` +
      `<button type="button" class="icon-btn df-step" data-step="1" data-focus="next" aria-label="Next period"${next ? "" : " disabled"}>${chev("right")}</button>` +
      (open ? popover() : "");
    if (focused) mount.querySelector(`[data-focus="${focused}"]`)?.focus();
  }

  function change(patch) {
    sel = { ...sel, ...patch };
    persist();
    render();
    notify();
  }

  function setOpen(on) {
    open = on;
    if (on) draft = { ...sel };
    render();
    mount.querySelector(on ? ".df-preset[aria-pressed='true']" : ".df-trigger")?.focus();
  }

  function editDraft(patch) {
    draft = { ...draft, ...patch };
    render();
  }

  // The range currently shown, as ISO dates (seeds the custom inputs when switching to Custom).
  function shownRange() {
    if (grain === "day") return wantedDays() || ["", ""];
    const [a, b] = wanted();
    const lo = toIdx(months[0]), hi = toIdx(months[months.length - 1]);
    return [monthFirst(Number.isNaN(lo) ? a : Math.max(a, lo)), monthLast(Number.isNaN(hi) ? b : Math.min(b, hi))];
  }

  function bind() {
    mount.addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (!btn || btn.disabled) return;
      if (btn.dataset.step) {
        const r = stepped(Number(btn.dataset.step));
        if (r) change({ preset: "custom", from: r[0], to: r[1] });
      } else if (btn.classList.contains("df-trigger")) {
        setOpen(!open);
      } else if (btn.dataset.preset) {
        const patch = { preset: btn.dataset.preset };
        if (patch.preset === "custom" && !draft.from) [patch.from, patch.to] = withSel(draft, shownRange);
        editDraft(patch);
      } else if (btn.dataset.split) {
        editDraft({ split: btn.dataset.split });
      } else if (btn.dataset.act === "cancel") {
        setOpen(false);
      } else if (btn.dataset.act === "apply") {
        open = false;
        change(draft);
        mount.querySelector(".df-trigger")?.focus();
      }
    });
    // From / To edit the draft; either one switches it to Custom.
    mount.addEventListener("change", (e) => {
      if (e.target.id !== "dfFrom" && e.target.id !== "dfTo") return;
      let from = $v("dfFrom"), to = $v("dfTo");
      if (!from || !to) return;
      if (grain === "month") { from = `${from}-01`; to = monthLast(toIdx(to)); }
      editDraft({ preset: "custom", from: minS(from, to), to: maxS(from, to) });
    });
    // Escape or a click outside closes the popover without applying. composedPath, because a click
    // inside re-renders the popover and detaches its target before this listener runs.
    document.addEventListener("keydown", (e) => {
      if (open && e.key === "Escape") setOpen(false);
    });
    document.addEventListener("click", (e) => {
      if (open && !e.composedPath().includes(mount)) { open = false; render(); }
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
    /** What the page is showing: a run's months (month grain), loaded date ranges (day grain,
        `coverage` = [{from, to}] merged) or `live` (day grain, any dates), and where the fiscal year
        starts. */
    setSource({ months: list, coverage: cov, live: isLive = false, fiscalStart }) {
      if (isLive) cov = [];
      const nextGrain = cov ? "day" : "month";
      const next = cov ? cov.map((r) => ({ from: r.from, to: r.to })) : [...(list || [])].sort();
      const fs = toIdx(fiscalStart);
      const start = Number.isNaN(fs) ? 0 : fs % 12;
      const prev = grain === "day" ? coverage : months;
      const same = nextGrain === grain && start === fyStart && isLive === live && JSON.stringify(next) === JSON.stringify(prev);
      grain = nextGrain;
      live = isLive;
      if (cov) coverage = next; else months = next;
      fyStart = start;
      if (!same) render();  // a re-render would drop focus from the control being used
    },
    /** Open on a given date range and optional split (e.g. from a shared link) without notifying. */
    setRange(from, to, by) {
      if (!validDay(from) || !validDay(to)) return;
      sel = { ...sel, preset: "custom", from: minS(from, to), to: maxS(from, to) };
      if (SPLITS.some(([id]) => id === by)) sel.split = by;
      persist();
      render();
    },
    split,
    /** Pages without period columns (e.g. trial balance) turn the ± steppers off. */
    setCompare(on) { if (compareOn !== on) { compareOn = on; render(); } },
    layout, aggregate, isoRange, colsParam, label, spanLabel, rangeLabel,
  };
})();
