/* Category Master page: ledger -> PL/BS category mapping. Select an account to see how it is mapped and,
   when the server allows it (Zoho JWT auth on), edit it: saved as an override in category_overrides.csv. */
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const icon = (name, cls = "") =>
    `<svg class="icon ${cls}" aria-hidden="true"><use href="assets/icons.svg#${name}"/></svg>`;

  const SOURCES = [
    ["review", "Needs review"],
    ["override", "Overridden"],
    ["rule", "By rule"],
    ["type", "By account type"],
  ];
  const STATEMENT = { PL: "P&L", BS: "BS" };
  const NUM = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  let data = null;
  let selectedId = null;
  let sourceFilter = "";
  let editing = false;

  // ---------------------------------------------------------------- helpers

  function snackbar(msg, isErr = false) {
    const s = $("snackbar");
    s.textContent = msg;
    s.className = `snackbar show${isErr ? " err" : ""}`;
    clearTimeout(snackbar.timer);
    snackbar.timer = setTimeout(() => (s.className = "snackbar"), isErr ? 6000 : 3000);
  }

  async function api(path, body) {
    const res = await MISAuth.fetch(path, body === undefined ? { cache: "no-store" } : {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
    if (!res.ok) throw new Error(json.error || `HTTP ${res.status}`);
    return json;
  }

  const ledgers = () => data.rows.filter((r) => r.group_ledger === "Ledger");

  // ---------------------------------------------------------------- render

  function setData(payload) {
    data = payload;
    $("subtitle").textContent =
      `${payload.currency_code} · snapshot ${payload.snapshot_time.replace("T", " ")}`;
    const cats = [...new Set(payload.rows.map((r) => r.category).filter(Boolean))].sort();
    const cur = $("fCat").value;
    $("fCat").innerHTML = `<option value="">All categories</option>` +
      cats.map((c) => `<option${c === cur ? " selected" : ""}>${esc(c)}</option>`).join("");
    render();
  }

  function filtered() {
    const q = $("q").value.trim().toLowerCase();
    const plbs = $("fPlbs").value;
    const cat = $("fCat").value;
    const groups = $("fGroups").checked;
    return data.rows.filter((r) =>
      (groups || r.group_ledger === "Ledger") &&
      (!plbs || r.pl_bs === plbs) &&
      (!cat || r.category === cat) &&
      (!sourceFilter || r.source === sourceFilter) &&
      (!q || [r.ledger_name, r.path, r.category, r.sub_category, r.account_code, r.account_type]
        .some((v) => String(v ?? "").toLowerCase().includes(q))));
  }

  function renderChips() {
    const counts = {};
    ledgers().forEach((r) => (counts[r.source] = (counts[r.source] || 0) + 1));
    $("chips").innerHTML = SOURCES.map(([key, label]) =>
      `<button type="button" class="chip" data-src="${key}" aria-pressed="${sourceFilter === key}">
         ${icon("check")}${label}<span class="count">${counts[key] || 0}</span></button>`).join("");
  }

  function render() {
    renderChips();
    const rows = filtered();
    $("count").textContent = `${rows.length} of ${data.rows.length} accounts`;
    if (!rows.length) {
      $("tableWrap").innerHTML = `<div class="state">${icon("search", "xl")}<h2>No accounts match</h2>
        <p>Clear the search or a filter to see more accounts.</p></div>`;
    } else {
      $("tableWrap").innerHTML = `<table class="data">
        <thead><tr>
          <th scope="col">Ledger</th><th scope="col" class="l">Category</th>
          <th scope="col" class="l">Sub category</th><th scope="col" class="l">Source</th>
          <th scope="col" class="hide-sm">Balance</th>
        </tr></thead>
        <tbody>${rows.map(rowHtml).join("")}</tbody></table>`;
    }
    renderPanel();
  }

  function rowHtml(r) {
    const bal = Number(r.current_balance) || 0;
    const selected = r.account_id === selectedId;
    return `<tr class="selectable${r.group_ledger === "Group" ? " category" : ""}" data-id="${esc(r.account_id)}"
               tabindex="0" aria-selected="${selected}">
      <td>${esc(r.ledger_name)}<span class="tag">${STATEMENT[r.pl_bs] || esc(r.pl_bs)}</span>
        <span class="meta">${esc(r.path)}</span></td>
      <td class="l">${esc(r.category) || '<span class="muted">Not set</span>'}</td>
      <td class="l">${esc(r.sub_category)}</td>
      <td class="l"><span class="tag ${r.source}" title="${esc(r.note)}">${r.source}</span></td>
      <td class="n hide-sm${bal < 0 ? " neg" : ""}">${bal ? (bal < 0 ? `(${NUM.format(-bal)})` : NUM.format(bal)) : ""}</td>
    </tr>`;
  }

  function renderRollup() {
    const by = new Map();
    ledgers().forEach((r) => {
      const k = `${r.pl_bs}|${r.category || ""}`;
      by.set(k, (by.get(k) || 0) + 1);
    });
    const items = [...by.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([k, n]) => {
      const [plbs, cat] = k.split("|");
      return `<button type="button" data-cat="${esc(cat)}" title="Show ${esc(cat || "uncategorised")} ledgers">
        <span class="tag">${STATEMENT[plbs] || esc(plbs)}</span><span>${esc(cat || "Uncategorised")}</span>
        <span class="n">${n}</span></button>`;
    }).join("");
    $("panel").innerHTML = `<h2>Ledgers per category</h2>
      <p class="muted lead">Select a category to filter, or a row to see how it is mapped.</p>
      <div class="rollup">${items}</div>`;
  }

  function renderPanel() {
    const r = data.rows.find((x) => x.account_id === selectedId);
    if (!r) {
      renderRollup();
      return;
    }
    $("panel").innerHTML = `
      <div class="head">
        <div><h2>${esc(r.ledger_name)}</h2><div class="path">${esc(r.path)}</div></div>
        <button type="button" class="icon-btn" id="eClose" aria-label="Close">${icon("close")}</button>
      </div>
      <dl>
        <dt>Statement</dt><dd>${r.pl_bs === "PL" ? "P&amp;L" : r.pl_bs === "BS" ? "Balance Sheet" : esc(r.pl_bs)}</dd>
        <dt>Category</dt><dd>${esc(r.category) || '<span class="muted">Not set</span>'}</dd>
        <dt>Sub category</dt><dd>${esc(r.sub_category) || '<span class="muted">None</span>'}</dd>
        <dt>Decided by</dt><dd><span class="tag ${r.source}">${r.source}</span> <span class="muted">${esc(r.note)}</span></dd>
        <dt>Code</dt><dd>${esc(r.account_code) || "None"}</dd>
        <dt>Zoho type</dt><dd>${esc(r.account_type)}</dd>
        <dt>Level</dt><dd>${esc(r.group_ledger)}</dd>
      </dl>
      ${editing ? editForm(r) : data.can_edit ? `<div class="actions">
        <button type="button" class="btn tonal" id="eEdit">${icon("edit")}Edit mapping</button></div>` : ""}`;
    $("eClose").onclick = () => { selectedId = null; editing = false; render(); };
    if ($("eEdit")) $("eEdit").onclick = () => { editing = true; renderPanel(); $("fe-cat").focus(); };
    if (editing) bindEditForm(r);
  }

  // ---------------------------------------------------------------- edit

  const subsFor = (plbs, cat) =>
    [...new Set(data.rows.filter((x) => x.pl_bs === plbs && x.category === cat).map((x) => x.sub_category).filter(Boolean))].sort();

  function catOptions(plbs, current) {
    const list = data.categories[plbs] || [];
    return list.map((c) => `<option${c === current ? " selected" : ""}>${esc(c)}</option>`).join("");
  }

  function editForm(r) {
    const plbs = data.categories[r.pl_bs] ? r.pl_bs : "PL";
    return `<form id="eForm" class="edit-form" autocomplete="off">
      <label class="field"><span>Statement</span>
        <select class="input" id="fe-plbs"><option value="PL"${plbs === "PL" ? " selected" : ""}>P&amp;L</option>
          <option value="BS"${plbs === "BS" ? " selected" : ""}>Balance Sheet</option></select></label>
      <label class="field"><span>Category</span>
        <select class="input" id="fe-cat" required>${catOptions(plbs, r.category)}</select></label>
      <label class="field"><span>Sub category</span>
        <input class="input" id="fe-sub" list="fe-subs" maxlength="255" value="${esc(r.sub_category)}">
        <datalist id="fe-subs">${subsFor(plbs, r.category).map((v) => `<option value="${esc(v)}">`).join("")}</datalist></label>
      <label class="field"><span>Note (why)</span>
        <input class="input" id="fe-note" maxlength="500" value="${r.source === "override" ? esc(r.note) : ""}"></label>
      <div class="actions">
        <button type="submit" class="btn filled" id="fe-save">Save</button>
        <button type="button" class="btn text" id="fe-cancel">Cancel</button>
        ${r.source === "override" ? `<button type="button" class="btn text" id="fe-revert"
          title="Remove the override; the rule or account type decides again">Revert to rule</button>` : ""}
      </div>
      <p class="muted">Applies to this account only. Saved reports are not recomputed; re-run them to pick it up.</p>
    </form>`;
  }

  function bindEditForm(r) {
    const plbs = $("fe-plbs"), cat = $("fe-cat"), sub = $("fe-sub");
    plbs.onchange = () => {
      cat.innerHTML = catOptions(plbs.value, "");
      $("fe-subs").innerHTML = subsFor(plbs.value, cat.value).map((v) => `<option value="${esc(v)}">`).join("");
    };
    cat.onchange = () => {
      $("fe-subs").innerHTML = subsFor(plbs.value, cat.value).map((v) => `<option value="${esc(v)}">`).join("");
    };
    $("fe-cancel").onclick = () => { editing = false; renderPanel(); };
    const submit = async (path, body, done) => {
      const btns = $("eForm").querySelectorAll("button");
      btns.forEach((b) => (b.disabled = true));
      try {
        setData(await api(path, { account_id: r.account_id, ...body }));
        editing = false;
        renderPanel();
        snackbar(done);
      } catch (e) {
        snackbar(e.message, true);
        btns.forEach((b) => (b.disabled = false));
      }
    };
    $("eForm").onsubmit = (e) => {
      e.preventDefault();
      submit("api/category-override", {
        pl_bs: plbs.value, category: cat.value, sub_category: sub.value.trim(), note: $("fe-note").value.trim(),
      }, "Mapping saved");
    };
    if ($("fe-revert")) {
      $("fe-revert").onclick = () => {
        if (confirm(`Remove the override for ${r.ledger_name}?`)) submit("api/category-override/delete", {}, "Override removed");
      };
    }
  }

  function select(id) {
    selectedId = id === selectedId ? null : id;
    editing = false;
    render();
    const row = $("tableWrap").querySelector(`tr[data-id="${CSS.escape(id)}"]`);
    row?.focus({ preventScroll: true });
  }

  // ---------------------------------------------------------------- events

  $("tableWrap").addEventListener("click", (e) => {
    const tr = e.target.closest("tr[data-id]");
    if (tr) select(tr.dataset.id);
  });
  $("tableWrap").addEventListener("keydown", (e) => {
    const tr = e.target.closest("tr[data-id]");
    if (!tr) return;
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      select(tr.dataset.id);
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      (e.key === "ArrowDown" ? tr.nextElementSibling : tr.previousElementSibling)?.focus();
    }
  });
  $("chips").addEventListener("click", (e) => {
    const chip = e.target.closest("[data-src]");
    if (!chip) return;
    sourceFilter = sourceFilter === chip.dataset.src ? "" : chip.dataset.src;
    render();
  });
  $("panel").addEventListener("click", (e) => {
    const b = e.target.closest("[data-cat]");
    if (!b) return;
    $("fCat").value = b.dataset.cat;
    render();
  });
  ["q", "fPlbs", "fCat", "fGroups"].forEach((id) => $(id).addEventListener("input", render));

  $("refresh").addEventListener("click", async () => {
    const b = $("refresh");
    b.disabled = true;
    b.lastChild.textContent = " Refreshing";
    try {
      setData(await api("api/refresh", {}));
      snackbar("Chart of accounts refreshed from Zoho");
    } catch (e) {
      snackbar(e.message, true);
    } finally {
      b.disabled = false;
      b.lastChild.textContent = " Refresh from Zoho";
    }
  });

  MISTabs.render($("tabs"), "categories");
  api("api/category-master").then(setData).catch((e) => {
    $("subtitle").textContent = "Could not load the chart of accounts";
    $("tableWrap").innerHTML = `<div class="state error">${icon("error", "xl")}
      <h2>Could not load accounts</h2><p>${esc(e.message)}</p></div>`;
    $("panel").innerHTML = "";
  });
})();
