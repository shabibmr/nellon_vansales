import 'package:dio/dio.dart';

/// Normalizes Dio request paths for mock routing (relative Books paths and
/// absolute Inventory URLs collapse to a single `/…` form).
class ZohoMockPath {
  ZohoMockPath._();

  static String normalize(RequestOptions options) {
    var path = options.path;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final uri = Uri.parse(path);
      path = uri.path;
      const prefixes = ['/books/v3', '/inventory/v1'];
      for (final p in prefixes) {
        if (path.startsWith(p)) {
          path = path.substring(p.length);
          break;
        }
      }
    }
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}
