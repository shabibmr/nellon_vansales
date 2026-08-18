import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/services/debug_file_logger.dart';
import '../../../core/theme/app_theme.dart';

/// Test page/widget for validating DebugFileLogger local file writing
/// and Cloud Firestore upload functionality.
class DebugLoggerTestPage extends StatefulWidget {
  const DebugLoggerTestPage({super.key});

  @override
  State<DebugLoggerTestPage> createState() => _DebugLoggerTestPageState();
}

class _DebugLoggerTestPageState extends State<DebugLoggerTestPage> {
  String _statusMessage = 'Ready. Click a button below to test.';
  bool? _isSuccess;
  bool _isUploading = false;
  String _logContent = '';
  int _lineCount = 0;
  String _filePath = '';
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _refreshLogStats();
  }

  Future<void> _refreshLogStats() async {
    final path = await DebugFileLogger.getActiveFilePath();
    final content = await DebugFileLogger.readActiveLog();
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (mounted) {
      setState(() {
        _filePath = path;
        _logContent = content;
        _lineCount = lines.length;
      });
    }
  }

  Future<void> _onWriteTimestamp() async {
    final timestamp = DateTime.now().toIso8601String();
    final testMsg = '⏱️ [Test Timestamp] $timestamp';
    DebugFileLogger.log(testMsg);

    await _refreshLogStats();
    if (mounted) {
      setState(() {
        _statusMessage = '✅ Wrote timestamp to file: $timestamp';
        _isSuccess = true;
      });
    }
  }

  Future<void> _onCopyToFirestore() async {
    setState(() {
      _isUploading = true;
      _statusMessage = '📤 Uploading log file to Firestore collection "debug_logs"...';
      _isSuccess = null;
    });

    final result = await DebugFileLogger.uploadToFirestoreNow();
    await _refreshLogStats();

    if (mounted) {
      setState(() {
        _isUploading = false;
        if (result['success'] == true) {
          _statusMessage =
              '✅ Successfully copied to Firestore!\n'
              '• Document ID: ${result['docId']}\n'
              '• Uploaded: ${result['lineCount']} lines\n'
              '• File: ${result['fileName']}';
          _isSuccess = true;
        } else {
          _statusMessage = '❌ Firestore upload failed:\n${result['error']}';
          _isSuccess = false;
        }
      });
    }
  }

  Future<void> _onClearFile() async {
    await DebugFileLogger.clearActiveLog();
    await _refreshLogStats();
    if (mounted) {
      setState(() {
        _statusMessage = '🗑️ Local active log file cleared.';
        _isSuccess = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B26) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2D3748) : const Color(0xFFCBD5E1),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.science_outlined,
                  size: 20,
                  color: AppTheme.primaryIndigo,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Debug Logger Test Panel',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      'File: ${_filePath.split(Platform.pathSeparator).last} ($_lineCount lines)',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh Log Stats',
                onPressed: _refreshLogStats,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                tooltip: 'Clear Log File',
                onPressed: _onClearFile,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(
                  _showLogs ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                tooltip: _showLogs ? 'Hide Logs' : 'View Logs',
                onPressed: () => setState(() => _showLogs = !_showLogs),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Action Buttons
          Row(
            children: [
              // Button 1: Write Timestamp
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _onWriteTimestamp,
                  icon: const Icon(Icons.access_time_filled, size: 16),
                  label: const Text(
                    'Write Timestamp',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Button 2: Copy to Firestore
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _onCopyToFirestore,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: Text(
                    _isUploading ? 'Uploading...' : 'Copy to Firestore',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488), // Teal/Emerald
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Status Feedback Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isSuccess == true
                  ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7))
                  : _isSuccess == false
                      ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2))
                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isSuccess == true
                    ? Colors.green.shade400
                    : _isSuccess == false
                        ? Colors.red.shade400
                        : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
                color: _isSuccess == true
                    ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF166534))
                    : _isSuccess == false
                        ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                        : (isDark ? Colors.grey[300] : const Color(0xFF334155)),
              ),
            ),
          ),

          // Collapsible Log Viewer Box
          if (_showLogs) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _logContent.isEmpty ? '// No log entries in debug_log.txt' : _logContent,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF38BDF8), // Light Sky Blue
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
