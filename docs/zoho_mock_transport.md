# Zoho mock transport — removed

The in-app Zoho sandbox (`lib/data/services/zoho_mock/`, mock flags, `_MockModeBanner`, `MockLiveSwitchTile`) has been removed.

All `ZohoApiClient` HTTP calls go to live Zoho Books / Inventory. Payload shaping (`ZohoPayloadMapper`, location inject, expense-account resolve) is unchanged.

`fetchRoutes()` remains an app-local list — Zoho has no Route entity.

Mapper coverage lives in `test/zoho_payload_mapper_test.dart`. Test doubles (`Fake*`, mockito) stay in `test/` only.
