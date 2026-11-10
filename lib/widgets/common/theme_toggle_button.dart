import 'package:action_flow/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';

/// A sleek, accessible Light / Dark theme toggle button for headers and toolbars.
class ThemeToggleButton extends StatelessWidget {
  final double size;
  final bool showBorder;
  final EdgeInsetsGeometry? padding;

  const ThemeToggleButton({
    super.key,
    this.size = 38,
    this.showBorder = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final isDark = ThemeController.instance.isDark;
        final tooltip = isDark
            ? 'Switch to Light Theme'
            : 'Switch to Dark Theme';

        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: () => ThemeController.instance.toggleTheme(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: size,
              height: size,
              padding: padding,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: showBorder
                    ? Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                      )
                    : null,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) => RotationTransition(
                    turns: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_outlined,
                    key: ValueKey<bool>(isDark),
                    size: size * 0.52,
                    color: isDark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
