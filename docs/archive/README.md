# Documentation Archive

This directory contains historical documentation, completed migration plans, and
milestone progress reports that are preserved for reference but are no longer
active operational or architectural specifications.

**Nothing in here is a live backlog.** Every task list below is either complete
or explicitly cancelled, and each file carries a status banner explaining what
actually shipped. For open work see `docs/ENTERPRISE_READINESS.md` and
`reports/2026-08-17_flutter_dart_code_review.md`.

## Archived Documents

| File | Description | Original Date / Milestone |
|------|-------------|---------------------------|
| [bloc_migration_plan.md](bloc_migration_plan.md) | Original architectural plan for migrating from `setState` to BLoC/Cubit across the app. | June 2026 |
| [bloc_migration_tasks.md](bloc_migration_tasks.md) | Detailed task checklist and status tracking for the BLoC migration. | June–July 2026 |
| [migration_handoff.md](migration_handoff.md) | Final completion handoff report verifying `setState` migration complete (155/155 tests passing). | July 15, 2026 |
| [migration_status.md](migration_status.md) | Interim migration status notes and progress tracking. | July 2026 |
| [master_sync_report.md](master_sync_report.md) | Milestone 1 plan and change report for offline Hive caching and Zoho master data syncing. | May 24, 2026 |
| [sales_return_dialog_design.md](sales_return_dialog_design.md) | Task 0.4 design document for converting the `SalesReturnDialog` to BLoC/Cubit. | June 2026 |
| [sales-repository-split-plan.md](sales-repository-split-plan.md) | Analysis and plan for breaking the 51-member `SalesRepository` into per-concept repositories. **Shipped** — `SalesRepository` no longer exists. | Archived Sept 7, 2026 |
| [stock-transfer-architecture-review.md](stock-transfer-architecture-review.md) | Architecture review of `lib/ui/features/stock_transfer/`; three deepening candidates. **All three implemented.** | Archived Sept 7, 2026 |
| [stock-transfer-tasks.md](stock-transfer-tasks.md) | Task list derived from the review above. Checkboxes reconciled against the code at archive time. | Archived Sept 7, 2026 |
| [online-first-save-plan.md](online-first-save-plan.md) | Plan for making saves online-first (queue only on Zoho failure). **Shipped** — now the app's save path, documented in `CLAUDE.md`. | Archived Sept 7, 2026 |
| [online-first-save-tasks.md](online-first-save-tasks.md) | Task list for the above. All done except the two cancelled cash-closing items. | Archived Sept 7, 2026 |
| [server-config-logging-plan.md](server-config-logging-plan.md) | One-off plan for logging the Firestore `server_config/zoho` document reaching a phone. Superseded by `AppLogger`. Was `DEBUGGING_PLAN.md` at the repo root. | Archived Sept 7, 2026 |

## Loose ends carried out of archived work

These were part of archived programs but never completed. They are recorded here
so archiving does not silently drop them.

- **`CONTEXT.md` was never created.** Three tasks in
  [stock-transfer-tasks.md](stock-transfer-tasks.md) asked for a project
  vocabulary file to record the terms `StockTransferRepository`,
  `StockTransferEditorView`, and `StockTransferQtyDialog`. `CLAUDE.md` covers
  some of this ground; decide whether `CONTEXT.md` is still wanted or drop the
  requirement.
- **Cash closing never moved to `submitOrEnqueue`.** T1.6 and T3.4 of the
  online-first-save program were cancelled, so cash closing still uses the older
  save-then-enqueue path while every other transaction type is online-first.
