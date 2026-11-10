import 'package:flutter/material.dart';

/// The official, standardized ActionFlow Logo Emblem.
///
/// Encapsulates the approved ActionFlow A-symbol mark with
/// consistent proportions, corner radiuses, and color styling.
class ActionFlowLogo extends StatelessWidget {
  const ActionFlowLogo({
    super.key,
    this.size = 40,
    this.iconSize,
    this.borderRadius,
    this.backgroundColor,
    this.gradient,
    this.iconColor = Colors.white,
    this.border,
    this.boxShadow,
  });

  /// Primary blue gradient logo emblem for light surfaces (Sidebars, Cards, Navigation).
  factory ActionFlowLogo.primary({
    Key? key,
    double size = 40,
    double? iconSize,
    double? borderRadius,
  }) {
    return ActionFlowLogo(
      key: key,
      size: size,
      iconSize: iconSize,
      borderRadius: borderRadius,
      gradient: const LinearGradient(
        colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      iconColor: Colors.white,
    );
  }

  /// Translucent white emblem for primary blue / dark surfaces (Splash Screen, Hero Panels).
  factory ActionFlowLogo.white({
    Key? key,
    double size = 40,
    double? iconSize,
    double? borderRadius,
    double opacity = 0.18,
  }) {
    return ActionFlowLogo(
      key: key,
      size: size,
      iconSize: iconSize,
      borderRadius: borderRadius,
      backgroundColor: Colors.white.withValues(alpha: opacity),
      iconColor: Colors.white,
    );
  }

  /// Solid white emblem with primary blue icon.
  factory ActionFlowLogo.solidWhite({
    Key? key,
    double size = 40,
    double? iconSize,
    double? borderRadius,
    Color iconColor = const Color(0xFF1565C0),
  }) {
    return ActionFlowLogo(
      key: key,
      size: size,
      iconSize: iconSize,
      borderRadius: borderRadius,
      backgroundColor: Colors.white,
      iconColor: iconColor,
    );
  }

  /// Light tint emblem for headers and toolbars.
  factory ActionFlowLogo.light({
    Key? key,
    double size = 40,
    double? iconSize,
    double? borderRadius,
  }) {
    return ActionFlowLogo(
      key: key,
      size: size,
      iconSize: iconSize,
      borderRadius: borderRadius,
      backgroundColor: const Color(0xFFE3F2FD),
      iconColor: const Color(0xFF1565C0),
    );
  }

  final double size;
  final double? iconSize;
  final double? borderRadius;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Color iconColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? (size * 0.28);
    final effectiveSymbolSize = iconSize ?? (size * 0.62);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null
            ? (backgroundColor ?? const Color(0xFF1565C0))
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: border,
        boxShadow: boxShadow,
      ),
      alignment: Alignment.center,
      child: ActionFlowSymbol(size: effectiveSymbolSize, color: iconColor),
    );
  }
}

/// Standardized ActionFlow Brand mark combining [ActionFlowLogo] with typography.
class ActionFlowBrand extends StatelessWidget {
  const ActionFlowBrand({
    super.key,
    this.logoSize = 38,
    this.fontSize = 18,
    this.textColor,
    this.isDark = false,
    this.spacing = 12,
    this.subtitle,
  });

  final double logoSize;
  final double fontSize;
  final Color? textColor;
  final bool isDark;
  final double spacing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color =
        textColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        isDark
            ? ActionFlowLogo.white(size: logoSize)
            : ActionFlowLogo.primary(size: logoSize),
        SizedBox(width: spacing),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ActionFlow',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: fontSize * 0.65,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The official ActionFlow Symbol Mark:
/// A stylized capital "A" with a dynamic sweeping arrow integrated through it.
class ActionFlowSymbol extends StatelessWidget {
  const ActionFlowSymbol({
    super.key,
    this.size = 96,
    this.width,
    this.height,
    this.color = Colors.white,
  });

  /// Crisp white symbol mark for dark or blue backgrounds (e.g. Splash Screen).
  factory ActionFlowSymbol.white({
    Key? key,
    double size = 96,
    double? width,
    double? height,
  }) {
    return ActionFlowSymbol(
      key: key,
      size: size,
      width: width,
      height: height,
      color: Colors.white,
    );
  }

  /// Primary blue symbol mark for light backgrounds.
  factory ActionFlowSymbol.primary({
    Key? key,
    double size = 96,
    double? width,
    double? height,
  }) {
    return ActionFlowSymbol(
      key: key,
      size: size,
      width: width,
      height: height,
      color: const Color(0xFF1565C0),
    );
  }

  final double size;
  final double? width;
  final double? height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = height ?? size;
    final effectiveWidth = width ?? (effectiveHeight * 1.18);

    final assetName = color == Colors.white
        ? 'assets/images/actionflow_symbol_white_hd.png'
        : 'assets/images/actionflow_symbol_blue_hd.png';

    return SizedBox(
      width: effectiveWidth,
      height: effectiveHeight,
      child: Image.asset(
        assetName,
        fit: BoxFit.contain,
        color: (color != Colors.white && color != const Color(0xFF1565C0))
            ? color
            : null,
        errorBuilder: (context, error, stackTrace) {
          return CustomPaint(
            size: Size(effectiveWidth, effectiveHeight),
            painter: ActionFlowSymbolPainter(color: color),
          );
        },
      ),
    );
  }
}

/// Dedicated CustomPainter that renders the stylized "A" + sweeping arrow mark vector path.
class ActionFlowSymbolPainter extends CustomPainter {
  const ActionFlowSymbolPainter({this.color = Colors.white});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // Outer path including the letter A and the sweeping arrow
    final path = Path();
    path.fillType = PathFillType.evenOdd;

    // Left leg & Apex & Right upper leg
    path.moveTo(w * 0.06, h * 0.96);
    path.lineTo(w * 0.22, h * 0.96);
    path.lineTo(w * 0.44, h * 0.36);
    // Apex
    path.lineTo(w * 0.49, h * 0.04);
    path.lineTo(w * 0.53, h * 0.04);
    // Right outer leg down to arrow junction
    path.lineTo(w * 0.68, h * 0.40);
    // Arrowhead top base and point
    path.lineTo(w * 0.69, h * 0.33);
    path.lineTo(w * 0.96, h * 0.41);
    // Arrowhead bottom wing
    path.lineTo(w * 0.81, h * 0.66);
    path.lineTo(w * 0.77, h * 0.58);
    // Swoosh bottom curve going back to left leg
    path.quadraticBezierTo(w * 0.55, h * 0.70, w * 0.32, h * 0.76);
    // Connect down left inner edge
    path.lineTo(w * 0.22, h * 0.96);
    path.close();

    // Right lower leg piece below arrow
    final rightLegPath = Path();
    rightLegPath.moveTo(w * 0.66, h * 0.62);
    rightLegPath.lineTo(w * 0.74, h * 0.60);
    rightLegPath.lineTo(w * 0.60, h * 0.67);
    rightLegPath.lineTo(w * 0.77, h * 0.96);
    rightLegPath.lineTo(w * 0.62, h * 0.96);
    rightLegPath.lineTo(w * 0.52, h * 0.72);
    rightLegPath.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(rightLegPath, paint);
  }

  @override
  bool shouldRepaint(covariant ActionFlowSymbolPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
