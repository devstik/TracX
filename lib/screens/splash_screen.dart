import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracx/screens/login_screen.dart'; // Importação adicionada

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _rotationController;
  late final AnimationController _particlesController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoReveal;
  late final Animation<double> _letterS;
  late final Animation<double> _letterT;
  late final Animation<double> _letterI;
  late final Animation<double> _letterK;
  late final Animation<double> _glowIntensity;
  late final Animation<double> _contentFade;

  // FUNÇÃO ATUALIZADA: Verifica as credenciais salvas para definir a próxima tela.

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 20000),
    )..repeat();

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Revelação dos círculos
    _logoReveal = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    // Cada letra aparece individualmente em cascata
    _letterS = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _letterT = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _letterI = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.5, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _letterK = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // Intensidade do brilho
    _glowIntensity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeInOut),
      ),
    );

    // Fade do conteúdo inferior
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.7, 0.9, curve: Curves.easeIn),
      ),
    );

    _mainController.forward();

    _mainController.addStatusListener((status) async {
      if (status == AnimationStatus.completed) {
        await Future.delayed(const Duration(milliseconds: 3500));
        if (!mounted) return;

        // NOVO: Navegação para a tela de login após a animação
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => LoginScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _rotationController.dispose();
    _particlesController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFb41c1c);
    const accentColor = Color(0xFFd32f2f);
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFFFCFCFC),
              const Color(0xFFFAFAFA),
              primaryColor.withOpacity(0.02),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Padrão de grid sutil
            CustomPaint(
              size: screenSize,
              painter: _GridPainter(color: primaryColor),
            ),

            // Partículas flutuantes
            AnimatedBuilder(
              animation: _particlesController,
              builder: (context, child) {
                return CustomPaint(
                  size: screenSize,
                  painter: _EnhancedParticlesPainter(
                    animation: _particlesController.value,
                    color: primaryColor,
                  ),
                );
              },
            ),

            // Conteúdo principal
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _mainController,
                  _rotationController,
                  _pulseController,
                ]),
                builder: (context, child) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo com anéis rotativos
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Anel externo rotativo
                          Transform.scale(
                            scale: _logoReveal.value,
                            child: Transform.rotate(
                              angle: _rotationController.value * 2 * math.pi,
                              child: Container(
                                width: 320,
                                height: 320,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: primaryColor.withOpacity(0.08),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Anel médio contra-rotativo
                          Transform.scale(
                            scale: _logoReveal.value,
                            child: Transform.rotate(
                              angle: -_rotationController.value * 1.5 * math.pi,
                              child: Container(
                                width: 260,
                                height: 260,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: accentColor.withOpacity(0.12),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Círculo de fundo com gradiente e animação suave (Ponto 2)
                          Transform.scale(
                            scale: _logoReveal.value,
                            child: Transform.rotate(
                              // Animação de rotação suave adicionada
                              angle: _pulseController.value * 0.05 * math.pi,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      primaryColor.withOpacity(0.15),
                                      primaryColor.withOpacity(0.08),
                                      primaryColor.withOpacity(0.02),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.4, 0.7, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Pulso de brilho
                          Transform.scale(
                            scale:
                                _logoReveal.value *
                                (1.0 + _pulseController.value * 0.05),
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withOpacity(
                                      (0.15 *
                                              _glowIntensity.value *
                                              (0.7 +
                                                  _pulseController.value * 0.3))
                                          .clamp(0.0, 1.0),
                                    ),
                                    blurRadius:
                                        40 *
                                        (0.7 + _pulseController.value * 0.3),
                                    spreadRadius:
                                        10 *
                                        (0.7 + _pulseController.value * 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Letras STIK animadas individualmente
                          SizedBox(
                            height: 100,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildAnimatedLetter(
                                  'S',
                                  _letterS.value,
                                  primaryColor,
                                  accentColor,
                                ),
                                const SizedBox(width: 2),
                                _buildAnimatedLetter(
                                  'T',
                                  _letterT.value,
                                  primaryColor,
                                  accentColor,
                                ),
                                const SizedBox(width: 2),
                                _buildAnimatedLetter(
                                  'I',
                                  _letterI.value,
                                  primaryColor,
                                  accentColor,
                                ),
                                const SizedBox(width: 2),
                                _buildAnimatedLetter(
                                  'K',
                                  _letterK.value,
                                  primaryColor,
                                  accentColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 70),

                      // Subtítulo com ornamentos
                      Opacity(
                        opacity: _contentFade.value.clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            // Ornamento superior
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildOrnament(primaryColor),
                                const SizedBox(width: 16),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildOrnament(primaryColor),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Subtítulo
                            Text(
                              'TraceX',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 6,
                                color: primaryColor.withOpacity(0.75),
                              ),
                            ),

                            // Espaçamento aumentado para mais leveza (Ponto 1)
                            const SizedBox(height: 12),

                            // Tagline
                            Text(
                              'Rastreabilidade de Materiais',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1.5,
                                color: Colors.grey[600],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Ornamento inferior
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildOrnament(primaryColor),
                                const SizedBox(width: 16),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                _buildOrnament(primaryColor),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 60),

                      // NOVO: Indicador de Carregamento Linear (Ponto 3)
                      Opacity(
                        opacity: _contentFade.value.clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 80.0),
                          child: LinearProgressIndicator(
                            value: _mainController.value,
                            backgroundColor: primaryColor.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              primaryColor.withOpacity(0.6),
                            ),
                            minHeight: 3,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 20,
                      ), // Espaço entre a barra e os dots
                      // Loading moderno - dots animados (original)
                      Opacity(
                        opacity: _contentFade.value.clamp(0.0, 1.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (index) {
                            return AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final delay = index * 0.2;
                                final value =
                                    ((_pulseController.value + delay) % 1.0);
                                final scale =
                                    0.6 + (math.sin(value * math.pi) * 0.4);

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryColor.withOpacity(
                                      (0.3 + scale * 0.5).clamp(0.0, 1.0),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(
                                          (0.3 * scale).clamp(0.0, 1.0),
                                        ),
                                        blurRadius: 6 * scale,
                                        spreadRadius: 1 * scale,
                                      ),
                                    ],
                                  ),
                                  transform: Matrix4.identity()..scale(scale),
                                );
                              },
                            );
                          }),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Rodapé: Versão e Copyright
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _contentFade,
                builder: (context, child) {
                  return Opacity(
                    opacity: (_contentFade.value * 1.0).clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        // Texto "by: Stik Elástico"
                        const Text(
                          'by Stik Tech',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.5,
                            color: primaryColor,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Versão e ano
                        Text(
                          'v1.0.0',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                            letterSpacing: 2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '2025',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[350],
                            letterSpacing: 1,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrnament(Color color) {
    return Container(
      width: 30,
      height: 1.5,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildAnimatedLetter(
    String letter,
    double progress,
    Color primaryColor,
    Color accentColor,
  ) {
    final scale = progress.clamp(0.0, 1.0);
    final opacity = progress.clamp(0.0, 1.0);
    final translateY = (1 - progress) * 30;

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [primaryColor, accentColor],
                stops: const [0.3, 1.0],
              ).createShader(bounds);
            },
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 68,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Color(0x25000000),
                    offset: Offset(0, 6),
                    blurRadius: 16,
                  ),
                  Shadow(
                    color: Color(0x15000000),
                    offset: Offset(0, 3),
                    blurRadius: 8,
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

// Grid de fundo sutil
class _GridPainter extends CustomPainter {
  final Color color;

  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.02)
      ..strokeWidth = 0.5;

    const spacing = 40.0;

    // Linhas verticais
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    // Linhas horizontais
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// Partículas aprimoradas
class _EnhancedParticlesPainter extends CustomPainter {
  final double animation;
  final Color color;

  _EnhancedParticlesPainter({required this.animation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Partículas pequenas
    for (int i = 0; i < 40; i++) {
      final seed = i * 137.508;
      final x = (math.sin(seed) * 0.5 + 0.5) * size.width;
      final baseY = (math.cos(seed * 0.7) * 0.5 + 0.5) * size.height;
      final y = (baseY + (animation * 200)) % size.height;
      final radius = 1.0 + (math.sin(seed * 1.3) * 0.5 + 0.5) * 1.2;

      final distanceFromCenter =
          (y - size.height / 2).abs() / (size.height / 2);
      final opacity = ((1.0 - distanceFromCenter) * 0.15).clamp(0.0, 1.0);

      paint.color = color.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Partículas brilhantes
    for (int i = 0; i < 15; i++) {
      final seed = i * 234.567;
      final x = (math.cos(seed * 1.2) * 0.5 + 0.5) * size.width;
      final baseY = (math.sin(seed * 0.8) * 0.5 + 0.5) * size.height;
      final y = (baseY - (animation * 150)) % (size.height + 100) - 50;

      final pulseValue = math.sin((animation + seed) * math.pi * 2);
      final radius = 1.5 + pulseValue * 0.8;

      final distanceFromCenter =
          (y - size.height / 2).abs() / (size.height / 2);
      final baseOpacity = ((1.0 - distanceFromCenter) * 0.2).clamp(0.0, 1.0);
      final opacity = (baseOpacity * (0.5 + pulseValue * 0.5)).clamp(0.0, 1.0);

      paint.color = color.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Glow nas partículas brilhantes
      paint.color = color.withOpacity((opacity * 0.3).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), radius * 2, paint);
    }
  }

  @override
  bool shouldRepaint(_EnhancedParticlesPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
