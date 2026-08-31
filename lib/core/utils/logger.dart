/// Logging utility for the application
class AppLogger {
  static void log(String message, [dynamic error, StackTrace? stackTrace]) {
    print('LOG: $message');
    if (error != null) {
      print('ERROR: $error');
    }
    if (stackTrace != null) {
      print('STACK_TRACE: $stackTrace');
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    print('ERROR: $message');
    if (error != null) {
      print('ERROR_DETAILS: $error');
    }
    if (stackTrace != null) {
      print('STACK_TRACE: $stackTrace');
    }
  }

  static void warning(String message) {
    print('WARNING: $message');
  }

  static void info(String message) {
    print('INFO: $message');
  }
}
