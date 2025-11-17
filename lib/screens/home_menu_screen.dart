import 'package:tracx/screens/ListaRegistrosScreen.dart';
import 'package:tracx/views/RegistroEmbalagem.dart' as embalagem;
import 'package:tracx/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:tracx/screens/CadastrarUsuarioScreen.dart';
import 'package:tracx/screens/ListarUsuariosScreen.dart';
import 'package:tracx/screens/AlterarSenhaScreen.dart';
import 'package:tracx/views/RegistroTinturaria.dart';
import 'package:tracx/screens/LocalizacaoScreen.dart';
import 'package:tracx/screens/HistoricoMovimentacaoScreen.dart';
import 'package:tracx/screens/RegistroPrincipalScreen.dart';

class HomeMenuScreen extends StatefulWidget {
  final String conferente;
  const HomeMenuScreen({super.key, required this.conferente});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  // A lista de admins é necessária para determinar a função
  final List<String> _admins = const ['Joao', 'Leide', 'Lidinaldo'];

  // NOVO: Determina se o usuário atual é administrador
  bool get _isAdmin => _admins.contains(widget.conferente);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 🔹 Função genérica para aplicar transição personalizada
  void _navigateWithTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0.2, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 💡 MUDANÇA 1: Reorganização dos itens para 3 (Embalagem, Localização, Tinturaria)
    // Os demais (Relatório e Usuários) virão abaixo na ordem em que forem definidos.
    final List<_MenuItem> menuItems = [
      _MenuItem(
        title: 'Registrar', // Novo item principal
        icon: Icons.app_registration, // Ícone sugestivo para Registro
        color: Colors.red.shade700, // Cor de destaque
        onTap: () => _navigateWithTransition(
          context,
          RegistroPrincipalScreen(
            conferente: widget.conferente,
          ), // Navega para a tela com abas
        ),
      ),
      _MenuItem(
        title: 'Localização',
        icon: Icons.location_on,
        color: Colors.purple.shade700,
        onTap: () => _navigateWithTransition(
          context,
          Localizacaoscreen(
            conferente: widget.conferente, // PASSANDO O CONFERENTE
            isAdmin: _isAdmin, // PASSANDO O STATUS ADMIN
          ),
        ),
      ),
      // _MenuItem(
      //   title: 'Raschelina',
      //   icon: Icons.color_lens,
      //   color: Colors.blue.shade700,
      //   onTap: () => _navigateWithTransition(
      //     context,
      //     RegistroScreenTinturaria(conferente: widget.conferente),
      //   ),
      // ),
      // Os itens abaixo ficarão na segunda linha
      _MenuItem(
        title: 'Registros',
        icon: Icons.list_alt, // ícone de lista de registros ou documentos
        color: Colors.green.shade700,
        onTap: () => _navigateWithTransition(context, ListaRegistrosScreen()),
      ),
      _MenuItem(
        title: 'Fluxo', // Nome do card conforme solicitado
        icon: Icons.track_changes, // Ícone sugestivo para rastreamento
        color: Colors.cyan.shade700, // Nova cor para diferenciar
        onTap: () {
          // 🆕 Ação: Navega diretamente para a tela de histórico
          // passando 0 para indicar que é para buscar TUDO.
          _navigateWithTransition(
            context,
            HistoricoMovimentacaoScreen(
              nrOrdem: 0, // Passa 0: Nova lógica no service buscará todos
              titulo: 'Movimentação Geral', // Título fixo
            ),
          );
        },
      ),
    ];

    if (_isAdmin) {
      // Usando o getter _isAdmin
      menuItems.add(
        _MenuItem(
          title: 'Usuários',
          icon: Icons.person,
          color: Colors.orange.shade700,
          onTap: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (context) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_add),
                      title: const Text('Cadastrar Usuário'),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateWithTransition(
                          context,
                          CadastrarUsuarioScreen(),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_reset),
                      title: const Text('Alterar Senha'),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateWithTransition(context, AlterarSenhaScreen());
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.list),
                      title: const Text('Listar Usuários'),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateWithTransition(
                          context,
                          ListarUsuariosScreen(),
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.2),
                  end: Offset.zero,
                ).animate(_fadeAnimation),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade50, Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Bem-vindo, ',
                                style: TextStyle(
                                  fontSize: 20,
                                  color: Colors.black54,
                                ),
                              ),
                              TextSpan(
                                text: widget.conferente,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 16),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => LoginScreen()),
                              (route) => false,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.shade200,
                            ),
                            child: const Icon(
                              Icons.logout,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16), // Diminui o padding geral
                itemCount: menuItems.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // 💡 MUDANÇA 2: Define 3 colunas fixas
                  crossAxisSpacing: 12, // Diminui o espaçamento
                  mainAxisSpacing: 12, // Diminui o espaçamento
                  childAspectRatio: 1.1, // Aumenta um pouco a altura do card
                ),
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final double start = index * 0.1;
                      final double end = start + 0.5;
                      double opacity;
                      if (_controller.value < start) {
                        opacity = 0.0;
                      } else if (_controller.value > end) {
                        opacity = 1.0;
                      } else {
                        opacity = (_controller.value - start) / (end - start);
                      }
                      final double translateY = 50 * (1 - opacity);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.translate(
                          offset: Offset(0, translateY),
                          child: child,
                        ),
                      );
                    },
                    child: _MenuItemCard(
                      title: item.title,
                      icon: item.icon,
                      color: item.color,
                      onTap: item.onTap,
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
}

class _MenuItem {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _MenuItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _MenuItemCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MenuItemCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MenuItemCard> createState() => _MenuItemCardState();
}

class _MenuItemCardState extends State<_MenuItemCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.95,
      upperBound: 1.05,
    );
    _scaleAnimation = _controller.drive(Tween(begin: 1.0, end: 1.05));
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTapDown: (_) => _controller.reverse(),
        onTapUp: (_) => _controller.forward(),
        onTapCancel: () => _controller.forward(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.all(12), // Diminui o padding interno
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: _isHovered
                        ? [widget.color.withOpacity(0.25), Colors.white]
                        : [Colors.grey.shade200, Colors.grey.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isHovered ? 0.25 : 0.15),
                      blurRadius: _isHovered ? 16 : 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 💡 MUDANÇA 3: Diminui o tamanho do ícone de 60 para 40
                    Icon(widget.icon, size: 40, color: widget.color),
                    const SizedBox(height: 8), // Diminui o espaçamento
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 14, // Diminui o tamanho da fonte
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
