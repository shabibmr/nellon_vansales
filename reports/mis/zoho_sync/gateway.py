"""The `Gateway` interface every Zoho call goes through.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / `gateway.py` row.

`LiveGateway` wraps `ZohoClient`: budget before every call (and each retry),
sign-in counted through the client's `on_auth` (wired by the CLI/wrappers),
429/5xx retry with backoff, `NotFound` on 404, list/postings pages to `runlog`.
`FakeGateway` and `ReplayGateway` need no network.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Callable, Protocol, runtime_checkable

from zoho_client import ZohoHTTPError

from .budget import Budget
from .runlog import RunLog


class NotFound(Exception):
    """Raised by any `Gateway` on a Zoho 404, or by `ReplayGateway` when asked
    for an id its run folder never saw a 404 for (there is nothing to replay)."""


class PageNotFound(Exception):
    """`ReplayGateway`: no saved page matches this call. The run folder given to
    `--replay` was not the one that made this call, or the call is new since."""


@runtime_checkable
class Gateway(Protocol):
    def get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]: ...


def _param_key(params: dict[str, Any] | None) -> tuple[tuple[str, str], ...]:
    """A hashable, order-independent key for a params dict. Values are stringified
    so `{"page": 1}` and `{"page": "1"}` (as query strings round-trip) match."""
    items = (params or {}).items()
    return tuple(sorted((str(k), str(v)) for k, v in items))


# Endpoints whose every successful response is a list/postings page (even with
# no `page` param). Detail and master-by-id paths are not listed here.
_ALWAYS_LOG_ENDPOINTS = frozenset(
    {
        "/locations",
        "/salespersons",
        "/chartofaccounts/transactions",
    }
)


def _dataset_from_endpoint(endpoint: str) -> str:
    parts = [p for p in endpoint.strip("/").split("/") if p]
    if not parts:
        return "unknown"
    if parts[0] == "chartofaccounts" and "transactions" in parts:
        return "cogs"
    return parts[0].replace("-", "_")


class LiveGateway:
    """Live Zoho Books gateway. Composition root wires `ZohoClient(on_auth=…)`
    so each sign-in is counted on the same `Budget` used here.

    Set `dataset` before a list or postings loop so pages land under that name
    in the run folder; when unset, pages with a `page` param (and the always-log
    endpoints) still save under a name derived from the path.
    """

    def __init__(
        self,
        client: Any,
        budget: Budget,
        runlog: RunLog,
        *,
        sleep: Callable[[float], None] = time.sleep,
        backoff: tuple[float, ...] = (1.0, 2.0, 4.0),
    ) -> None:
        self.client = client
        self.budget = budget
        self.runlog = runlog
        self._sleep = sleep
        self.backoff = backoff
        self.dataset: str | None = None

    def get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        attempt = 0
        while True:
            self.budget.before_call()
            try:
                body = self.client.get(endpoint, params)
            except ZohoHTTPError as exc:
                if exc.status == 404:
                    raise NotFound(f"{endpoint} not found") from exc
                if (exc.status == 429 or exc.status >= 500) and attempt < len(self.backoff):
                    self._sleep(self.backoff[attempt])
                    attempt += 1
                    continue
                raise
            if self._should_log(endpoint, params):
                dataset = self.dataset or _dataset_from_endpoint(endpoint)
                self.runlog.save_page(dataset, endpoint, params, body)
            return body

    def _should_log(self, endpoint: str, params: dict[str, Any] | None) -> bool:
        if self.dataset:
            return True
        if params and "page" in params:
            return True
        return endpoint in _ALWAYS_LOG_ENDPOINTS


class FakeGateway:
    """Fixtures keyed by (endpoint, params). Records every call made, in order,
    for tests to assert against. A fixture value may be an exception instance
    (e.g. `NotFound`) so `id_else_list` masters can exercise the fallback."""

    def __init__(
        self,
        responses: dict[tuple[str, dict[str, Any] | None], dict[str, Any] | BaseException] | None = None,
    ) -> None:
        self._responses: dict[tuple[str, tuple[tuple[str, str], ...]], dict[str, Any] | BaseException] = {}
        for (endpoint, params), response in (responses or {}).items():
            self._responses[(endpoint, _param_key(params))] = response
        self.calls: list[tuple[str, dict[str, Any] | None]] = []

    def add(
        self, endpoint: str, params: dict[str, Any] | None, response: dict[str, Any] | BaseException
    ) -> None:
        self._responses[(endpoint, _param_key(params))] = response

    def get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        self.calls.append((endpoint, params))
        key = (endpoint, _param_key(params))
        if key not in self._responses:
            raise PageNotFound(f"FakeGateway: no fixture for {endpoint} {params!r}")
        value = self._responses[key]
        if isinstance(value, BaseException):
            raise value
        return value


class ReplayGateway:
    """Answers each call from a saved run folder (`output/runs/{run_id}/`), with
    no network. Pages are written by `RunLog.save_page` as
    `{dataset}/page-N.json` holding `{"endpoint", "params", "response"}`; this
    class only needs the (endpoint, params) -> response map that implies, so it
    does not care which dataset a page came from.

    Detail and master calls are not expected here: a replayed run's detail and
    master responses already came from the persistent cache (`output/cache/`)
    during the original live run, and the pipeline's own cache-hit / already-
    stored checks skip calling the gateway for them again. A page genuinely
    missing from the run folder raises `PageNotFound`.
    """

    def __init__(self, run_folder: Path) -> None:
        self.run_folder = Path(run_folder)
        self._pages: dict[tuple[str, tuple[tuple[str, str], ...]], dict[str, Any]] = {}
        self._load()

    def _load(self) -> None:
        import json

        if not self.run_folder.is_dir():
            raise PageNotFound(f"ReplayGateway: no run folder at {self.run_folder}")
        for dataset_dir in sorted(self.run_folder.iterdir()):
            if not dataset_dir.is_dir():
                continue
            for page_file in sorted(dataset_dir.glob("page-*.json")):
                try:
                    saved = json.loads(page_file.read_text(encoding="utf-8"))
                except (OSError, ValueError):
                    continue
                endpoint = saved.get("endpoint")
                params = saved.get("params")
                response = saved.get("response")
                if endpoint is None or response is None:
                    continue
                self._pages[(endpoint, _param_key(params))] = response

    def get(self, endpoint: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        key = (endpoint, _param_key(params))
        if key not in self._pages:
            raise PageNotFound(f"ReplayGateway: no saved page for {endpoint} {params!r} under {self.run_folder}")
        return self._pages[key]
