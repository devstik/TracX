import 'package:flutter/material.dart';

/// Design System para o aplicativo TracX
/// Paleta moderna inspirada em tecnologia e inovação
class AppDesignSystem {
  // ========== CORES PRIMÁRIAS ==========
  static const Color primaryDark = Color(0xFF0F172A); // Azul escuro profundo
  static const Color primaryBlue = Color(0xFF3B82F6); // Azul vibrante
  static const Color primaryCyan = Color(0xFF06B6D4); // Cyan energético
  static const Color primaryPurple = Color(0xFF8B5CF6); // Roxo moderno

  // ========== CORES SECUNDÁRIAS ==========
  static const Color accentOrange = Color(0xFFF59E0B); // Laranja para destaque
  static const Color accentGreen = Color(0xFF10B981); // Verde para sucesso
  static const Color accentRed = Color(0xFFEF4444); // Vermelho para alertas
  static const Color accentPink = Color(
    0xFFEC4899,
  ); // Rosa para elementos especiais

  // ========== CORES DE FUNDO ==========
  static const Color bgPrimary = Color(0xFFF8FAFC); // Branco azulado suave
  static const Color bgSecondary = Color(0xFFFFFFFF); // Branco puro
  static const Color bgCard = Color(0xFFFFFFFF); // Branco para cards
  static const Color bgInput = Color(0xFFF1F5F9); // Cinza muito claro
  static const Color bgDark = Color(0xFF1E293B); // Fundo escuro

  // ========== CORES DE TEXTO ==========
  static const Color textPrimary = Color(0xFF0F172A); // Texto principal
  static const Color textSecondary = Color(0xFF64748B); // Texto secundário
  static const Color textTertiary = Color(0xFF94A3B8); // Texto terciário
  static const Color textWhite = Color(0xFFFFFFFF); // Texto branco

  // ========== GRADIENTES ==========
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, primaryCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [primaryPurple, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [primaryDark, Color(0xFF1E293B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static LinearGradient cardGradient = LinearGradient(
    colors: [bgCard, bgCard.withOpacity(0.95)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ========== SOMBRAS ==========
  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLg => [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get shadowXl => [
    BoxShadow(
      color: primaryBlue.withOpacity(0.15),
      blurRadius: 40,
      offset: const Offset(0, 10),
    ),
  ];

  // ========== BORDAS ARREDONDADAS ==========
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;

  // ========== ESPAÇAMENTOS ==========
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacing2Xl = 48.0;

  // ========== TIPOGRAFIA ==========
  static const TextStyle headingXl = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle headingLg = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: textPrimary,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static const TextStyle headingMd = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.2,
    height: 1.4,
  );

  static const TextStyle headingSm = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.6,
  );

  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textTertiary,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    letterSpacing: 0.5,
    height: 1.3,
  );

  // ========== DECORAÇÕES REUTILIZÁVEIS ==========
  static BoxDecoration cardDecoration = BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(radiusLg),
    boxShadow: shadowMd,
    border: Border.all(color: textTertiary.withOpacity(0.1), width: 1),
  );

  static BoxDecoration inputDecoration = BoxDecoration(
    color: bgInput,
    borderRadius: BorderRadius.circular(radiusMd),
    border: Border.all(color: Colors.transparent, width: 1.5),
  );

  static BoxDecoration gradientCardDecoration = BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(radiusLg),
    boxShadow: shadowXl,
  );

  // ========== ANIMAÇÕES ==========
  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);

  static const Curve animationCurve = Curves.easeInOutCubic;
}

/// Widget helper para gradiente de texto
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

/// Widget helper para botão com gradiente
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
        gradient: gradient ?? AppDesignSystem.primaryGradient,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        boxShadow: AppDesignSystem.shadowMd,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: AppDesignSystem.spacingSm),
                        ],
                        Text(
                          text,
                          style: AppDesignSystem.headingSm.copyWith(
                            color: Colors.white,
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
