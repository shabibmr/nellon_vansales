"""CLI: `python -m zoho_sync run|fetch|seed-watermarks`.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / CLI. Task 8.

- `run` — seven-list pipeline. Live only with `--yes-live`; `--replay RUN_ID`
  reads a saved run folder with no network. Otherwise refuses any call.
  `--max-calls N` caps one live run. Pending is always retried (pipeline).
- `fetch KIND ID` — one master, same as the `fetch_*.py` wrappers.
- `seed-watermarks` — first-run seed from each header table's max
  `last_modified_time`. No Zoho call.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

from .budget import Budget
from .cache import Cache
from .context import DUBAI, Run
from .gateway import LiveGateway, ReplayGateway
from .masters import SPECS, UnknownMaster, build_live_run, ensure
from .pipeline import KIND_BY_DATASET, run_all
from .runlog import RunLog, cleanup_old_runs, new_run_id
from .specs import ALL_SPECS
from .store_db import DbStore
from . import watermark as wm


def _mis_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _output_dir() -> Path:
    return _mis_root() / "output"


def _db_store(db_name: str | None = None) -> DbStore:
    from seed_common import connect

    name = db_name or os.getenv("MIS_DB_NAME", "zoho-koyson")
    return DbStore(connect(name))


def _header_tables() -> dict[str, str]:
    return {spec.dataset: spec.header_table for spec in ALL_SPECS}


def build_run(
    *,
    yes_live: bool = False,
    replay: str | None = None,
    max_calls: int | None = None,
    db_name: str | None = None,
) -> Run:
    """Composition root for `run`. LiveGateway only with `--yes-live`;
    ReplayGateway for `--replay`; otherwise refuse."""
    if yes_live and replay:
        raise SystemExit("use either --yes-live or --replay, not both")
    if not yes_live and not replay:
        raise SystemExit("refuses to call Zoho without --yes-live (or pass --replay RUN_ID)")

    output_dir = _output_dir()
    cleanup_old_runs(output_dir)
    store = _db_store(db_name)
    cache = Cache(output_dir / "cache")

    if replay:
        source = output_dir / "runs" / replay
        if not source.is_dir():
            raise SystemExit(f"no run folder at {source}")
        run_id = new_run_id()
        return Run(
            gateway=ReplayGateway(source),
            store=store,
            cache=cache,
            runlog=RunLog(output_dir, run_id),
            run_id=run_id,
            mode="replay",
        )

    started_at = datetime.now(DUBAI)
    run_id = new_run_id(started_at)
    budget = Budget(output_dir / "zoho_budget_stamp", interval=20.0, max_calls=max_calls)
    from zoho_client import ZohoClient

    client = ZohoClient(on_auth=budget.before_call)
    runlog = RunLog(output_dir, run_id)
    return Run(
        gateway=LiveGateway(client, budget, runlog),
        store=store,
        cache=cache,
        runlog=runlog,
        run_id=run_id,
        mode="live",
        started_at=started_at,
    )


def cmd_run(args: argparse.Namespace) -> int:
    run = build_run(
        yes_live=args.yes_live,
        replay=args.replay,
        max_calls=args.max_calls,
        db_name=args.db,
    )
    summary = run_all(run)
    print(json.dumps(summary, ensure_ascii=False, indent=2, default=str))
    if any(ds.get("error") for ds in summary.get("datasets", {}).values()):
        return 1
    return 0


def cmd_fetch(args: argparse.Namespace) -> int:
    kind = args.kind
    if kind not in SPECS:
        raise SystemExit(f"unknown kind {kind!r}; choose from: {', '.join(sorted(SPECS))}")
    run = build_live_run(yes_live=args.yes_live, max_calls=args.max_calls, db_name=args.db)
    ensure(run, kind, args.id)
    print(f"{kind} {args.id} ok")
    return 0


def cmd_seed_watermarks(args: argparse.Namespace) -> int:
    store = _db_store(args.db)
    seeded = wm.seed(store, _header_tables(), kinds=KIND_BY_DATASET)
    print(json.dumps(seeded, ensure_ascii=False, indent=2, default=str))
    empty = [dataset for dataset, value in seeded.items() if not value]
    if empty:
        print(
            f"no last_modified_time yet for: {', '.join(empty)} "
            "(those datasets still refuse to list until rows exist)",
            file=sys.stderr,
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m zoho_sync", description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="sync the seven document lists")
    run_p.add_argument("--yes-live", action="store_true", help="call Zoho through LiveGateway")
    run_p.add_argument("--replay", metavar="RUN_ID", help="replay output/runs/RUN_ID with no network")
    run_p.add_argument("--max-calls", type=int, default=None, help="cap Zoho calls for this live run")
    run_p.add_argument("--db", default=None, help="MariaDB database name (default MIS_DB_NAME / zoho-koyson)")
    run_p.set_defaults(func=cmd_run)

    fetch_p = sub.add_parser("fetch", help="ensure one master (customer|vendor|item|account|location|salesperson)")
    fetch_p.add_argument("kind", choices=sorted(SPECS))
    fetch_p.add_argument("id", help="Zoho id")
    fetch_p.add_argument("--yes-live", action="store_true")
    fetch_p.add_argument("--max-calls", type=int, default=None)
    fetch_p.add_argument("--db", default=None)
    fetch_p.set_defaults(func=cmd_fetch)

    seed_p = sub.add_parser("seed-watermarks", help="seed sync_state from stored header last_modified_time")
    seed_p.add_argument("--db", default=None)
    seed_p.set_defaults(func=cmd_seed_watermarks)

    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except UnknownMaster as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)
    except SystemExit:
        raise
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)
