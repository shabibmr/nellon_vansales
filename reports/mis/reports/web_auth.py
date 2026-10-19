"""Zoho Books web-tab JWT verification for the report viewer (stdlib only).

Zoho posts the token to the iframe (postMessage); assets/webtab-auth.js sends it on every /api call
as `Authorization: Bearer <jwt>`. Stateless: no cookies, no sessions. Token lifetime is Zoho's
"Token Validity" setting on the web tab (the page refreshes it before expiry).

Config (reports/mis/.env.mis, git-ignored):
    MIS_JWT_SECRET    secret entered on the Zoho web tab, 32-500 chars (unset -> every /api call is refused)
    MIS_AUTH_DISABLED set to 1 for local development only: skips JWT checks when no secret is set
    MIS_ZOHO_ORG_ID   optional; token's organization_id must equal it
    MIS_ZOHO_TAB_ID   optional; token's tab_id must equal it
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env.mis")

LEEWAY = 60  # seconds of clock drift tolerated on exp

# Only Zoho may frame the pages (same domains as ZOHO_ORIGIN in web/assets/webtab-auth.js).
FRAME_ANCESTORS = "frame-ancestors " + " ".join(
    f"https://*.zoho.{tld}" for tld in ("com", "ae", "eu", "in", "sa", "jp", "ca", "uk", "com.au", "com.cn"))


def secret() -> bytes | None:
    s = os.getenv("MIS_JWT_SECRET", "").strip()
    return s.encode() if s else None


def enabled() -> bool:
    return secret() is not None


def explicitly_disabled() -> bool:
    """Opt-out for local development; only honoured when no secret is configured."""
    return secret() is None and os.getenv("MIS_AUTH_DISABLED", "").strip() == "1"


def framed(fetch_dest: str | None, asset: bool) -> bool:
    """Block direct access to pages/assets: browsers set Sec-Fetch-Dest and page scripts cannot change it.

    A page must load as an iframe (the Zoho web tab); an asset as a subresource of one (script, style,
    image...), never as a top-level document. No header at all means a non-browser client: refused too.
    Not a substitute for the JWT (curl can send any header): it only keeps the shell out of plain tabs.
    """
    dest = (fetch_dest or "").strip().lower()
    if asset:
        return dest not in ("", "document", "iframe", "frame")
    return dest == "iframe"


def _b64d(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def verify_jwt(token: str, key: bytes, now: float | None = None) -> dict[str, Any]:
    """Return the claims of a valid Zoho web-tab token, else raise ValueError."""
    now = time.time() if now is None else now
    try:
        head_b64, body_b64, sig_b64 = token.split(".")
        header = json.loads(_b64d(head_b64))
        claims = json.loads(_b64d(body_b64))
        sig = _b64d(sig_b64)
    except Exception as exc:
        raise ValueError("malformed token") from exc
    if header.get("alg") != "HS256":  # never let the header pick a weaker alg (e.g. "none")
        raise ValueError("unsupported alg")
    expected = hmac.new(key, f"{head_b64}.{body_b64}".encode(), hashlib.sha256).digest()
    if not hmac.compare_digest(sig, expected):
        raise ValueError("bad signature")
    if not isinstance(claims, dict):
        raise ValueError("bad claims")
    exp = claims.get("exp")
    if not isinstance(exp, (int, float)) or now > exp + LEEWAY:
        raise ValueError("token expired or missing exp")
    nbf = claims.get("nbf")
    if isinstance(nbf, (int, float)) and now + LEEWAY < nbf:
        raise ValueError("token not yet valid")
    if claims.get("token_type") != "access":
        raise ValueError("token_type is not access")
    want_org = os.getenv("MIS_ZOHO_ORG_ID", "").strip()
    if want_org and str(claims.get("organization_id")) != want_org:
        raise ValueError("organization mismatch")
    want_tab = os.getenv("MIS_ZOHO_TAB_ID", "").strip()
    if want_tab and str(claims.get("tab_id")) != want_tab:
        raise ValueError("tab mismatch")
    return claims
