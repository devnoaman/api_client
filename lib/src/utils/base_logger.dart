import 'package:api_client/src/configuration.dart';
import 'dart:developer' as dev;

enum LogLevel { info, warning, error, debug }

class BaseLogger {
  // Singleton instance
  static final BaseLogger _instance = BaseLogger._internal();

  factory BaseLogger() => _instance;

  BaseLogger._internal();

  /// Logs a message with a specific level and optional stack trace
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
    String? name,
  }) {
    if (!Configuration.enableLogs) return;

    final String emoji = _getEmoji(level);
    final String logName = name ?? 'ApiClientLogger';

    dev.log(
      '$emoji $message',
      name: logName,
      error: error,
      stackTrace: stackTrace,
      level: _getPriority(level),
    );
  }

  // Convenience methods
  void info(String msg, {String? name}) =>
      log(msg, level: LogLevel.info, name: name);
  void warn(String msg, {String? name}) =>
      log(msg, level: LogLevel.warning, name: name);
  void debug(String msg, {String? name}) =>
      log(msg, level: LogLevel.debug, name: name);
  void error(String msg, {Object? error, StackTrace? st, String? name}) =>
      log(msg, level: LogLevel.error, error: error, stackTrace: st, name: name);

  String _getEmoji(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.debug:
        return '🪲';
    }
  }

  int _getPriority(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return 0;
      case LogLevel.debug:
        return 500;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
    }
  }
}
