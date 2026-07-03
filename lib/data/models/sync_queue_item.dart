import 'package:equatable/equatable.dart';

/// Enumerates all sync progression states of local transaction logs.
enum SyncStatus {
  /// Scheduled to upload.
  pending,

  /// Currently uploading via Sync Worker.
  syncing,

  /// Failed due to API limits, network dropout, or validation error.
  failed,

  /// Completed successfully.
  completed,
}

/// Represents an offline-first record pushed to a sync queue box.
///
/// Wraps arbitrary payloads (sales invoice, receipt, return, expense, cash closing)
/// along with metadata (sync state, timestamps, error trace logs) so background workers
/// can process uploads sequentially when network state is favorable.
class SyncQueueItem extends Equatable {
  /// Unique identifier of the sync queue task.
  final String id;

  /// Entity name type to distinguish what parser to invoke (e.g. "invoice", "receipt", "return", "expense", "closing", "customer").
  final String type;

  /// The raw JSON map object of the transaction data to sync.
  final Map<String, dynamic> payload;

  /// Current sync execution state.
  final SyncStatus status;

  /// Error details or message if the sync status is [SyncStatus.failed].
  final String? errorMessage;

  /// Date-time when this sync action was generated.
  final DateTime timestamp;

  /// Creates a new [SyncQueueItem] to manage offline syncing.
  const SyncQueueItem({
    required this.id,
    required this.type,
    required this.payload,
    this.status = SyncStatus.pending,
    this.errorMessage,
    required this.timestamp,
  });

  /// Returns a copied [SyncQueueItem] instance with replaced values for specified fields.
  SyncQueueItem copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    SyncStatus? status,
    String? errorMessage,
    DateTime? timestamp,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Parses local database JSON map into a [SyncQueueItem] task.
  factory SyncQueueItem.fromJson(Map<String, dynamic> json) {
    return SyncQueueItem(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      errorMessage: json['errorMessage'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  /// Formats the task metadata and payload to a database compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'status': status.name,
      'errorMessage': errorMessage,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    type,
    payload,
    status,
    errorMessage,
    timestamp,
  ];
}
