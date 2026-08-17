/// Shared load lifecycle for transaction list screens.
///
/// Replaces boolean `isLoading` + nullable error so
/// `loading && error != null` cannot be represented.
enum ListLoadStatus { initial, loading, success, failure }
