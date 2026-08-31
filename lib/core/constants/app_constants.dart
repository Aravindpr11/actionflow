/// Application-wide constants
class AppConstants {
  AppConstants._(); // Private constructor to prevent instantiation

  // App information
  static const String appName = 'ActionFlow';
  static const String appVersion = '1.0.0';

  // API endpoints (placeholder - will be configured later)
  static const String apiBaseUrl = 'https://api.example.com';

  // Timeout durations
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Common strings
  static const String noDataMessage = 'No data available';
  static const String errorMessage = 'An error occurred. Please try again.';
  static const String loadingMessage = 'Loading...';

  // Features flags (for future use)
  static const bool enableNotifications = true;
  static const bool enableEmailReminders = true;
  static const bool enableAuditLog = true;
}
