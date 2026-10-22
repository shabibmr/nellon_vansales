"""Detail and master response cache: `output/cache/{folder}/{id}.json`.

Plan: docs/sync/transaction-sync-plan.md, "Code structure" / `cache.py` row,
and "Files on disk". Going forward the cache stores the bare resource object
(the document itself, not Zoho's `{"code", "message", "<resource>": {...}}`
envelope). The reader still unwraps that envelope for one release, so files
written by the scripts this package replaces keep working unchanged.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _unwrap_envelope(obj: Any) -> Any:
    """A Zoho response envelope has `code`/`message` plus exactly one resource
    key. Pull that resource out; anything else (already a bare document) is
    returned unchanged."""
    if not isinstance(obj, dict) or "code" not in obj or "message" not in obj:
        return obj
    candidates = [v for k, v in obj.items() if k not in ("code", "message") and isinstance(v, (dict, list))]
    return candidates[0] if len(candidates) == 1 else obj


class Cache:
    def __init__(self, root: Path) -> None:
        self.root = Path(root)

    def path(self, folder: str, doc_id: str) -> Path:
        return self.root / folder / f"{doc_id}.json"

    def read(self, folder: str, doc_id: str) -> dict[str, Any] | None:
        path = self.path(folder, doc_id)
        if not path.exists():
            return None
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return _unwrap_envelope(raw)

    def write(self, folder: str, doc_id: str, document: dict[str, Any]) -> None:
        """Atomic write: build the `.tmp` file fully, then replace in place."""
        path = self.path(folder, doc_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)

    def is_current(self, folder: str, doc_id: str, last_modified_time: str) -> bool:
        """True when a cached detail exists and its `last_modified_time` matches
        the list row's. The detail call is skipped in that case."""
        doc = self.read(folder, doc_id)
        if doc is None:
            return False
        return doc.get("last_modified_time") == last_modified_time
