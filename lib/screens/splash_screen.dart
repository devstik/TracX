import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracx/screens/login_screen.dart';
import 'package:intl/intl.dart';
import 'package:tracx/services/SyncService.dart';
import 'ConsultaMapaProducaoScreen.dart';
import 'package:tracx/services/estoque_db_helper.dart';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tracx/services/update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _animationFinished = false;
  bool _updateOk = true;

  late final AnimationController _mainController;
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _letterS;
  late final Animation<double> _letterT;
  late final Animation<double> _letterI;
  late final Animation<double> _letterK;
  late final Animation<double> _lineExpand;
  late final Animation<double> _textFade;
  late final Animation<double> _contentFade;

  // CORES CORPORATIVAS
  static const Color bg = Color(0xFF050A14);
  static const Color surface = Color(0xFF0B1220);
  static const Color surface2 = Color(0xFF101B34);
  static const Color primary = Color(0xFF4DA3FF);
  static const Color accent = Color(0xFF5EF7C5);
  static const Color danger = Color(0xFFFF5C8A);
  static const Color borderSoft = Color(0x18FFFFFF);

  void _showUpdateDialog({required bool force, required String apkUrl}) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => !force,
          child: AlertDialog(
            backgroundColor: surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: const Text(
              'Atualização disponível',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              force
                  ? 'Esta versão do aplicativo não é mais suportada.\nAtualize para continuar.'
                  : 'Existe uma nova versão disponível.\nDeseja atualizar agora?',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _updateOk = true;
                    _tryNavigate();
                  },
                  child: const Text(
                    'Depois',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  final uri = Uri.parse(apkUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  'Atualizar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _sincronizarHistoricoCompleto();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutCubic),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );

    _letterS = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.20, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _letterT = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.30, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _letterI = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.40, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _letterK = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.50, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _lineExpand = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.65, 0.90, curve: Curves.easeOut),
      ),
    );

    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
      ),
    );

    _mainController.forward();

    _mainController.addStatusListener((status) async {
      if (status == AnimationStatus.completed) {
        _animationFinished = true;
        _tryNavigate();
      }
    });
  }

  void _tryNavigate() async {
    if (!_animationFinished || !_updateOk) return;

    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginScreen()),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF0B1220), bg, const Color(0xFF050A14)],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Grid corporativo minimalista
            CustomPaint(size: screenSize, painter: _MinimalGridPainter()),

            // Glow suave de fundo
            Positioned(
              top: screenSize.height * 0.25,
              left: screenSize.width * 0.5 - 300,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [primary.withOpacity(0.08), Colors.transparent],
                  ),
                ),
              ),
            ),

            // Conteúdo principal
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _mainController,
                  _shimmerController,
                  _pulseController,
                ]),
                builder: (context, child) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo STIK Corporativo
                      Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoOpacity.value,
                          child: Column(
                            children: [
                              // Container com as letras STIK
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 24,
                                ),
                                decoration: BoxDecoration(
                                  color: surface.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: primary.withOpacity(0.15),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildCorporateLetter('S', _letterS.value),
                                    const SizedBox(width: 4),
                                    _buildCorporateLetter('T', _letterT.value),
                                    const SizedBox(width: 4),
                                    _buildCorporateLetter('I', _letterI.value),
                                    const SizedBox(width: 4),
                                    _buildCorporateLetter('K', _letterK.value),
                                  ],
                                ),
                              ),

                              // Linha decorativa animada
                              SizedBox(
                                height: 40,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Linha base
                                    Container(
                                      width: 180,
                                      height: 1,
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                    // Linha animada com gradiente
                                    AnimatedBuilder(
                                      animation: _lineExpand,
                                      builder: (context, child) {
                                        return Container(
                                          width: 180 * _lineExpand.value,
                                          height: 2,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                primary,
                                                accent,
                                                Colors.transparent,
                                              ],
                                              stops: const [0.0, 0.4, 0.6, 1.0],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // TracX Badge
                      Opacity(
                        opacity: _textFade.value.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - _textFade.value) * 15),
                          child: Column(
                            children: [
                              // Nome do produto
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  gradient: LinearGradient(
                                    colors: [
                                      primary.withOpacity(0.15),
                                      accent.withOpacity(0.12),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: primary.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Text(
                                  'TracX',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Tagline corporativa
                              Text(
                                'Sistema de Rastreabilidade',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: Colors.white.withOpacity(0.75),
                                ),
                              ),

                              const SizedBox(height: 6),

                              Text(
                                'Gestão Inteligente de Materiais',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.8,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),

                              const SizedBox(height: 36),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 50),

                      // Loading corporativo
                      Opacity(
                        opacity: _contentFade.value.clamp(0.0, 1.0),
                        child: Column(
                          children: [
                            // Barra de progresso premium
                            SizedBox(
                              width: 240,
                              child: Stack(
                                children: [
                                  // Fundo
                                  Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: surface2,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  // Progresso
                                  AnimatedBuilder(
                                    animation: _mainController,
                                    builder: (context, child) {
                                      return Container(
                                        height: 3,
                                        width: 240 * _mainController.value,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          gradient: LinearGradient(
                                            colors: [primary, accent],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Shimmer effect
                                  AnimatedBuilder(
                                    animation: _shimmerController,
                                    builder: (context, child) {
                                      return Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Colors.transparent,
                                              Colors.white.withOpacity(0.3),
                                              Colors.transparent,
                                            ],
                                            stops: [
                                              _shimmerController.value - 0.3,
                                              _shimmerController.value,
                                              _shimmerController.value + 0.3,
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Status text
                            AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return Opacity(
                                  opacity: 0.5 + (_pulseController.value * 0.3),
                                  child: Text(
                                    'Carregando...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Rodapé corporativo premium
            Positioned(
              bottom: 44,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _contentFade,
                builder: (context, child) {
                  return Opacity(
                    opacity: (_contentFade.value).clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        // Separador elegante
                        Container(
                          width: 100,
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withOpacity(0.2),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // by STIK Tech
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: surface.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: borderSoft, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [primary, accent],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'by STIK Tech',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.8,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Versão
                        Text(
                          'v1.0.7 • 2025',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                            color: Colors.white.withOpacity(0.35),
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

  Widget _buildCorporateLetter(String letter, double progress) {
    final opacity = progress.clamp(0.0, 1.0);
    final translateY = (1 - progress) * 20;

    return Transform.translate(
      offset: Offset(0, translateY),
      child: Opacity(
        opacity: opacity,
        child: ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4DA3FF), Color(0xFF5EF7C5)],
            ).createShader(bounds);
          },
          child: Text(
            letter,
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sincronizarHistoricoCompleto() async {
    try {
      final dbHelper = EstoqueDbHelper();
      final agora = DateTime.now();

      final dataInicial = DateTime(agora.year, agora.month, 1);
      final dataOntem = agora.subtract(const Duration(days: 1));

      if (dataOntem.isBefore(dataInicial)) return;

      final token = await ApiService.authenticate(
        endpoint: AppConstants.authEndpointWMS,
        email: AppConstants.authEmailWMS,
        senha: AppConstants.authSenhaWMS,
        usuarioId: AppConstants.authUsuarioIdWMS,
      );

      List<DateTime> diasFaltantes = [];
      for (
        DateTime d = dataInicial;
        !d.isAfter(dataOntem);
        d = d.add(const Duration(days: 1))
      ) {
        String iso = DateFormat("yyyy-MM-dd'T'00:00:00").format(d);
        final jaExiste = await dbHelper.getMapasByDate(iso);
        if (jaExiste.isEmpty) diasFaltantes.add(d);
      }

      if (diasFaltantes.isNotEmpty) {
        await Future.wait(
          diasFaltantes.map((data) async {
            String isoDate = DateFormat("yyyy-MM-dd'T'00:00:00").format(data);
            try {
              final registros = await ApiService.fetchMapByDate(
                apiKeyWMS: token,
                isoDate: isoDate,
              );
              if (registros.isNotEmpty) {
                await dbHelper.insertMapas(registros, isoDate);
              }
            } catch (e) {
              debugPrint("Erro no dia $isoDate: $e");
            }
          }),
        );
      }
    } catch (e) {
      debugPrint("Erro na carga da Splash: $e");
    }
  }
}

// ==================== PAINTERS ====================

class _MinimalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 0.5;

    const spacing = 80.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(_MinimalGridPainter oldDelegate) => false;
}
