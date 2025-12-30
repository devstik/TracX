import 'dart:convert';
import 'package:tracx/screens/home_menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para feedback tátil
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Importação para persistência
import '../services/estoque_db_helper.dart';

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
  final _dbHelper = EstoqueDbHelper();

  // Chave para SharedPreferences
  static const String _lastLoggedInUserKey = 'lastLoggedInUser';

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

  @override
  void initState() {
    super.initState();
    _carregarUltimoUsuario();
  }

  // Novo método: Carrega o último usuário salvo e preenche o campo
  void _carregarUltimoUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUser = prefs.getString(_lastLoggedInUserKey);
    if (lastUser != null && lastUser.isNotEmpty) {
      _userController.text = lastUser;
    }
  }

  // Novo método: Salva o usuário logado
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
        // 1. Tenta obter a chave da API (Necessita Internet)
        final apiKey = await _obterChaveApi();

        // 2. Tenta validar usuário no servidor
        final response = await http
            .get(Uri.parse('http://168.190.90.2:5000/consulta/usuarios'))
            .timeout(
              const Duration(seconds: 5),
            ); // Timeout curto para não travar o user

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          bool usuarioEncontrado = _verificarUsuarioNaLista(data, username);

          if (usuarioEncontrado) {
            // SUCESSO ONLINE: Salva no SQLite para acessos futuros offline
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
        // --- FLUXO OFFLINE ---
        print('Tentando login offline devido a: $e');

        bool autorizadoLocalmente = await _dbHelper.verificarUsuarioLocal(
          username,
        );

        if (autorizadoLocalmente) {
          _salvarUltimoUsuario(username);
          // Nota: Como estamos offline, passamos uma String vazia ou 'OFFLINE' como apiKey
          _navegarParaHome(username, "OFFLINE_SESSION");

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Modo Offline: Acesso concedido via cache local."),
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

  // Auxiliar para navegação
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
                "© 2025 - Stik Tech",
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
