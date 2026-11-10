import 'package:flutter/material.dart';

/// Application-wide theme configuration and adaptive color tokens.
class AppTheme {
  AppTheme._();

  // Core Brand Colors
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color primaryVariant = Color(0xFF0D47A1);
  static const Color secondaryColor = Color(0xFF38BDF8);
  static const Color secondaryVariant = Color(0xFF0284C7);
  static const Color errorColor = Color(0xFFEF4444);

  // Light Palette Tokens
  static const Color lightBackground = Color(0xFFF1F5F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextHint = Color(0xFF94A3B8);
  static const Color lightInputFill = Color(0xFFF8FAFC);
  static const Color lightInputBorder = Color(0xFFCBD5E1);
  static const Color lightDivider = Color(0xFFF1F5F9);

  // Dark Palette Tokens (Enterprise Slate/Navy)
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color surfaceDark = darkSurface;
  static const Color darkCardBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextHint = Color(0xFF64748B);
  static const Color darkInputFill = Color(0xFF0B1120);
  static const Color darkInputBorder = Color(0xFF334155);
  static const Color darkDivider = Color(0xFF334155);

  // Shared Sidebar Background (Consistent Dark Navy across themes)
  static const Color sidebarBackground = Color(0xFF0F172A);
  static const Color sidebarDivider = Color(0xFF1E293B);

  // Status & Severity Colors
  static const Color statusOpen = Color(0xFF0284C7);
  static const Color statusInProgress = Color(0xFFEAB308);
  static const Color statusPendingReview = Color(0xFF8B5CF6);
  static const Color statusClosed = Color(0xFF10B981);
  static const Color statusOverdue = Color(0xFFEF4444);
  static const Color statusDueSoon = Color(0xFFF97316);

  static const Color priorityCritical = Color(0xFFEF4444);
  static const Color priorityHigh = Color(0xFFF97316);
  static const Color priorityMedium = Color(0xFFEAB308);
  static const Color priorityLow = Color(0xFF10B981);

  // =========================================================================
  // THEMEDATA DEFINITIONS
  // =========================================================================

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: secondaryVariant,
      onSecondary: Colors.white,
      error: errorColor,
      onError: Colors.white,
      surface: lightSurface,
      onSurface: lightTextPrimary,
      surfaceContainerHighest: lightBackground,
      onSurfaceVariant: lightTextSecondary,
      outline: lightInputBorder,
      outlineVariant: lightCardBorder,
    ),
    scaffoldBackgroundColor: lightBackground,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: lightSurface,
      foregroundColor: lightTextPrimary,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: lightTextPrimary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: lightCardBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: lightSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: lightTextPrimary,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 14,
        color: lightTextSecondary,
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      dataRowColor: WidgetStateProperty.all(lightSurface),
      headingTextStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: lightTextSecondary,
      ),
      dataTextStyle: const TextStyle(fontSize: 13, color: lightTextPrimary),
      dividerThickness: 1,
    ),
    dividerTheme: const DividerThemeData(
      color: lightDivider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightInputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightInputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(fontSize: 13, color: lightTextHint),
      labelStyle: const TextStyle(fontSize: 13, color: lightTextSecondary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 3,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: lightTextPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primaryColor),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: secondaryColor,
      onPrimary: darkBackground,
      secondary: secondaryVariant,
      onSecondary: Colors.white,
      error: errorColor,
      onError: Colors.white,
      surface: darkSurface,
      onSurface: darkTextPrimary,
      surfaceContainerHighest: darkBackground,
      onSurfaceVariant: darkTextSecondary,
      outline: darkInputBorder,
      outlineVariant: darkCardBorder,
    ),
    scaffoldBackgroundColor: darkBackground,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: darkSurface,
      foregroundColor: darkTextPrimary,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: darkTextPrimary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: darkCardBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: darkTextPrimary,
      ),
      contentTextStyle: const TextStyle(fontSize: 14, color: darkTextSecondary),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStateProperty.all(darkBackground),
      dataRowColor: WidgetStateProperty.all(darkSurface),
      headingTextStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: darkTextSecondary,
      ),
      dataTextStyle: const TextStyle(fontSize: 13, color: darkTextPrimary),
      dividerThickness: 1,
    ),
    dividerTheme: const DividerThemeData(
      color: darkDivider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkInputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkInputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: darkInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: secondaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(fontSize: 13, color: darkTextHint),
      labelStyle: const TextStyle(fontSize: 13, color: darkTextSecondary),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: secondaryColor,
      foregroundColor: darkBackground,
      elevation: 3,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: secondaryColor,
        foregroundColor: darkBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: secondaryColor),
    ),
  );

  // =========================================================================
  // DYNAMIC CONTEXT HELPERS
  // =========================================================================

  /// Returns whether the current BuildContext is rendering in dark mode.
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Adaptive application background (slate-50 in light, slate-900 in dark).
  static Color scaffoldBg(BuildContext context) {
    return isDark(context) ? darkBackground : lightBackground;
  }

  /// Adaptive card and container surface color.
  static Color cardBg(BuildContext context) {
    return isDark(context) ? darkSurface : lightSurface;
  }

  /// Adaptive subtle border for cards and panels.
  static Color cardBorder(BuildContext context) {
    return isDark(context) ? darkCardBorder : lightCardBorder;
  }

  /// Adaptive top header background color.
  static Color headerBg(BuildContext context) {
    return isDark(context) ? darkSurface : lightSurface;
  }

  /// Adaptive top header bottom border color.
  static Color headerBorder(BuildContext context) {
    return isDark(context) ? darkCardBorder : lightCardBorder;
  }

  /// Adaptive high-contrast primary text color.
  static Color textPrimary(BuildContext context) {
    return isDark(context) ? darkTextPrimary : lightTextPrimary;
  }

  /// Adaptive muted secondary text color.
  static Color textSecondary(BuildContext context) {
    return isDark(context) ? darkTextSecondary : lightTextSecondary;
  }

  /// Adaptive placeholder / hint text color.
  static Color textMuted(BuildContext context) {
    return isDark(context) ? darkTextHint : lightTextHint;
  }

  /// Adaptive text field and dropdown fill color.
  static Color inputFill(BuildContext context) {
    return isDark(context) ? darkInputFill : lightInputFill;
  }

  /// Adaptive text field and dropdown border color.
  static Color inputBorder(BuildContext context) {
    return isDark(context) ? darkInputBorder : lightInputBorder;
  }

  /// Adaptive divider color.
  static Color dividerColor(BuildContext context) {
    return isDark(context) ? darkDivider : lightDivider;
  }

  /// Adaptive DataTable header row background.
  static Color tableHeaderBg(BuildContext context) {
    return isDark(context) ? darkBackground : const Color(0xFFF8FAFC);
  }

  /// Adaptive DataTable row hover/alternate color.
  static Color tableRowHover(BuildContext context) {
    return isDark(context) ? const Color(0xFF243248) : const Color(0xFFF8FAFC);
  }

  /// Adaptive brand accent color for action buttons & highlights.
  static Color primaryAccent(BuildContext context) {
    return isDark(context) ? secondaryColor : primaryColor;
  }

  /// Adaptive pill/badge background color based on status or role.
  static Color badgeBg(BuildContext context, String label) {
    final dark = isDark(context);
    final l = label.toLowerCase();
    if (l.contains('manager') || l.contains('open') || l.contains('info')) {
      return dark
          ? const Color(0xFF0369A1).withValues(alpha: 0.3)
          : const Color(0xFFE0F2FE);
    }
    if (l.contains('staff') ||
        l.contains('worker') ||
        l.contains('closed') ||
        l.contains('active') ||
        l.contains('success') ||
        l.contains('completed')) {
      return dark
          ? const Color(0xFF15803D).withValues(alpha: 0.3)
          : const Color(0xFFDCFCE7);
    }
    if (l.contains('overdue') ||
        l.contains('critical') ||
        l.contains('inactive') ||
        l.contains('danger') ||
        l.contains('high')) {
      return dark
          ? const Color(0xFFB91C1C).withValues(alpha: 0.3)
          : const Color(0xFFFEE2E2);
    }
    if (l.contains('pending') ||
        l.contains('progress') ||
        l.contains('medium') ||
        l.contains('warning') ||
        l.contains('soon')) {
      return dark
          ? const Color(0xFFB45309).withValues(alpha: 0.3)
          : const Color(0xFFFEF3C7);
    }
    return dark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
  }

  /// Adaptive pill/badge text color based on status or role.
  static Color badgeText(BuildContext context, String label) {
    final dark = isDark(context);
    final l = label.toLowerCase();
    if (l.contains('manager') || l.contains('open') || l.contains('info')) {
      return dark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    }
    if (l.contains('staff') ||
        l.contains('worker') ||
        l.contains('closed') ||
        l.contains('active') ||
        l.contains('success') ||
        l.contains('completed')) {
      return dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    }
    if (l.contains('overdue') ||
        l.contains('critical') ||
        l.contains('inactive') ||
        l.contains('danger') ||
        l.contains('high')) {
      return dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
    }
    if (l.contains('pending') ||
        l.contains('progress') ||
        l.contains('medium') ||
        l.contains('warning') ||
        l.contains('soon')) {
      return dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    }
    return dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
  }

  /// Adaptive progress bar track background color.
  static Color progressTrackBg(BuildContext context) {
    return isDark(context) ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  }

  /// Adaptive Action ID badge background color.
  static Color actionIdBg(BuildContext context) {
    return isDark(context)
        ? const Color(0xFF1E3A8A).withValues(alpha: 0.35)
        : const Color(0xFFEFF6FF);
  }

  /// Adaptive Action ID badge border color.
  static Color actionIdBorder(BuildContext context) {
    return isDark(context)
        ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
        : const Color(0xFFBFDBFE);
  }

  /// Adaptive Action ID badge text color.
  static Color actionIdText(BuildContext context) {
    return isDark(context) ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
  }

  /// Adaptive secondary container background (slate-50 vs slate-800/900).
  static Color containerBg(BuildContext context) {
    return isDark(context) ? const Color(0xFF131D31) : const Color(0xFFF8FAFC);
  }

  /// Priority indicator color.
  static Color priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return priorityCritical;
      case 'high':
        return priorityHigh;
      case 'medium':
        return priorityMedium;
      case 'low':
        return priorityLow;
      default:
        return const Color(0xFF94A3B8);
    }
  }

  /// Status indicator color.
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return statusOpen;
      case 'in progress':
        return statusInProgress;
      case 'pending review':
        return statusPendingReview;
      case 'closed':
      case 'completed':
        return statusClosed;
      case 'overdue':
        return statusOverdue;
      case 'due soon':
        return statusDueSoon;
      default:
        return const Color(0xFF94A3B8);
    }
  }
}
