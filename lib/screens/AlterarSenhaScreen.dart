import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AlterarSenhaScreen extends StatefulWidget {
  const AlterarSenhaScreen({super.key});

  @override
  _AlterarSenhaScreenState createState() => _AlterarSenhaScreenState();
}

class _AlterarSenhaScreenState extends State<AlterarSenhaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuarioController = TextEditingController();
  final _novaSenhaController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  void _alterarSenha() async {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus(); // fecha o teclado
      setState(() => _loading = true);
      final usuario = _usuarioController.text.trim();
      final novaSenha = _novaSenhaController.text.trim();

      try {
        final response = await http.put(
          Uri.parse('http://168.190.90.2:5000/consulta/usuarios/senha'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'usuario': usuario, 'senha': novaSenha}),
        );

        final data = jsonDecode(response.body);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Erro'),
            backgroundColor: response.statusCode == 200
                ? Colors.green
                : Colors.red,
          ),
        );

        if (response.statusCode == 200) {
          Navigator.pop(context);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro de conexão: $e'),
            backgroundColor: Colors.red,
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
      backgroundColor: Colors.white, // mantém branco
      appBar: AppBar(
        backgroundColor: const Color(0xFFCD1818),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[300], // mantém cinza prateado leve
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              autovalidateMode:
                  AutovalidateMode.onUserInteraction, // feedback imediato
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Atualize sua senha',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Usuário
                  TextFormField(
                    controller: _usuarioController,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Usuário',
                      labelStyle: TextStyle(color: Colors.grey[700]),
                      prefixIcon: Icon(Icons.person, color: Colors.grey[700]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 16),

                  // Nova senha
                  TextFormField(
                    controller: _novaSenhaController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Nova Senha',
                      labelStyle: TextStyle(color: Colors.grey[700]),
                      prefixIcon: Icon(Icons.lock, color: Colors.grey[700]),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey[700],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Campo obrigatório';
                      if (v.length < 6)
                        return 'A senha deve ter ao menos 6 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Botão
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFCD1818),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _alterarSenha,
                            icon: const Icon(Icons.check),
                            label: const Text('Alterar Senha'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFCD1818),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
