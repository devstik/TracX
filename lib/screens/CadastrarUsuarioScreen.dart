import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CadastrarUsuarioScreen extends StatefulWidget {
  const CadastrarUsuarioScreen({Key? key}) : super(key: key);

  @override
  _CadastrarUsuarioScreenState createState() => _CadastrarUsuarioScreenState();
}

class _CadastrarUsuarioScreenState extends State<CadastrarUsuarioScreen> {
  final _formKey = GlobalKey<FormState>();
  final _novoUsuarioController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  // Cor principal consistente com as outras telas
  final Color _primaryColor = const Color(0xFFC62828); // Vermelho Escuro

  void _showSnackBar(String message, {Color color = Colors.red}) {
    // Fecha qualquer SnackBar anterior e mostra a nova
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Define o estilo moderno para os campos de texto
  InputDecoration _inputDecoration(
    String labelText,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: Colors.grey.shade600),
      prefixIcon: Icon(icon, color: _primaryColor.withOpacity(0.7)),
      suffixIcon: suffixIcon,
      // Estilo preenchido e suave
      filled: true,
      fillColor: Colors.grey.shade50,
      // Borda padrão arredondada e sutil
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      // Borda quando o campo está focado (destaque com a cor principal)
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  void _salvarNovoUsuario() async {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus(); // Fecha o teclado
      setState(() => _loading = true);

      final novoUsuario = _novoUsuarioController.text.trim();
      final novaSenha = _novaSenhaController.text.trim();

      try {
        final response = await http.post(
          Uri.parse('http://168.190.90.2:5000/consulta/cadastro'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'usuario': novoUsuario, 'senha': novaSenha}),
        );

        final data = jsonDecode(response.body);
        final success = response.statusCode == 201 && data['success'] == true;

        _showSnackBar(
          data['message'] ??
              (success
                  ? 'Usuário cadastrado com sucesso!'
                  : 'Erro desconhecido'),
          color: success ? Colors.green.shade700 : Colors.red.shade700,
        );

        if (success) {
          // Limpa os campos após o cadastro
          _novoUsuarioController.clear();
          _novaSenhaController.clear();
          // Navega de volta após sucesso
          Navigator.of(context).pop();
        }
      } catch (e) {
        _showSnackBar('Erro de conexão: $e', color: Colors.red.shade900);
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100, // Fundo levemente cinza
      appBar: AppBar(
        title: const Text(
          'Novo Cadastro',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        elevation: 0, // Visual plano
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Container(
            // O formulário agora é um "Cartão Flutuante"
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.1),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 50,
                    color: Color(0xFFC62828),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cadastrar Novo Conferente',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Novo Usuário
                  TextFormField(
                    controller: _novoUsuarioController,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration(
                      'Nome de Usuário',
                      Icons.person_outline,
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'O nome de usuário é obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Nova Senha
                  TextFormField(
                    controller: _novaSenhaController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    decoration: _inputDecoration(
                      'Definir Senha',
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: _primaryColor.withOpacity(0.7),
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'A senha é obrigatória';
                      if (value.length < 6)
                        return 'A senha deve ter ao menos 6 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 40),

                  // Botão de Salvar
                  SizedBox(
                    height: 56,
                    child: _loading
                        ? Center(
                            child: CircularProgressIndicator(
                              color: _primaryColor,
                              strokeWidth: 3,
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _salvarNovoUsuario,
                            icon: const Icon(Icons.add_task_rounded, size: 24),
                            label: const Text('Cadastrar Usuário'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
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
    );
  }
}
