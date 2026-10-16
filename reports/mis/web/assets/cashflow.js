/* Cashflow seeker. End-of-day balance = opening + signed events on or before that day.
   Same rule as reports.cashflow_forecast.balances. */
(() => {
  "use strict";

  const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const HORIZONS = [30, 60, 90, 180];
  const KIND = { ar: "Receivable", ap: "Payable", po: "Purchase order", so: "Sales order" };

  const $ = (id) => document.getElementById(id);
  const DAY_LIST_CAP = 25;
  let payload = null;
  let byDate = new Map();
  let rows = [];
  let index = 0;
  let horizon = 90;
  let chartReady = false;
  let geom = null;

  const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

  function addDays(iso, n) {
    const [y, m, d] = iso.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
  }

  function pretty(iso) {
    const [y, m, d] = iso.split("-");
    return `${Number(d)} ${MONTHS[Number(m) - 1]} ${y}`;
  }

  function esc(value) {
    return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[ch]));
  }

  function money(n) {
    const abs = Math.abs(n).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    return n < 0 ? `${payload.currency} (${abs})` : `${payload.currency} ${abs}`;
  }

  function getJson(path) {
    const embedded = window.parent !== window;
    const run = embedded && window.MISAuth
      ? MISAuth.fetch(path, { cache: "no-store" })
      : fetch(path, { cache: "no-store" });
    return run.then(async (res) => {
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || `Could not load the forecast (${res.status})`);
      return body;
    });
  }

  function buildSeries(days) {
    const start = payload.as_of;
    const end = addDays(start, days);
    const flow = new Map();
    const inn = new Map();
    const outg = new Map();
    for (const event of payload.events) {
      if (event.date < start || event.date > end) continue;
      flow.set(event.date, round2((flow.get(event.date) || 0) + event.amount));
      if (event.amount >= 0) inn.set(event.date, round2((inn.get(event.date) || 0) + event.amount));
      else outg.set(event.date, round2((outg.get(event.date) || 0) - event.amount));
    }
    const out = [];
    let balance = payload.opening;
    let income = 0;
    let expense = 0;
    for (let iso = start; iso <= end; iso = addDays(iso, 1)) {
      const dayFlow = flow.get(iso) || 0;
      const dayIn = inn.get(iso) || 0;
      const dayOut = outg.get(iso) || 0;
      balance = round2(balance + dayFlow);
      income = round2(income + dayIn);
      expense = round2(expense + dayOut);
      out.push({ date: iso, flow: round2(dayFlow), balance, income, expense });
    }
    return out;
  }

  function cumulative(iso) {
    const totals = { ar: 0, ap: 0, po: 0, so: 0 };
    for (const event of payload.events) {
      if (event.date <= iso) totals[event.kind] += event.amount;
    }
    for (const key of Object.keys(totals)) totals[key] = round2(totals[key]);
    return totals;
  }

  function movementIndexes() {
    const found = [];
    rows.forEach((row, i) => { if (row.flow) found.push(i); });
    return found;
  }

  function setIndex(next, force) {
    next = Math.max(0, Math.min(rows.length - 1, next));
    if (!force && next === index && chartReady) return;
    index = next;
    const seeker = $("seeker");
    seeker.value = String(index);
    seeker.setAttribute("aria-valuenow", String(index));
    seeker.setAttribute("aria-valuemax", String(rows.length - 1));
    paint();
    if (!chartReady) draw();
    else moveCursor();
  }

  function paint() {
    const row = rows[index];
    const totals = cumulative(row.date);
    const negative = row.balance < 0;
    $("balance").textContent = money(row.balance);
    $("balance").classList.toggle("neg", negative);
    const delta = round2(row.balance - payload.opening);
    $("delta").textContent = delta === 0
      ? "Same as opening cash"
      : `${delta < 0 ? "Down" : "Up"} ${money(Math.abs(delta))} from opening cash`;
    $("kicker").textContent = `Balance on ${pretty(row.date)}, after that day's movements`;
    $("seekNow").textContent = pretty(row.date);
    $("seeker").setAttribute("aria-valuetext", `${pretty(row.date)}, ${money(row.balance)}`);
    const span = Math.max(1, rows.length - 1);
    $("seeker").style.setProperty("--seek", `${(index / span) * 100}%`);

    const stat = (label, amount) =>
      `<div class="cf-stat"><span>${label}</span><strong class="num${amount < 0 ? " neg" : ""}">${money(amount)}</strong></div>`;
    $("stats").innerHTML = [
      stat("Opening cash", payload.opening),
      stat("Receivable", totals.ar),
      stat("Payable", totals.ap),
      stat("Purchase orders", totals.po),
      stat("Sales orders", totals.so),
    ].join("");

    const todays = byDate.get(row.date) || [];
    $("dayTitle").textContent = todays.length ? `Movements on ${pretty(row.date)}` : pretty(row.date);
    $("dayMeta").textContent = todays.length
      ? `${todays.length.toLocaleString("en-US")} movement${todays.length === 1 ? "" : "s"} · net ${money(row.flow)}`
      : "Nothing falls due. The balance is unchanged.";
    $("dayList").innerHTML = renderDay(todays);

    const end = rows[rows.length - 1].date;
    const later = payload.events.filter((event) => event.date > end);
    $("laterSection").hidden = later.length === 0;
    if (later.length) {
      const net = round2(later.reduce((sum, event) => sum + event.amount, 0));
      $("laterMeta").textContent = `${later.length} movements, net ${money(net)}, sit after ${pretty(end)}. Extend the horizon to bring them onto the road.`;
    }
  }

  function stoneIndexes() {
    const n = rows.length;
    const target = n <= 31 ? 5 : n <= 91 ? 7 : 8;
    const step = Math.max(1, Math.round((n - 1) / Math.max(1, target - 1)));
    const idx = [];
    for (let i = 0; i < n; i += step) idx.push(i);
    if (idx[idx.length - 1] !== n - 1) idx.push(n - 1);
    return idx;
  }

  function stoneParts(iso) {
    const [y, m, d] = iso.split("-");
    const mon = MONTHS[Number(m) - 1];
    const startYear = rows[0].date.slice(0, 4);
    return { day: String(Number(d)), mon: y === startYear ? mon : `${mon} ${y.slice(2)}` };
  }

  function stepArea(key, yOf, baseline, xOf) {
    let path = "";
    rows.forEach((row, i) => {
      const x0 = xOf(i);
      const x1 = xOf(i) + geomSlot();
      const yy = yOf(row[key]).toFixed(1);
      path += `${i ? "L" : "M"}${x0.toFixed(1)},${yy} L${x1.toFixed(1)},${yy} `;
    });
    const xLast = (xOf(rows.length - 1) + geomSlot()).toFixed(1);
    const yBase = baseline.toFixed(1);
    return `${path}L${xLast},${yBase} L${xOf(0).toFixed(1)},${yBase} Z`;
  }

  function geomSlot() {
    return geom.slot;
  }

  function draw() {
    const host = $("chart");
    const width = 1000;
    const sideH = 64;
    const roadH = 52;
    const padX = 28;
    const topLabel = 4;
    const botLabel = 4;
    const roadTop = topLabel + sideH;
    const roadBot = roadTop + roadH;
    const height = roadBot + sideH + botLabel;
    const plotW = width - padX * 2;
    const slot = plotW / rows.length;
    const xOf = (i) => padX + i * slot;
    const mid = (i) => xOf(i) + slot / 2;
    let maxMag = 0;
    for (const row of rows) maxMag = Math.max(maxMag, row.income, row.expense);
    if (maxMag <= 0) maxMag = 1;
    const yIn = (v) => roadTop - (v / maxMag) * sideH;
    const yOut = (v) => roadBot + (v / maxMag) * sideH;
    geom = { x: mid, pad: { l: padX, r: padX }, plotW, width, slot, roadMid: (roadTop + roadBot) / 2 };
    const incomeArea = stepArea("income", yIn, roadTop, xOf);
    const expenseArea = stepArea("expense", yOut, roadBot, xOf);
    const stones = stoneIndexes().map((i) => {
      const part = stoneParts(rows[i].date);
      const cx = mid(i);
      return `<g class="cf-stone" data-x="${cx.toFixed(1)}" transform="translate(${cx.toFixed(1)} ${geom.roadMid.toFixed(1)})">
        <rect class="cf-stone-body" x="-20" y="-16" width="40" height="32" rx="8"></rect>
        <text class="cf-stone-day" y="-1" text-anchor="middle">${part.day}</text>
        <text class="cf-stone-mon" y="10" text-anchor="middle">${part.mon}</text>
      </g>`;
    }).join("");
    const from = pretty(rows[0].date);
    const to = pretty(rows[rows.length - 1].date);
    const incomeLabelY = (topLabel + 16).toFixed(1);
    const expenseLabelY = (roadBot + 16).toFixed(1);
    host.innerHTML = `
      <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Income above the road and expenses below, ${from} to ${to}. Dates are milestones on the road.">
        <path d="${incomeArea}" class="cf-in-ghost"></path>
        <path d="${expenseArea}" class="cf-out-ghost"></path>
        <g clip-path="url(#cfPast)">
          <path d="${incomeArea}" class="cf-in"></path>
          <path d="${expenseArea}" class="cf-out"></path>
        </g>
        <clipPath id="cfPast"><rect class="cf-clip" x="0" y="0" width="0" height="${height}"></rect></clipPath>
        <rect class="cf-road" x="${padX}" y="${roadTop}" width="${plotW}" height="${roadH}"></rect>
        <line class="cf-edge" x1="${padX + 6}" y1="${roadTop + 4}" x2="${width - padX - 6}" y2="${roadTop + 4}"></line>
        <line class="cf-lane" x1="${padX + 6}" y1="${geom.roadMid}" x2="${width - padX - 6}" y2="${geom.roadMid}"></line>
        <line class="cf-edge" x1="${padX + 6}" y1="${roadBot - 4}" x2="${width - padX - 6}" y2="${roadBot - 4}"></line>
        ${stones}
        <g class="cf-here">
          <rect class="cf-here-body" x="-22" y="-18" width="44" height="36" rx="8"></rect>
          <text class="cf-here-day" y="-1" text-anchor="middle"></text>
          <text class="cf-here-mon" y="11" text-anchor="middle"></text>
        </g>
        <text x="${padX}" y="${incomeLabelY}" class="cf-side-name">Income</text>
        <text x="${width - padX}" y="${incomeLabelY}" text-anchor="end" class="cf-in-amt"></text>
        <text x="${padX}" y="${expenseLabelY}" class="cf-side-name">Expense</text>
        <text x="${width - padX}" y="${expenseLabelY}" text-anchor="end" class="cf-out-amt"></text>
      </svg>`;
    chartReady = true;
    moveCursor();
  }

  function moveCursor() {
    if (!geom) return;
    const svg = $("chart").querySelector("svg");
    if (!svg) return;
    const row = rows[index];
    const cx = geom.x(index);
    const revealed = geom.pad.l + (index + 1) * geom.slot;
    const clip = svg.querySelector(".cf-clip");
    clip.setAttribute("width", revealed.toFixed(1));
    const here = svg.querySelector(".cf-here");
    here.setAttribute("transform", `translate(${cx.toFixed(1)} ${geom.roadMid.toFixed(1)})`);
    const part = stoneParts(row.date);
    svg.querySelector(".cf-here-day").textContent = part.day;
    svg.querySelector(".cf-here-mon").textContent = part.mon;
    svg.querySelector(".cf-in-amt").textContent = money(row.income);
    svg.querySelector(".cf-out-amt").textContent = money(row.expense);
    svg.querySelectorAll(".cf-stone").forEach((stone) => {
      const near = Math.abs(Number(stone.getAttribute("data-x")) - cx) < 34;
      stone.setAttribute("visibility", near ? "hidden" : "visible");
    });
  }

  function seekFromPointer(event) {
    const svg = $("chart").querySelector("svg");
    if (!svg || !geom || !rows.length) return;
    const rect = svg.getBoundingClientRect();
    const local = ((event.clientX - rect.left) / rect.width) * geom.width;
    const t = (local - geom.pad.l) / geom.plotW;
    let next = Math.floor(t * rows.length);
    if (next >= rows.length) next = rows.length - 1;
    setIndex(next);
  }

  function renderSide(title, events) {
    const total = round2(events.reduce((sum, event) => sum + event.amount, 0));
    const count = events.length.toLocaleString("en-US");
    const summary = events.length
      ? `${count} movement${events.length === 1 ? "" : "s"} · ${money(total)}`
      : "None on this day.";
    const ranked = events.slice().sort((a, b) => Math.abs(b.amount) - Math.abs(a.amount));
    const shown = ranked.slice(0, DAY_LIST_CAP);
    const rowsHtml = shown.map((event) => `
      <div class="cf-row">
        <span class="cf-kind" data-kind="${esc(event.kind)}">${esc(KIND[event.kind] || event.kind)}</span>
        <span class="cf-who"><b>${esc(event.number || "—")}</b> ${esc(event.party)}<span class="cf-why">${esc(event.label)}${event.overdue ? " · overdue, placed on the first day" : ""}</span></span>
        <span class="num${event.amount < 0 ? " neg" : ""}">${money(event.amount)}</span>
      </div>`).join("");
    const rest = events.length - shown.length;
    const more = rest > 0
      ? `<p class="cf-more">Showing the ${DAY_LIST_CAP} largest. The total above includes all ${count}.</p>`
      : "";
    const list = events.length ? `<div class="cf-list">${rowsHtml}${more}</div>` : "";
    return `<div class="cf-col"><div class="cf-col-head"><h3>${title}</h3><p>${summary}</p></div>${list}</div>`;
  }

  function renderDay(todays) {
    if (!todays.length) return "";
    const receivables = [];
    const payables = [];
    for (const event of todays) {
      if (event.kind === "ap" || event.kind === "po") payables.push(event);
      else receivables.push(event);
    }
    return renderSide("Receivables", receivables) + renderSide("Payables", payables);
  }

  function applyHorizon(days, keepDate) {
    horizon = days;
    const previous = rows[index] ? rows[index].date : payload.as_of;
    chartReady = false;
    rows = buildSeries(days);
    [...$("horizon").querySelectorAll("button")].forEach((button) => {
      const on = Number(button.dataset.days) === days;
      button.setAttribute("aria-pressed", on ? "true" : "false");
    });
    $("seeker").max = String(rows.length - 1);
    $("seekStart").textContent = pretty(rows[0].date);
    $("seekEnd").textContent = pretty(rows[rows.length - 1].date);
    const kept = keepDate ? rows.findIndex((row) => row.date === previous) : 0;
    setIndex(kept === -1 ? 0 : kept, true);
  }

  function show(data) {
    payload = data;
    byDate = new Map();
    for (const event of data.events || []) {
      const list = byDate.get(event.date);
      if (list) list.push(event);
      else byDate.set(event.date, [event]);
    }
    const org = "";
    const live = data.mode === "zoho";
    $("subtitle").textContent = live
      ? `${org}${data.currency} · as of ${pretty(data.as_of)}`
      : `${org}${data.currency} · from ${pretty(data.as_of)} · local files only`;
    const missing = [];
    if (!data.counts.ar) missing.push("accounts receivable");
    if (!data.counts.so) missing.push("sales orders");
    const banner = $("banner");
    banner.classList.remove("ok");
    if (missing.length) {
      banner.hidden = false;
      banner.textContent = `This timeline has no ${missing.join(" or ")}. It is opening bank and cash, then cached bills and unbilled purchase orders.`;
    } else if (!live) {
      banner.hidden = false;
      banner.textContent = "Built from local files.";
    } else {
      banner.hidden = true;
      banner.textContent = "";
    }
    $("notes").innerHTML = data.notes.map((note) => `<li>${esc(note)}</li>`).join("");
    $("accounts").innerHTML = data.accounts.map((account) => `
      <div class="cf-row">
        <span class="cf-kind" data-kind="${esc(account.type)}">${esc(account.type)}</span>
        <span class="cf-who">${esc(account.name)}</span>
        <span class="num${account.balance < 0 ? " neg" : ""}">${money(account.balance)}</span>
      </div>`).join("");
    const pending = data.unscheduled || [];
    $("unschedSection").hidden = pending.length === 0;
    $("unsched").innerHTML = pending.map((item) => `
      <div class="cf-row">
        <span class="cf-kind" data-kind="${esc(item.kind)}">${esc(KIND[item.kind] || item.kind)}</span>
        <span class="cf-who"><b>${esc(item.number || "—")}</b> ${esc(item.party)}</span>
        <span class="cf-why">${esc(item.reason)}</span>
        <span class="num${item.amount < 0 ? " neg" : ""}">${money(item.amount)}</span>
      </div>`).join("");
    $("horizon").innerHTML = HORIZONS.map((days) =>
      `<button type="button" class="btn tonal" data-days="${days}" aria-pressed="${days === horizon}">${days} days</button>`
    ).join("");
    $("horizon").addEventListener("click", (event) => {
      const button = event.target.closest("button");
      if (button) applyHorizon(Number(button.dataset.days), true);
    });
    applyHorizon(horizon, false);
    const requested = new URLSearchParams(location.search).get("day");
    if (requested) {
      const found = rows.findIndex((row) => row.date === requested);
      if (found >= 0) setIndex(found, true);
    }
  }

  const chart = $("chart");
  let dragging = false;
  chart.addEventListener("pointerdown", (event) => {
    dragging = true;
    chart.setPointerCapture(event.pointerId);
    seekFromPointer(event);
  });
  chart.addEventListener("pointermove", (event) => { if (dragging) seekFromPointer(event); });
  chart.addEventListener("pointerup", () => { dragging = false; });
  chart.addEventListener("pointercancel", () => { dragging = false; });

  $("seeker").addEventListener("input", () => setIndex(Number($("seeker").value)));
  $("prevMove").addEventListener("click", () => {
    const found = movementIndexes().filter((i) => i < index);
    if (found.length) setIndex(found[found.length - 1]);
  });
  $("nextMove").addEventListener("click", () => {
    const next = movementIndexes().find((i) => i > index);
    if (next !== undefined) setIndex(next);
  });

  getJson("api/cashflow").then(show).catch((error) => {
    $("balance").textContent = "Forecast unavailable";
    $("banner").hidden = false;
    $("banner").textContent = error.message;
  });
})();
