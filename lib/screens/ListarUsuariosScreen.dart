import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ListarUsuariosScreen extends StatefulWidget {
  const ListarUsuariosScreen({Key? key}) : super(key: key);

  @override
  _ListarUsuariosScreenState createState() => _ListarUsuariosScreenState();
}

class _ListarUsuariosScreenState extends State<ListarUsuariosScreen>
    with SingleTickerProviderStateMixin {
  List<String> _usuarios = [];
  bool _loading = true;

  late AnimationController _animationController;

  // Cor principal consistente e moderna
  final Color _primaryColor = const Color(0xFFC62828);

  final String _baseUrl = 'http://168.190.90.2:5000/consulta/usuarios';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _carregarUsuarios();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _carregarUsuarios() async {
    setState(() => _loading = true);
    try {
      final response = await http.get(Uri.parse(_baseUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() => _usuarios = data.cast<String>());
      } else {
        _showSnackBar(
          'Erro ao carregar usuários. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      _showSnackBar('Erro de conexão: $e');
    } finally {
      setState(() {
        _loading = false;
        if (_usuarios.isNotEmpty) {
          _animationController.forward(from: 0);
        }
      });
    }
  }

  void _showSnackBar(String message, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- NOVA FUNÇÃO: DIALOG DE OPÇÕES DO USUÁRIO ---
  Future<void> _mostrarOpcoesUsuario(String usuario) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Opções de Usuário: $usuario',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.edit_note, color: _primaryColor),
                title: const Text('Editar Permissões/Telas'),
                subtitle: const Text(
                  'Configurar o que o usuário pode acessar (Futuro)',
                ),
                onTap: () {
                  // TODO: Implementar a navegação para a tela de edição de permissões
                  Navigator.pop(context, 'edit');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.red,
                ),
                title: const Text(
                  'Excluir Usuário',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context, 'delete');
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );

    if (result == 'delete') {
      _excluirUsuario(usuario);
    }
    // Futuramente, você pode adicionar 'else if (result == 'edit') { ... }'
  }
  // -------------------------------------------------------------------------

  Future<void> _excluirUsuario(String usuario) async {
    // Código de exclusão foi mantido e simplificado
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Confirmação de Exclusão'),
        content: Text(
          'Deseja realmente excluir o usuário "$usuario"? Esta ação é irreversível.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.delete(Uri.parse('$_baseUrl/$usuario'));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showSnackBar('Usuário excluído com sucesso!', color: Colors.green);
        _carregarUsuarios();
      } else {
        _showSnackBar(
          data['message'] ?? 'Erro ao excluir usuário',
          color: Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar('Erro de conexão: $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.grey.shade50, // Fundo levemente cinza para contraste
      appBar: AppBar(
        title: const Text(
          'Gerenciar Usuários', // Título mais focado em gerenciamento
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: _primaryColor))
            : _usuarios.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_search,
                      size: 90,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum usuário cadastrado',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Puxe para baixo para tentar novamente.',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _carregarUsuarios,
                color: _primaryColor,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  itemCount: _usuarios.length,
                  itemBuilder: (context, index) {
                    final usuario = _usuarios[index];
                    final animation =
                        Tween<Offset>(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _animationController,
                            curve: Interval(
                              (index * 0.08).clamp(0.0, 1.0),
                              1.0,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        );

                    return FadeTransition(
                      opacity: _animationController,
                      child: SlideTransition(
                        position: animation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 3,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              // Abre o modal de opções ao tocar no item
                              onTap: () => _mostrarOpcoesUsuario(usuario),
                              leading: CircleAvatar(
                                backgroundColor: _primaryColor.withOpacity(0.1),
                                radius: 24,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: _primaryColor,
                                  size: 28,
                                ),
                              ),
                              title: Text(
                                usuario,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text(
                                'Toque para gerenciar/excluir', // Subtítulo mais informativo
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              // Botão de reticências para abrir as opções
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.more_vert,
                                  color: _primaryColor,
                                ),
                                tooltip: 'Opções do Usuário',
                                onPressed: () => _mostrarOpcoesUsuario(usuario),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
