---
name: context7-bloc-dio
description: Fetch current flutter_bloc and Dio docs via Context7 before writing BLoC/Cubit, interceptors, or HTTP client code. Use when editing blocs, cubits, ZohoApiClient, Dio interceptors, or answering API questions about flutter_bloc, bloc, or dio.
---

# Context7: flutter_bloc + Dio

This app uses `flutter_bloc` ^9.1.1 / `bloc` ^9.2.1 and `dio` ^5.4.0 (`pubspec.yaml`). Do not rely on training-data APIs for these packages.

## When to use

- Adding or changing a BLoC, Cubit, event, or state
- Transformer / `bloc_concurrency` / hydration questions
- Dio interceptors, token refresh, `FormData`, cancel tokens, or `DioException`
- Anything that touches `lib/data/services/zoho_api_client.dart` HTTP plumbing

## How to query

Use the Context7 MCP tools (`resolve-library-id` only if an ID below fails; otherwise skip resolve):

| Package | Context7 library ID | Typical query topics |
|---|---|---|
| `bloc` / `flutter_bloc` | `/felangel/bloc` | `Bloc`, `Cubit`, `BlocProvider`, `BlocListener`, `Equatable` states, `emit` after close, transformers |
| `dio` | `/cfug/dio` | `InterceptorsWrapper`, 401 retry, `DioException`, `Options`, `CancelToken`, `BaseOptions` |

Call `query-docs` with:

- `libraryId`: one of the IDs above
- `query`: the concrete API or pattern you need
- Prefer version-aware results that match ^9.x (bloc) and ^5.x (dio)

## Project constraints after the docs come back

- UI talks to domain interfaces only; Dio stays in `data/`.
- `ZohoApiClient` already owns the OAuth interceptor and live `_dio.get/post/put`. Do not add an in-app Zoho mock transport.
- Existing BLoCs follow event/state files next to the bloc. Match that layout.
- Empty remote Zoho credentials must not wipe a working cache (`updateCredentials` fail-open).
