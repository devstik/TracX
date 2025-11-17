import 'dart:convert';
import 'package:tracx/screens/home_menu_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  // Cores Consistentes com a identidade visual (Vermelho e Branco)
  static const Color primaryColor = Color(0xFFb41c1c); // Vermelho forte (base)
  static const Color focusColor = Color(
    0xFFd32f2f,
  ); // Vermelho mais claro (foco)

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _loading = true);

      final username = _userController.text.trim();
      final password = _passwordController.text.trim();

      try {
        final response = await http.post(
          Uri.parse('http://168.190.90.2:5000/consulta/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'usuario': username, 'senha': password}),
        );

        final data = jsonDecode(response.body);

        if (response.statusCode == 200 && data['success'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomeMenuScreen(conferente: username),
            ),
          );
        } else {
          // Exibição de erro otimizada para ser mais simples
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Usuário ou senha inválidos'),
              backgroundColor: primaryColor,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro de conexão: Verifique sua rede.'),
            backgroundColor: Colors.orange,
          ),
        );
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Fundo branco limpo
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Container(
            // ✅ ALTERADO: Gradiente cinza para o fundo do Card
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.grey.shade200, Colors.grey.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15), // Sombra ajustada
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(
                32.0,
              ), // Padding aumentado para mais "respiro"
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo STIK
                    Container(
                      height: 80,
                      child: Image.asset(
                        'assets/logo_login.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Título e Subtítulo Modernos
                    const Text(
                      'Bem-vindo!',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Entre com suas credenciais para continuar.',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Campo Conferente
                    TextFormField(
                      controller: _userController,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: "Conferente",
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(
                          Icons.person_outline,
                          color: primaryColor,
                        ), // Ícone moderno e cor vermelha
                        filled: true,
                        fillColor: Colors.white, // Input field continua branco
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 20,
                        ), // Melhor padding
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            12,
                          ), // Mais arredondado
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade300, // Borda cinza suave
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: focusColor, // Borda vermelha de foco
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? "Informe o nome de usuário"
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Campo Senha
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: "Senha",
                        labelStyle: TextStyle(color: Colors.grey[600]),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: primaryColor,
                        ), // Ícone moderno e cor vermelha
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: primaryColor.withOpacity(0.6),
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white, // Input field continua branco
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 20,
                        ), // Melhor padding
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: focusColor,
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? "Informe a senha"
                          : null,
                    ),
                    const SizedBox(height: 32),

                    // Botão de Login
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _loading
                          ? const CircularProgressIndicator(color: primaryColor)
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _login,
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ), // Ícone de seta moderna
                                label: const Text(
                                  "ENTRAR",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      primaryColor, // Vermelho forte
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      12,
                                    ), // Mais arredondado
                                  ),
                                  elevation:
                                      8, // Elevação para o efeito 3D suave
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
