import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LoggerService {
  static File? _logFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/pocket_query_debug.log');
      _initialized = true;
      await log('=== POCKET QUERY LOGGER INITIALIZED ===', level: 'SYSTEM');
    } catch (e) {
      debugPrint('Failed to initialize LoggerService: $e');
    }
  }

  static Future<void> log(
    String message, {
    String level = 'INFO',
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer();
    buffer.write('[$timestamp] [$level] $message');
    if (error != null) {
      buffer.write(' | ERROR: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nSTACKTRACE:\n$stackTrace');
    }
    buffer.writeln();

    final logLine = buffer.toString();
    debugPrint(logLine.trimRight());

    try {
      if (_logFile == null) {
        final dir = await getApplicationDocumentsDirectory();
        _logFile = File('${dir.path}/pocket_query_debug.log');
      }
      await _logFile?.writeAsString(logLine, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('Failed to write to pocket_query_debug.log: $e');
    }
  }

  static Future<String> readLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pocket_query_debug.log');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      return 'Failed to read logs: $e';
    }
    return 'No log file found.';
  }

  static Future<void> clearLogs() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.writeAsString('=== LOGS CLEARED ===\n', mode: FileMode.write, flush: true);
      }
    } catch (e) {
      debugPrint('Failed to clear logs: $e');
    }
  }
}
