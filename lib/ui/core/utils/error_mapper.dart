import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:van_sales/data/services/error_classification.dart';
import 'package:van_sales/domain/utils/stock_rules.dart';

/// Converts any caught error or exception object into a clean, human-readable
/// string suitable for display in UI elements (snackbars, dialogs, error views).
String userFacingMessage(
  Object? error, {
  String fallback = 'Something went wrong',
}) {
  if (error == null) return fallback;

  if (error is InsufficientStockException) {
    return error.toString();
  }

  if (error is TimeoutException) {
    return 'Operation timed out. Please try again.';
  }

  if (error is SocketException) {
    return 'Network connection error. Please check your internet connection.';
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return 'Connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        return 'Network connection error. Please check your internet connection.';
      case DioExceptionType.badResponse:
        final fromBody = zohoMessageFromResponseData(error.response?.data);
        if (fromBody != null && fromBody.isNotEmpty) {
          return _cleanPrefixes(fromBody, fallback: fallback);
        }
        final statusCode = error.response?.statusCode;
        if (statusCode != null) {
          if (statusCode >= 500) {
            return 'Server error ($statusCode). Please try again later.';
          }
          if (statusCode == 404) {
            return 'Requested resource was not found.';
          }
          if (statusCode == 401 || statusCode == 403) {
            return 'Access denied. Please check your permissions.';
          }
        }
        break;
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Security certificate validation failed.';
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Network connection error. Please check your internet connection.';
        }
        break;
    }

    if (error.message != null && error.message!.isNotEmpty) {
      final cleanedMsg = _cleanPrefixes(error.message!, fallback: fallback);
      if (cleanedMsg != fallback) {
        return cleanedMsg;
      }
    }
  }

  final rawStr = error.toString();
  return _cleanPrefixes(rawStr, fallback: fallback);
}

String _cleanPrefixes(String raw, {required String fallback}) {
  var s = raw.trim();
  if (s.isEmpty) return fallback;

  bool modified = true;
  while (modified) {
    modified = false;

    final dioMatch = RegExp(
      r'^DioException\s*(?:\[[^\]]*\])?:\s*',
      caseSensitive: false,
    ).firstMatch(s);
    if (dioMatch != null) {
      s = s.substring(dioMatch.end).trim();
      modified = true;
    }

    final excMatch = RegExp(
      r'^(?:[A-Za-z0-9_]*Exception|[A-Za-z0-9_]*Error|Failed):\s*',
      caseSensitive: false,
    ).firstMatch(s);
    if (excMatch != null) {
      s = s.substring(excMatch.end).trim();
      modified = true;
    }
  }

  if (s.isEmpty) return fallback;
  return s;
}
