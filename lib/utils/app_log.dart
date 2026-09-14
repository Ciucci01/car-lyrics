import 'dart:developer' as developer;

const _loggerName = 'car_play';

void logInfo(String message) {
  developer.log(message, name: _loggerName);
}

void logError(String message, [Object? error, StackTrace? stackTrace]) {
  developer.log(
    message,
    name: _loggerName,
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );
}
