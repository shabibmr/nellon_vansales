"""`Run`: everything one sync run carries, passed instead of a growing argument list.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / `context.py` row,
and the "Modules take a `Run` context" rule.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Literal

from .cache import Cache
from .gateway import Gateway
from .runlog import RunLog
from .store import Store

Mode = Literal["live", "replay", "test"]


@dataclass
class Run:
    gateway: Gateway
    store: Store
    cache: Cache
    runlog: RunLog
    run_id: str
    mode: Mode = "test"
    clock: Callable[[], datetime] = field(default=datetime.now)

    # Per-run memo for `masters.ensure`: (kind, id) -> True once that master is
    # known stored or already written this run, so a repeated id on the same
    # run makes no second Zoho call. Cleared by starting a new `Run`.
    master_memo: set[tuple[str, str]] = field(default_factory=set)

    def now(self) -> datetime:
        return self.clock()
