"""Run folder: `output/runs/{run_id}/{dataset}/page-N.json` plus `summary.json`.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / `runlog.py` row,
and "Files on disk" (list pages, postings pages, location/salesperson list
pages; kept 30 days). `LiveGateway` calls `save_page` for every list and
postings page it fetches; `gateway.ReplayGateway` reads the same files back.

Each page file holds `{"endpoint", "params", "response"}` so a replay can
match a later call to the exact page that answered it (see `gateway.py`).
"""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

DUBAI = ZoneInfo("Asia/Dubai")
RUN_ID_RE = re.compile(r"^(\d{8})-(\d{6})$")


def new_run_id(now: datetime | None = None) -> str:
    """`YYYYMMDD-HHMMSS` in Asia/Dubai, per the plan."""
    moment = now or datetime.now(DUBAI)
    return moment.strftime("%Y%m%d-%H%M%S")


class RunLog:
    def __init__(self, output_dir: Path, run_id: str) -> None:
        self.output_dir = Path(output_dir)
        self.run_id = run_id
        self.run_folder = self.output_dir / "runs" / run_id
        self._page_counts: dict[str, int] = {}

    def save_page(self, dataset: str, endpoint: str, params: dict[str, Any] | None, response: dict[str, Any]) -> Path:
        dataset_dir = self.run_folder / dataset
        dataset_dir.mkdir(parents=True, exist_ok=True)
        n = self._page_counts.get(dataset, 0) + 1
        self._page_counts[dataset] = n
        path = dataset_dir / f"page-{n}.json"
        path.write_text(
            json.dumps({"endpoint": endpoint, "params": params, "response": response}, ensure_ascii=False),
            encoding="utf-8",
        )
        return path

    def save_summary(self, summary: dict[str, Any]) -> Path:
        self.run_folder.mkdir(parents=True, exist_ok=True)
        path = self.run_folder / "summary.json"
        path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        return path


def cleanup_old_runs(output_dir: Path, days: int = 30, now: datetime | None = None) -> list[Path]:
    """Delete run folders older than `days`, judged by the `run_id` in their
    name (not file mtime, so this stays deterministic in tests). Returns the
    folders removed."""
    import shutil

    moment = now or datetime.now(DUBAI)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=DUBAI)
    runs_dir = Path(output_dir) / "runs"
    if not runs_dir.is_dir():
        return []
    removed = []
    for entry in sorted(runs_dir.iterdir()):
        if not entry.is_dir():
            continue
        match = RUN_ID_RE.match(entry.name)
        if not match:
            continue
        run_started = datetime.strptime(entry.name, "%Y%m%d-%H%M%S").replace(tzinfo=DUBAI)
        if (moment - run_started).days >= days:
            shutil.rmtree(entry)
            removed.append(entry)
    return removed
