# UI Layer Architecture & Dependency Injection Rules

## Composition-Root Rule
- **No `sl<>` inside `build()` or leaf widgets**: Resolve dependencies only in page `open` static methods, `BlocProvider.create`, or app-level `MultiBlocProvider` / `MultiRepositoryProvider`.
- **UI Layer Layering**: Widgets must depend on **domain repositories and interfaces**, not raw data services (`ZohoApiClient`, `HiveDatabaseService`, `SyncWorker`).

## GetIt Test Harness
- Unit/widget tests can reset and re-register GetIt instances using:
  ```dart
  await sl.reset();
  // Register mocks or fakes for test cases
  ```
