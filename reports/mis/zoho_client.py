"""Zoho Books API client for MIS reports.

Credentials load from the van-sales root `.env_zoho` (same as zoho_endpoints/).
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]  # nellon_vansales/
load_dotenv(ROOT / ".env_zoho")

TOKEN_URL = "https://accounts.zoho.com/oauth/v2/token"
API_BASE = "https://www.zohoapis.com/books/v3"


def _require_env(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise RuntimeError(f"Missing required env var: {key} (set it in {ROOT / '.env_zoho'})")
    return val


class ZohoClient:
    def __init__(self) -> None:
        self.client_id = _require_env("ZOHO_CLIENT_ID")
        self.client_secret = _require_env("ZOHO_CLIENT_SECRET")
        self.refresh_token = _require_env("ZOHO_REFRESH_TOKEN")
        self.org_id = _require_env("ZOHO_ORG_ID")
        self.session = requests.Session()
        self._authenticate()

    def _authenticate(self) -> None:
        resp = self.session.post(
            TOKEN_URL,
            params={
                "grant_type": "refresh_token",
                "refresh_token": self.refresh_token,
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            },
            timeout=30,
        )
        data = resp.json()
        if "access_token" not in data:
            raise RuntimeError(f"OAuth failed: {data}")
        self.session.headers.update(
            {
                "Authorization": f"Zoho-oauthtoken {data['access_token']}",
                "Content-Type": "application/json;charset=UTF-8",
            }
        )

    def get(self, endpoint: str, params: dict[str, Any] | None = None, timeout: int = 120) -> dict:
        params = dict(params or {})
        params["organization_id"] = self.org_id
        url = f"{API_BASE}{endpoint}"
        resp = self.session.get(url, params=params, timeout=timeout)
        try:
            body = resp.json()
        except Exception as exc:
            raise RuntimeError(f"{endpoint} returned non-JSON HTTP {resp.status_code}: {resp.text[:300]}") from exc
        if resp.status_code != 200 or body.get("code") not in (0, None):
            raise RuntimeError(
                f"{endpoint} failed: HTTP {resp.status_code} code={body.get('code')} msg={body.get('message')}"
            )
        return body
