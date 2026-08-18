import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// File and Firestore debug logger.
///
/// 1. [log] writes [message] to `debug_log.txt` and calls [debugPrint].
/// 2. On app launch, [flushPreviousSessionIfAny] renames `debug_log.txt` to
///    `debug_log_<timestamp_to_microsecond>.txt` and uploads it to Cloud Firestore
///    as a Document in the collection `debug_logs`.
/// 3. After Document write is complete, the timestamped file is deleted.
/// 4. Meanwhile, the current session logs unhindered to a new `debug_log.txt`.
class DebugFileLogger {
  const DebugFileLogger._();

  static const String _activeLogFileName = 'debug_log.txt';

  /// Android logcat / SurfaceView choke on multi-kilobyte `debugPrint` lines
  /// (BLASTBufferQueue flood, empty `flutter` tag buffer, UI jank). Keep the
  /// console and overlay short; the on-device file may retain a bit more.
  static const int maxConsoleChars = 800;
  static const int maxStoredChars = 8192;

  static Future<void> _tail = Future.value();
  static Directory? _docsDir;
  static final StreamController<String> _logController =
      StreamController<String>.broadcast();

  static Future<Directory?> _getDirectory() async {
    if (_docsDir != null) return _docsDir;
    try {
      return _docsDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _getActiveFile() async {
    final dir = await _getDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_activeLogFileName');
  }

  /// Live stream of formatted log lines, for UI consumers like the debug console.
  static Stream<String> get logStream => _logController.stream;

  /// Truncates [message] for a given sink so huge Zoho JSON never hits logcat.
  static String clip(String message, int maxChars) {
    if (message.length <= maxChars) return message;
    final omitted = message.length - maxChars;
    return '${message.substring(0, maxChars)}…(+$omitted chars)';
  }

  /// Writes [message] to `debug_log.txt` and outputs a clipped line to console.
  static void log(String message) {
    final consoleLine = clip(message, maxConsoleChars);
    debugPrint(consoleLine);
    _logController.add('${DateTime.now().toIso8601String()} $consoleLine');
    _tail = _tail.then((_) => _appendToFile(message)).catchError((_) {});
  }

  static Future<void> _appendToFile(String message) async {
    try {
      final file = await _getActiveFile();
      if (file == null) return;
      final line =
          '${DateTime.now().toIso8601String()} ${clip(message, maxStoredChars)}\n';
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {
      // Logging must never crash the app.
    }
  }

  /// App launch handler:
  /// - Renames `debug_log.txt` to `debug_log_<timestamp_to_6th_millisecond>.txt`.
  /// - Uploads the timestamped log file as a Document to Firestore `debug_logs`.
  /// - Deletes the timestamped file once the write is complete.
  /// - Leaves the current session free to write to a new `debug_log.txt`.
  static Future<void> flushPreviousSessionIfAny() async {
    try {
      final dir = await _getDirectory();
      if (dir == null) return;
      final activeFile = File('${dir.path}/$_activeLogFileName');

      // 1. Rename existing active log file with microsecond timestamp (6 decimal places)
      if (await activeFile.exists() && await activeFile.length() > 0) {
        final timestampStr = DateTime.now()
            .toIso8601String()
            .replaceAll(RegExp(r'[^0-9]'), ''); // YYYYMMDDTHHMMSSffffff
        final renamedFile = File('${dir.path}/debug_log_$timestampStr.txt');
        await activeFile.rename(renamedFile.path);
      }

      // Legacy cleanup: rename previous debug_logs.txt (plural) if it exists from earlier builds
      final legacyFile = File('${dir.path}/debug_logs.txt');
      if (await legacyFile.exists() && await legacyFile.length() > 0) {
        final timestampStr = DateTime.now()
            .toIso8601String()
            .replaceAll(RegExp(r'[^0-9]'), '');
        final renamedLegacy = File('${dir.path}/debug_log_legacy_$timestampStr.txt');
        await legacyFile.rename(renamedLegacy.path);
      }

      // 2. Upload any timestamped log files in the directory
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.uri.pathSegments.last;
          if (fileName.startsWith('debug_log_') && fileName.endsWith('.txt')) {
            await _uploadAndDelete(entity);
          }
        }
      }
    } catch (_) {
      // Startup flush must never crash the application.
    }
  }

  static Future<void> _uploadAndDelete(File file) async {
    try {
      final rawContent = await file.readAsString();
      final lines = rawContent
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        await file.delete();
        return;
      }

      String appVersion = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      final fileName = file.uri.pathSegments.last;
      debugPrint('[DebugFileLogger] 📤 Uploading $fileName (${lines.length} lines) to Firestore...');

      // Send to Cloud Firestore as a Document in the collection debug_logs
      await FirebaseFirestore.instance.collection('debug_logs').add({
        'created_at': FieldValue.serverTimestamp(),
        'flushed_at': DateTime.now().toIso8601String(),
        'source_file': fileName,
        'app_version': appVersion,
        'line_count': lines.length,
        'lines': lines,
      });

      // Delete the timestamped file once Document write is complete
      await file.delete();
      debugPrint('[DebugFileLogger] ✅ Successfully uploaded $fileName to Firestore and deleted local file.');
    } catch (e) {
      debugPrint('[DebugFileLogger] ❌ Failed to upload $file to Firestore: $e');
      // If offline or write fails, the timestamped file is retained for next launch
    }
  }

  /// Returns the current active log file path.
  static Future<String> getActiveFilePath() async {
    final file = await _getActiveFile();
    return file?.path ?? '';
  }

  /// Reads the current content of the active log file `debug_log.txt`.
  static Future<String> readActiveLog() async {
    try {
      final file = await _getActiveFile();
      if (file != null && await file.exists()) {
        return await file.readAsString();
      }
      return '';
    } catch (e) {
      return 'Error reading log file: $e';
    }
  }

  /// Clears the active log file.
  static Future<void> clearActiveLog() async {
    try {
      final file = await _getActiveFile();
      if (file != null && await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Manually flushes and uploads current active log to Firestore `debug_logs`.
  /// Returns a status summary map with keys: 'success', 'docId', 'lineCount', 'fileName', 'error'.
  static Future<Map<String, dynamic>> uploadToFirestoreNow() async {
    try {
      final dir = await _getDirectory();
      if (dir == null) {
        return {'success': false, 'error': 'Directory unavailable'};
      }
      final activeFile = File('${dir.path}/$_activeLogFileName');

      if (!await activeFile.exists() || (await activeFile.length()) == 0) {
        // If file is empty, write a timestamp entry first so the document is valid under Firestore rules
        await _appendToFile('Manual Firestore test upload timestamp.');
      }

      final timestampStr = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), ''); // YYYYMMDDTHHMMSSffffff
      final fileName = 'debug_log_$timestampStr.txt';
      final renamedFile = File('${dir.path}/$fileName');
      await activeFile.rename(renamedFile.path);

      final rawContent = await renamedFile.readAsString();
      final lines = rawContent
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        lines.add('${DateTime.now().toIso8601String()} [Test Log Entry]');
      }

      String appVersion = '1.0.0+7';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      final docRef = await FirebaseFirestore.instance.collection('debug_logs').add({
        'created_at': FieldValue.serverTimestamp(),
        'flushed_at': DateTime.now().toIso8601String(),
        'source_file': fileName,
        'app_version': appVersion,
        'line_count': lines.length,
        'lines': lines,
      });

      await renamedFile.delete();
      return {
        'success': true,
        'docId': docRef.id,
        'lineCount': lines.length,
        'fileName': fileName,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
