/* Sales Dashboard loader: the dashboard's HTML/CSS/JS are only served to a valid Zoho web-tab JWT.
   Fetch each file with the Bearer token, then assemble the page in place. */
(async () => {
  "use strict";
  const BASE = "api/sales-dashboard/";
  const msg = document.getElementById("msg");
  const get = async (name) => {
    const res = await MISAuth.fetch(BASE + name, { cache: "no-store" });
    if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
    return res.text();
  };
  try {
    const doc = new DOMParser().parseFromString(await get("index.html"), "text/html");
    await Promise.all([...doc.querySelectorAll('link[rel="stylesheet"]')].map(async (l) => {
      const href = l.getAttribute("href");
      if (/^(https?:)?\/\//.test(href)) return;
      l.replaceWith(Object.assign(document.createElement("style"), { textContent: await get(href) }));
    }));
    const scripts = [...doc.querySelectorAll("script")].map((s) => ({
      src: s.getAttribute("src"), text: s.textContent, type: s.type }));
    doc.querySelectorAll("script").forEach((s) => s.remove());
    document.title = doc.title || document.title;
    document.head.append(...[...doc.head.children].filter((n) => n.tagName !== "TITLE"));
    document.body.replaceWith(doc.body);
    for (const s of scripts) {
      const el = document.createElement("script");
      if (s.src && /^(https?:)?\/\//.test(s.src)) {
        el.src = s.src;
        await new Promise((ok) => { el.onload = el.onerror = ok; document.head.append(el); });
      } else {
        el.textContent = s.src ? await get(s.src) : s.text;
        document.body.append(el);
      }
    }
  } catch (e) {
    msg.textContent = e.message;
  }
})();
