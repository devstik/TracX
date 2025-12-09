import 'dart:convert';
import 'package:tracx/screens/home_menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para feedback tátil
import 'package:http/http.dart' as http;
// ** IMPORTANTE: Certifique-se de que este import está correto **
import 'package:tracx/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscurePassword = true;

  // --- Credenciais Admin Offline (Para checagem local) ---
  static const String _adminUsernameCheck = 'admin';
  static const String _adminPasswordCheck = 'admin';
  // -------------------------------------------------------

  // Cores da Identidade Visual
  static const Color primaryColor = Color(0xFFb41c1c); // Vermelho da marca
  static const Color darkText = Color(0xFF1F2937); // Cinza escuro para texto
  static const Color lightBg = Color(0xFFF9FAFB); // Fundo da tela (Off-White)
  static const Color inputFill = Color(
    0xFFF3F4F6,
  ); // Fundo dos inputs (Cinza claro)

  // Configurações de API (Mantidas originais)
  static const String _authEndpoint =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _authEmail = 'suporte.wms';
  static const String _authSenha = '123456';
  static const int _authUsuarioId = 21578;

  // --- LÓGICA DE LOGIN MODIFICADA PARA OFFLINE ---
  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _loading = true);
      HapticFeedback.lightImpact(); // Feedback tátil ao iniciar o login

      final username = _userController.text.trim();
      final password = _passwordController.text.trim();
      String? apiKey;

      // 1. TENTATIVA DE LOGIN ADMIN OFFLINE
      if (username.toLowerCase() == _adminUsernameCheck &&
          password == _adminPasswordCheck) {
        // Chama a função da AuthService para salvar o token admin no storage
        final loginSucesso = await AuthService.loginAdminOffline(
          username,
          password,
        );

        if (loginSucesso) {
          // Agora acessando o token público
          apiKey = AuthService.offlineAdminToken;
          _navegarParaHome(username, apiKey!);
          return; // Sai do processo de login
        }
      }

      // 2. TENTATIVA DE LOGIN ONLINE (Tradicional)
      // Se não foi o login admin ou o login admin falhou, tenta o online.
      try {
        // Primeiro, obtém a chave da API (Token de Serviço)
        apiKey = await _obterChaveApi();

        // Segundo, consulta o endpoint de usuários (Auth/Permissão)
        final response = await http.get(
          Uri.parse('http://168.190.90.2:5000/consulta/usuarios'),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          bool usuarioEncontrado = false;
          String? mensagemErro;

          if (data is Map<String, dynamic>) {
            if (data['usuarios'] is List) {
              final usuarios = (data['usuarios'] as List).map(
                (user) => user.toString().trim().toLowerCase(),
              );
              usuarioEncontrado = usuarios.contains(username.toLowerCase());
            }

            mensagemErro =
                data['message']?.toString() ?? 'Usuário não encontrado.';
          } else if (data is List) {
            usuarioEncontrado = data
                .map((user) => user.toString().trim().toLowerCase())
                .contains(username.toLowerCase());
            if (!usuarioEncontrado) {
              mensagemErro = 'Usuário não encontrado.';
            }
          } else {
            mensagemErro = 'Formato de resposta inválido do servidor.';
          }

          if (usuarioEncontrado) {
            _navegarParaHome(username, apiKey!);
          } else {
            _showError(mensagemErro ?? 'Usuário não encontrado.');
          }
        } else {
          _showError(
            'Erro ao consultar usuários. Código: ${response.statusCode}',
          );
        }
      } catch (e) {
        _showError('Erro de conexão: Verifique sua rede ou dados. ($e)');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _navegarParaHome(String username, String apiKey) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeMenuScreen(conferente: username, apiKey: apiKey),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  // Widget auxiliar para TextFields modernos
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
      style: const TextStyle(fontWeight: FontWeight.w500, color: darkText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.bold,
        ),
        prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isObscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.grey[400],
                  size: 20,
                ),
                onPressed: onVisibilityToggle,
              )
            : null,
        filled: true,
        fillColor: inputFill, // Fundo cinza claro
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none, // Sem borda padrão
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: primaryColor,
            width: 1.5,
          ), // Borda fina ao focar
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.red.shade100, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 20,
        ),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg, // Fundo Off-White moderno
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. LOGO TRACX (Tipografia Moderna)
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2.0,
                    fontFamily: 'Segoe UI',
                  ),
                  children: [
                    TextSpan(
                      text: 'Trac',
                      style: TextStyle(color: darkText),
                    ),
                    TextSpan(
                      text: 'X',
                      style: TextStyle(
                        color: primaryColor,
                      ), // O "X" em vermelho
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gestão Logística Inteligente',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 48),

              // 2. CARD DE LOGIN (Container principal)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Acesso",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: darkText,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // CAMPO CONFERENTE
                      _buildModernTextField(
                        controller: _userController,
                        label: "Conferente",
                        icon: Icons.person_rounded,
                        validator: (value) => value == null || value.isEmpty
                            ? "Informe o usuário"
                            : null,
                      ),

                      const SizedBox(height: 16),

                      // CAMPO SENHA
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
                        validator: (value) => value == null || value.isEmpty
                            ? "Informe a senha"
                            : null,
                      ),

                      const SizedBox(height: 32),

                      // BOTÃO DE LOGIN
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "ENTRAR",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ), // Fim do Container (Card de Login)
              // 3. Rodapé discreto (Fora do Card, mas dentro da tela)
              const SizedBox(height: 32),
              Text(
                "© 2025 - Stik Tech ",
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              const SizedBox(height: 24), // Espaçamento extra no final
            ],
          ),
        ),
      ),
    );
  }
}
