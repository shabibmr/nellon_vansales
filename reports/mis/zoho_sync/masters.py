"""Master specs and `ensure(run, kind, id)`.

Plan: docs/sync/transaction-sync-plan.md, "Master scripts". Differences between
masters live in `MasterSpec`; `ensure` has no `if kind == …` branches beyond
looking up the spec.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

from zoho_client import ZohoClient

from . import mapping
from .budget import Budget
from .cache import Cache
from .context import Run
from .gateway import LiveGateway, NotFound
from .runlog import RunLog, cleanup_old_runs, new_run_id
from .store_db import DbStore

Lookup = Literal["id", "list", "id_else_list"]
Mapper = Callable[[dict[str, Any]], Any]


class WrongType(Exception):
    """Payload `contact_type` (or similar) does not match this master kind."""


class UnknownMaster(KeyError):
    """No `MasterSpec` registered for this kind."""


@dataclass(frozen=True)
class MasterSpec:
    kind: str
    lookup: Lookup
    path: str | None
    list_path: str | None
    response_key: str
    list_key: str | None
    id_field: str
    type_check: Callable[[dict[str, Any]], None] | None
    table: str
    mapper: Mapper
    deps: tuple[tuple[str, str], ...]  # (payload_field, master_kind)
    cache_folder: str | None
    update_cols: tuple[str, ...] | None
    child_table: str | None = None
    child_parent_col: str | None = None


def _require_contact_type(expected: str) -> Callable[[dict[str, Any]], None]:
    def check(payload: dict[str, Any]) -> None:
        actual = str(payload.get("contact_type") or "").strip().lower()
        if actual != expected:
            raise WrongType(f"contact_type={actual!r} is not {expected!r}")

    return check


ACCOUNT_UPDATE_COLS = (
    "account_code",
    "account_name",
    "account_type",
    "parent_account_id",
    "parent_account_name",
    "is_active",
    "last_modified_time",
)

SPECS: dict[str, MasterSpec] = {
    "customer": MasterSpec(
        kind="customer",
        lookup="id",
        path="/contacts/{id}",
        list_path=None,
        response_key="contact",
        list_key=None,
        id_field="contact_id",
        type_check=_require_contact_type("customer"),
        table="customers",
        mapper=mapping.map_customer,
        deps=(),
        cache_folder="contacts",
        update_cols=None,
    ),
    "vendor": MasterSpec(
        kind="vendor",
        lookup="id",
        path="/contacts/{id}",
        list_path=None,
        response_key="contact",
        list_key=None,
        id_field="contact_id",
        type_check=_require_contact_type("vendor"),
        table="vendors",
        mapper=mapping.map_vendor,
        deps=(),
        cache_folder="contacts",
        update_cols=None,
    ),
    "item": MasterSpec(
        kind="item",
        lookup="id",
        path="/items/{id}",
        list_path=None,
        response_key="item",
        list_key=None,
        id_field="item_id",
        type_check=None,
        table="items",
        mapper=mapping.map_item,
        deps=(("account_id", "account"), ("purchase_account_id", "account")),
        cache_folder="items",
        update_cols=None,
        child_table="item_units",
        child_parent_col="item_id",
    ),
    "account": MasterSpec(
        kind="account",
        lookup="id",
        path="/chartofaccounts/{id}",
        list_path=None,
        response_key="chart_of_account",
        list_key=None,
        id_field="account_id",
        type_check=None,
        table="accounts",
        mapper=mapping.map_account,
        deps=(("parent_account_id", "account"),),
        cache_folder="chartofaccounts",
        update_cols=ACCOUNT_UPDATE_COLS,
    ),
    "location": MasterSpec(
        kind="location",
        lookup="list",
        path=None,
        list_path="/locations",
        response_key="location",
        list_key="locations",
        id_field="location_id",
        type_check=None,
        table="locations",
        mapper=mapping.map_location,
        deps=(),
        cache_folder=None,
        update_cols=None,
    ),
    "salesperson": MasterSpec(
        kind="salesperson",
        lookup="id_else_list",
        path="/salespersons/{id}",
        list_path="/salespersons",
        response_key="salesperson",
        list_key="salespersons",
        id_field="salesperson_id",
        type_check=None,
        table="salespersons",
        mapper=mapping.map_salesperson,
        deps=(),
        cache_folder="salespersons",
        update_cols=None,
    ),
}


def _unwrap(body: dict[str, Any], key: str) -> dict[str, Any]:
    if key in body and isinstance(body[key], dict):
        return body[key]
    # Already a bare resource (fixtures / cache).
    return body


def _find_in_list(body: dict[str, Any], list_key: str, id_field: str, doc_id: str) -> dict[str, Any]:
    rows = body.get(list_key) or []
    for row in rows:
        if str(row.get(id_field) or "") == str(doc_id):
            return row
    raise NotFound(f"{list_key}: no row with {id_field}={doc_id}")


def _fetch_payload(run: Run, spec: MasterSpec, doc_id: str) -> dict[str, Any]:
    if spec.lookup == "id":
        assert spec.path is not None
        body = run.gateway.get(spec.path.format(id=doc_id))
        return _unwrap(body, spec.response_key)

    if spec.lookup == "list":
        assert spec.list_path is not None and spec.list_key is not None
        body = run.gateway.get(spec.list_path)
        return _find_in_list(body, spec.list_key, spec.id_field, doc_id)

    # id_else_list
    assert spec.path is not None and spec.list_path is not None and spec.list_key is not None
    try:
        body = run.gateway.get(spec.path.format(id=doc_id))
        return _unwrap(body, spec.response_key)
    except NotFound:
        body = run.gateway.get(spec.list_path)
        return _find_in_list(body, spec.list_key, spec.id_field, doc_id)


def ensure(run: Run, kind: str, doc_id: str) -> None:
    """Load one master into the store. No-op when already memoized or stored."""
    doc_id = str(doc_id or "").strip()
    if not doc_id:
        raise ValueError(f"ensure: blank id for kind {kind!r}")

    spec = SPECS.get(kind)
    if spec is None:
        raise UnknownMaster(kind)

    memo_key = (kind, doc_id)
    if memo_key in run.master_memo or run.store.has(spec.table, doc_id):
        run.master_memo.add(memo_key)
        return

    payload: dict[str, Any] | None = None
    if spec.cache_folder:
        payload = run.cache.read(spec.cache_folder, doc_id)

    fetched = payload is None
    if payload is None:
        payload = _fetch_payload(run, spec, doc_id)

    if spec.type_check is not None:
        spec.type_check(payload)

    # Cache only a payload that passed the type check, and only when it came from Zoho.
    if fetched and spec.cache_folder:
        run.cache.write(spec.cache_folder, doc_id, payload)

    for field, dep_kind in spec.deps:
        dep_id = str(payload.get(field) or "").strip()
        if dep_id:
            ensure(run, dep_kind, dep_id)

    mapped = spec.mapper(payload)
    if spec.child_table:
        header, children = mapped
        update = list(spec.update_cols) if spec.update_cols is not None else None
        run.store.upsert(spec.table, [header], update_cols=update)
        run.store.replace_lines(spec.child_table, spec.child_parent_col or spec.id_field, doc_id, children)
    else:
        update = list(spec.update_cols) if spec.update_cols is not None else None
        run.store.upsert(spec.table, [mapped], update_cols=update)

    run.master_memo.add(memo_key)


def build_live_run(*, yes_live: bool, max_calls: int | None = None, db_name: str | None = None) -> Run:
    """Composition root for the six `fetch_*.py` wrappers and `python -m zoho_sync fetch`."""
    if not yes_live:
        raise SystemExit("refuses to call Zoho without --yes-live")

    from seed_common import connect
    import os

    base = Path(__file__).resolve().parent.parent
    output_dir = base / "output"
    cleanup_old_runs(output_dir)
    run_id = new_run_id()
    budget = Budget(output_dir / "zoho_budget_stamp", interval=20.0, max_calls=max_calls)
    client = ZohoClient(on_auth=budget.before_call)
    runlog = RunLog(output_dir, run_id)
    conn = connect(db_name or os.getenv("MIS_DB_NAME", "zoho-koyson"))
    return Run(
        gateway=LiveGateway(client, budget, runlog),
        store=DbStore(conn),
        cache=Cache(output_dir / "cache"),
        runlog=runlog,
        run_id=run_id,
        mode="live",
    )
