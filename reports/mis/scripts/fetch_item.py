"""Fetch one Zoho Books item (and item_units) into MariaDB. Requires --yes-live."""

from __future__ import annotations

import argparse
import sys

from zoho_sync.masters import ensure, build_live_run


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("item_id")
    p.add_argument("--yes-live", action="store_true")
    p.add_argument("--max-calls", type=int, default=None)
    args = p.parse_args(argv)
    run = build_live_run(yes_live=args.yes_live, max_calls=args.max_calls)
    ensure(run, "item", args.item_id)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(1)
