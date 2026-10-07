// Small helpers that make parsing Binance JSON safe.
//
// Binance mixes types across endpoints (`"100"`, `100`, `100.0`) so every model
// parses through these guards instead of brittle casts.

import 'dart:convert';

/// Returns [value] as `double`, tolerating strings, ints and nulls.
double asDouble(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

/// Returns [value] as `int`, tolerating strings and doubles.
int asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.toInt() ?? fallback;
  }
  return fallback;
}

/// Returns [value] as `String`, tolerating numbers.
String asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

/// Returns [value] as `bool`, tolerating the `"true"` / `1` variants.
bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return fallback;
}

/// Safely walks a JSON object into a `Map<String, dynamic>`.
Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

/// Safely converts a JSON array of objects into a typed list.
List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.map(asMap).toList(growable: false);
}

/// Decodes a HTTP body into a JSON object, falling back to `{'raw': body}`.
Map<String, dynamic> decodeJsonObject(String body) {
  if (body.isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      return asMap(decoded);
    }
    return <String, dynamic>{'raw': decoded};
  } on FormatException {
    // Not JSON at all (HTML error page, Cloudflare block, ...).
    return <String, dynamic>{'raw': body};
  }
}

/// Decodes a HTTP body that is expected to be a JSON array.
List<Object?> decodeJsonArray(String body) {
  if (body.isEmpty) {
    return const <Object?>[];
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded;
    }
    return <Object?>[decoded];
  } on FormatException {
    return <Object?>[
      <String, dynamic>{'raw': body},
    ];
  }
}

