import 'dart:convert';
import 'dart:math' as math;
import 'package:tracx/screens/home_menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../services/estoque_db_helper.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscurePassword = true;
  final _dbHelper = EstoqueDbHelper();

  late final AnimationController _particlesController;
  late final AnimationController _fadeController;
  late final AnimationController _sideBarShimmerController;

  static const String _lastLoggedInUserKey = 'lastLoggedInUser';

  // Cores da Identidade Visual
  static const Color bg = Color(0xFF050A14);
  static const Color surface = Color(0xFF0B1220);
  static const Color surface2 = Color(0xFF101B34);
  static const Color primary = Color(0xFF4DA3FF);
  static const Color accent = Color(0xFF5EF7C5);
  static const Color danger = Color(0xFFFF5C8A);
  static const Color borderSoft = Color(0x18FFFFFF);

  // Configurações de API
  static const String _authEndpoint =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _authEmail = 'suporte.wms';
  static const String _authSenha = '123456';
  static const int _authUsuarioId = 21578;

  @override
  void initState() {
    super.initState();
    _carregarUltimoUsuario();

    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeController.forward();

    // Inicializa shimmer barra lateral de forma segura
    _sideBarShimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _particlesController.dispose();
    _fadeController.dispose();
    _sideBarShimmerController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _carregarUltimoUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUser = prefs.getString(_lastLoggedInUserKey);
    if (lastUser != null && lastUser.isNotEmpty) {
      _userController.text = lastUser;
    }
  }

  void _salvarUltimoUsuario(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLoggedInUserKey, username);
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _loading = true);
      HapticFeedback.lightImpact();

      final username = _userController.text.trim();

      try {
        final apiKey = await _obterChaveApi();

        final response = await http
            .get(Uri.parse('http://168.190.90.2:5000/consulta/usuarios'))
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          bool usuarioEncontrado = _verificarUsuarioNaLista(data, username);

          if (usuarioEncontrado) {
            await _dbHelper.salvarUsuarioLocal(username);
            _salvarUltimoUsuario(username);
            _navegarParaHome(username, apiKey);
          } else {
            _showError('Usuário não autorizado no servidor.');
          }
        } else {
          throw Exception("Erro servidor");
        }
      } catch (e) {
        print('Tentando login offline devido a: $e');

        bool autorizadoLocalmente = await _dbHelper.verificarUsuarioLocal(
          username,
        );

        if (autorizadoLocalmente) {
          _salvarUltimoUsuario(username);
          _navegarParaHome(username, "OFFLINE_SESSION");

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "Modo Offline: Acesso concedido via cache local.",
              ),
              backgroundColor: surface2,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        } else {
          _showError(
            'Sem conexão e usuário não encontrado localmente. Conecte-se à rede para o primeiro acesso.',
          );
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  bool _verificarUsuarioNaLista(dynamic data, String username) {
    final userLower = username.toLowerCase();
    if (data is Map && data['usuarios'] is List) {
      return (data['usuarios'] as List).any(
        (u) => u.toString().trim().toLowerCase() == userLower,
      );
    } else if (data is List) {
      return data.any((u) => u.toString().trim().toLowerCase() == userLower);
    }
    return false;
  }

  void _navegarParaHome(String username, String key) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeMenuScreen(conferente: username, apiKey: key),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<String> _obterChaveApi() async {
    final response = await http.post(
      Uri.parse(_authEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': _authEmail,
        'senha': _authSenha,
        'usuarioID': _authUsuarioId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Falha ao autenticar. Código: ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final redirect = body['redirecionarPara']?.toString();
    if (redirect == null || redirect.isEmpty) {
      throw Exception('Resposta de autenticação inválida.');
    }

    try {
      final redirectUri = Uri.parse(redirect);
      final token = redirectUri.queryParameters.values.firstWhere(
        (value) => value.startsWith('ey'),
        orElse: () => '',
      );
      if (token.isNotEmpty) return token;
    } catch (_) {}

    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect);
    if (match != null) {
      return match.group(1)!;
    }

    throw Exception('Não foi possível extrair a chave da API.');
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isObscure = false,
    VoidCallback? onVisibilityToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: primary.withOpacity(0.7), size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isObscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 22,
                ),
                onPressed: onVisibilityToggle,
              )
            : null,
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: borderSoft, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: danger.withOpacity(0.5), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: danger, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 20,
          horizontal: 20,
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [Color(0xFF0B1220), Color(0xFF050A14)],
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(size: screenSize, painter: _GridPainter()),

            AnimatedBuilder(
              animation: _particlesController,
              builder: (context, child) {
                return CustomPaint(
                  size: screenSize,
                  painter: _ParticlesPainter(
                    animation: _particlesController.value,
                  ),
                );
              },
            ),

            Positioned(
              top: -180,
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [primary.withOpacity(0.15), Colors.transparent],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: -150,
              right: -120,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [accent.withOpacity(0.1), Colors.transparent],
                  ),
                ),
              ),
            ),

            FadeTransition(
              opacity: _fadeController,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Shimmer.fromColors(
                          baseColor: primary,
                          highlightColor: accent,
                          period: const Duration(seconds: 2),
                          child: const Text(
                            'TracX',
                            style: TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -2.0,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Color(0x40000000),
                                  offset: Offset(0, 8),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'Sistema de Gestão',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.4),
                            letterSpacing: 1.2,
                          ),
                        ),

                        const SizedBox(height: 64),

                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            color: surface.withOpacity(0.6),
                            border: Border.all(color: borderSoft, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 40,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(32),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // =======================
                                    // Barra lateral com shimmer contínuo
                                    // =======================
                                    AnimatedBuilder(
                                      animation: _sideBarShimmerController,
                                      builder: (context, child) {
                                        return Container(
                                          width: 4,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            gradient: LinearGradient(
                                              colors: [primary, accent],
                                              stops: [
                                                (_sideBarShimmerController
                                                            .value -
                                                        0.3)
                                                    .clamp(0.0, 1.0),
                                                (_sideBarShimmerController
                                                            .value +
                                                        0.3)
                                                    .clamp(0.0, 1.0),
                                              ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      "Acesso ao Sistema",
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 32),

                                _buildModernTextField(
                                  controller: _userController,
                                  label: "Conferente",
                                  icon: Icons.person_rounded,
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? "Informe o usuário"
                                      : null,
                                ),

                                const SizedBox(height: 20),

                                _buildModernTextField(
                                  controller: _passwordController,
                                  label: "Senha",
                                  icon: Icons.lock_rounded,
                                  isPassword: true,
                                  isObscure: _obscurePassword,
                                  onVisibilityToggle: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? "Informe a senha"
                                      : null,
                                ),

                                const SizedBox(height: 36),

                                SizedBox(
                                  width: double.infinity,
                                  height: 58,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _login,
                                    style:
                                        ElevatedButton.styleFrom(
                                          backgroundColor: primary,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          disabledBackgroundColor: primary
                                              .withOpacity(0.5),
                                          shadowColor: primary.withOpacity(0.4),
                                        ).copyWith(
                                          elevation: MaterialStateProperty.all(
                                            8,
                                          ),
                                        ),
                                    child: _loading
                                        ? SizedBox(
                                            height: 26,
                                            width: 26,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 3,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: const [
                                              Text(
                                                "ENTRAR",
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 48),

                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: surface.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: borderSoft, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.security_rounded,
                                    size: 14,
                                    color: accent.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Conexão Segura",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "© 2025 - Stik Tech",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.25),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Grid de fundo sutil
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..strokeWidth = 0.7;

    const spacing = 44.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }

    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// Partículas flutuantes
class _ParticlesPainter extends CustomPainter {
  final double animation;

  _ParticlesPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    const primary = Color(0xFF4DA3FF);
    const accent = Color(0xFF5EF7C5);

    // Partículas principais
    for (int i = 0; i < 30; i++) {
      final seed = i * 137.508;
      final x = (math.sin(seed) * 0.5 + 0.5) * size.width;
      final baseY = (math.cos(seed * 0.7) * 0.5 + 0.5) * size.height;
      final y = (baseY + (animation * 180)) % size.height;
      final radius = 1.0 + (math.sin(seed * 1.3) * 0.5 + 0.5) * 1.2;

      final distanceFromCenter =
          (y - size.height / 2).abs() / (size.height / 2);
      final opacity = ((1.0 - distanceFromCenter) * 0.15).clamp(0.0, 1.0);

      paint.color = primary.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    // Partículas secundárias
    for (int i = 0; i < 12; i++) {
      final seed = i * 234.567;
      final x = (math.cos(seed * 1.2) * 0.5 + 0.5) * size.width;
      final baseY = (math.sin(seed * 0.8) * 0.5 + 0.5) * size.height;
      final y = (baseY - (animation * 120)) % (size.height + 100) - 50;

      final pulseValue = math.sin((animation + seed) * math.pi * 2);
      final radius = 1.4 + pulseValue * 0.7;

      final distanceFromCenter =
          (y - size.height / 2).abs() / (size.height / 2);
      final baseOpacity = ((1.0 - distanceFromCenter) * 0.18).clamp(0.0, 1.0);
      final opacity = (baseOpacity * (0.6 + pulseValue * 0.4)).clamp(0.0, 1.0);

      paint.color = accent.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
