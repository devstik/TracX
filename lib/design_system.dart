import 'package:flutter/material.dart';

class AppDesignSystem {
  static const Color brandGold = Color(0xFFD8B840);
  static const Color brandGoldLight = Color(0xFFE8CE7A);
  static const Color brandGoldDark = Color(0xFFB89628);

  static const Color industrialBg = Color(0xFF020617);
  static const Color industrialHeader = Color(0xFF0F172A);
  static const Color industrialSurface = Color(0xFF111827);
  static const Color industrialSurfaceElevated = Color(0xFF172033);
  static const Color industrialBorder = Color(0xFF334155);
  static const Color industrialPrimary = brandGold;
  static const Color industrialPrimaryPressed = brandGoldDark;
  static const Color industrialInfo = Color(0xFF38BDF8);
  static const Color industrialSuccess = Color(0xFF16A34A);
  static const Color industrialSuccessBg = Color(0xFF052E16);
  static const Color industrialWarning = Color(0xFFF59E0B);
  static const Color industrialWarningBg = Color(0xFF451A03);
  static const Color industrialError = Color(0xFFDC2626);
  static const Color industrialErrorBg = Color(0xFF450A0A);
  static const Color industrialBlocked = Color(0xFFB91C1C);
  static const Color industrialTextPrimary = Color(0xFFF8FAFC);
  static const Color industrialTextSecondary = Color(0xFFCBD5E1);
  static const Color industrialTextMuted = Color(0xFF94A3B8);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [brandGoldDark, brandGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient cardGradient = const LinearGradient(
    colors: [industrialSurfaceElevated, industrialSurface],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get shadowXl => [
        BoxShadow(
          color: brandGold.withValues(alpha: 0.18),
          blurRadius: 34,
          offset: const Offset(0, 10),
        ),
      ];

  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2Xl = 48.0;

  static const TextStyle headingXl = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: industrialTextPrimary,
    letterSpacing: 0,
    height: 1.2,
  );

  static const TextStyle headingLg = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: industrialTextPrimary,
    letterSpacing: 0,
    height: 1.3,
  );

  static const TextStyle headingMd = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: industrialTextPrimary,
    letterSpacing: 0,
    height: 1.4,
  );

  static const TextStyle headingSm = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: industrialTextPrimary,
    height: 1.5,
  );

  static const TextStyle bodyLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: industrialTextPrimary,
    height: 1.6,
  );

  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: industrialTextSecondary,
    height: 1.5,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: industrialTextMuted,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: industrialTextMuted,
    letterSpacing: 0,
    height: 1.3,
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    color: industrialSurface,
    borderRadius: BorderRadius.circular(radiusSm),
    boxShadow: shadowMd,
    border: Border.all(color: industrialBorder, width: 1),
  );

  static BoxDecoration inputDecoration = BoxDecoration(
    color: industrialHeader,
    borderRadius: BorderRadius.circular(radiusSm),
    border: Border.all(color: industrialBorder, width: 1.5),
  );

  static BoxDecoration gradientCardDecoration = BoxDecoration(
    gradient: brandGradient,
    borderRadius: BorderRadius.circular(radiusSm),
    boxShadow: shadowXl,
  );

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
  static const Curve animationCurve = Curves.easeInOutCubic;

  static ThemeData appTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: industrialPrimary,
      brightness: Brightness.dark,
      primary: industrialPrimary,
      secondary: industrialInfo,
      surface: industrialSurface,
      error: industrialError,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: industrialBg,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: industrialHeader,
        foregroundColor: industrialTextPrimary,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: industrialTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        iconTheme: IconThemeData(color: industrialTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: industrialSurface,
        elevation: 0,
        margin: const EdgeInsets.all(spacingSm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: const BorderSide(color: industrialBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: industrialHeader,
        labelStyle: const TextStyle(
          color: industrialTextSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: industrialTextMuted),
        helperStyle: const TextStyle(color: industrialTextMuted),
        prefixIconColor: industrialTextSecondary,
        suffixIconColor: industrialTextSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacingMd,
          vertical: spacingMd,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: industrialBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: industrialInfo, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: industrialBorder),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: industrialError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: industrialError, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: industrialPrimary,
          foregroundColor: industrialBg,
          disabledBackgroundColor: industrialBorder,
          disabledForegroundColor: industrialTextMuted,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: industrialPrimary,
          foregroundColor: industrialBg,
          disabledBackgroundColor: industrialBorder,
          disabledForegroundColor: industrialTextMuted,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: brandGoldLight,
          side: const BorderSide(color: industrialPrimary),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: industrialHeader,
        contentTextStyle: const TextStyle(
          color: industrialTextPrimary,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      dividerTheme: const DividerThemeData(color: industrialBorder),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: industrialInfo,
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;

  const GradientText({
    super.key,
    required this.text,
    required this.style,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Gradient? gradient;
  final bool isLoading;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.gradient,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient ?? AppDesignSystem.brandGradient,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        boxShadow: AppDesignSystem.shadowXl,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.spacingLg,
              vertical: AppDesignSystem.spacingMd,
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: AppDesignSystem.industrialBg,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            color: AppDesignSystem.industrialBg,
                            size: 20,
                          ),
                          const SizedBox(width: AppDesignSystem.spacingSm),
                        ],
                        Text(
                          text,
                          style: AppDesignSystem.headingSm.copyWith(
                            color: AppDesignSystem.industrialBg,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
