/// Coerces untyped JSON / Hive values under `strict-casts`.
String jsonString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

String? jsonStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

double jsonDouble(Object? value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

int jsonInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

bool jsonBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  return fallback;
}

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

List<dynamic> jsonList(Object? value) {
  if (value is List) return value;
  return const [];
}

DateTime jsonDate(Object? value, [DateTime? fallback]) {
  if (value is DateTime) return value;
  if (value != null) {
    final parsed = DateTime.tryParse(value.toString());
    if (parsed != null) return parsed;
  }
  return fallback ?? DateTime.now();
}
