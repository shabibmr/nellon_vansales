import 'package:equatable/equatable.dart';

enum SyncStatus { pending, syncing, failed, completed }

class SyncQueueItem extends Equatable {
  final String id;
  final String type; // 'invoice', 'receipt', 'return', 'expense', 'closing', 'customer'
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const SyncQueueItem({
    required this.id,
    required this.type,
    required this.payload,
    this.status = SyncStatus.pending,
    this.errorMessage,
    required this.timestamp,
  });

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
  List<Object?> get props => [id, type, payload, status, errorMessage, timestamp];
}
