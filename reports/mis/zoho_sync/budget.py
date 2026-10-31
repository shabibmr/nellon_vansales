"""Call pacing and the per-run call cap.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / `budget.py` row,
and "How often, and how long" (3 calls a minute = 20s between calls).

`LiveGateway` (task 2+) calls `before_call()` before every Zoho request,
including the sign-in itself. The pacing stamp lives in a file under `output/`
so `fetch_*.py` wrappers run alongside the runner share the same 3-per-minute
cap, even across separate processes; an `fcntl` exclusive lock serializes the
read-wait-write. `--max-calls` is per invocation, so it is kept in memory only.
"""

from __future__ import annotations

import fcntl
import time
from pathlib import Path
from typing import Callable


class BudgetExceeded(Exception):
    """Raised by `Budget.before_call()` once `max_calls` is reached."""


class Budget:
    def __init__(
        self,
        stamp_path: Path,
        interval: float = 20.0,
        max_calls: int | None = None,
        sleep: Callable[[float], None] = time.sleep,
        now: Callable[[], float] = time.time,
    ) -> None:
        self.stamp_path = Path(stamp_path)
        self.interval = interval
        self.max_calls = max_calls
        self._sleep = sleep
        self._now = now
        self.calls_made = 0

    def before_call(self) -> None:
        """Block until this call may go out, then count it. Raises `BudgetExceeded`
        before counting it, if `max_calls` would be exceeded."""
        if self.max_calls is not None and self.calls_made >= self.max_calls:
            raise BudgetExceeded(f"budget: max_calls={self.max_calls} reached")
        self._wait_for_pace()
        self.calls_made += 1

    def _wait_for_pace(self) -> None:
        if self.interval <= 0:
            return
        self.stamp_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.stamp_path, "a+") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                f.seek(0)
                content = f.read().strip()
                last = float(content) if content else 0.0
                now = self._now()
                wait = self.interval - (now - last)
                if wait > 0:
                    self._sleep(wait)
                    now = self._now()
                f.seek(0)
                f.truncate()
                f.write(repr(now))
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)
