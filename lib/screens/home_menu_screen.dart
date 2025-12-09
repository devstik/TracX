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
import 'package:tracx/screens/MapaProducaoScreen.dart';
import 'package:tracx/screens/ConsultaMapaProducaoScreen.dart';

class HomeMenuScreen extends StatefulWidget {
  final String conferente;
  final String? apiKey;
  const HomeMenuScreen({super.key, required this.conferente, this.apiKey});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<HomeMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  final List<String> _admins = const ['Joao', 'Leide', 'Lidinaldo', 'admin'];
  bool get _isAdmin => _admins.contains(widget.conferente);

  @override
  void initState() {
    super.initState();
    if (widget.apiKey != null) {
      debugPrint('[HomeMenu] API key obtida para uso seguro.');
    }
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

  void _showAdminMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Administração',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.blue),
              title: const Text('Cadastrar Usuário'),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(context, CadastrarUsuarioScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset, color: Colors.green),
              title: const Text('Alterar Senha'),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(context, AlterarSenhaScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.list, color: Colors.purple),
              title: const Text('Listar Usuários'),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(context, ListarUsuariosScreen());
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 📦 SEÇÃO 1: REGISTRAR PEDIDOS (3 itens)
    final List<_MenuItem> registrarItems = [
      _MenuItem(
        title: 'Registrar',
        icon: Icons.app_registration,
        color: Colors.red.shade700,
        onTap: () => _navigateWithTransition(
          context,
          RegistroPrincipalScreen(conferente: widget.conferente),
        ),
      ),
      _MenuItem(
        title: 'Localização',
        icon: Icons.location_on,
        color: Colors.purple.shade700,
        onTap: () => _navigateWithTransition(
          context,
          Localizacaoscreen(conferente: widget.conferente, isAdmin: _isAdmin),
        ),
      ),
      _MenuItem(
        title: 'Mapa Produção',
        icon: Icons.map_outlined,
        color: Colors.indigo.shade600,
        onTap: () => _navigateWithTransition(context, MapaProducaoScreen()),
      ),
    ];

    // 📊 SEÇÃO 2: ANÁLISE DE DADOS (3 itens)
    final List<_MenuItem> analiseItems = [
      _MenuItem(
        title: 'Registros',
        icon: Icons.list_alt,
        color: Colors.green.shade700,
        onTap: () => _navigateWithTransition(context, ListaRegistrosScreen()),
      ),
      _MenuItem(
        title: 'Fluxo',
        icon: Icons.track_changes,
        color: Colors.cyan.shade700,
        onTap: () {
          _navigateWithTransition(
            context,
            HistoricoMovimentacaoScreen(
              nrOrdem: 0,
              titulo: 'Movimentação Geral',
            ),
          );
        },
      ),
      _MenuItem(
        title: 'Consultar Mapas',
        icon: Icons.analytics_outlined,
        color: Colors.deepPurple.shade600,
        onTap: () => _navigateWithTransition(
          context,
          const ConsultaMapaProducaoScreen(),
        ),
      ),
    ];

    final size = MediaQuery.of(context).size;
    final bool isPhone = size.width < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER COM BOTÃO ADMIN
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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
                      blurRadius: 8,
                      offset: const Offset(0, 4),
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
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                            TextSpan(
                              text: widget.conferente,
                              style: const TextStyle(
                                fontSize: 18,
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
                    const SizedBox(width: 12),

                    // BOTÃO ADMIN (só aparece para administradores)
                    if (_isAdmin) ...[
                      GestureDetector(
                        onTap: _showAdminMenu,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orange.shade100,
                          ),
                          child: Icon(
                            Icons.admin_panel_settings,
                            color: Colors.orange.shade700,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // BOTÃO LOGOUT
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Row(
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Sair do Sistema'),
                                ],
                              ),
                              content: const Text(
                                'Tem certeza que deseja sair?',
                                style: TextStyle(fontSize: 16),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context); // Fecha o dialog
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => LoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Sair',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
                        ),
                        child: const Icon(
                          Icons.logout,
                          color: Colors.black87,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isPhone ? 16 : 24,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TÍTULO SEÇÃO 1
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_document,
                            color: Colors.red.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Registrar Pedidos',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // GRID SEÇÃO 1 (3 colunas)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: registrarItems.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.0,
                          ),
                      itemBuilder: (context, index) {
                        return _buildAnimatedCard(registrarItems[index], index);
                      },
                    ),

                    const SizedBox(height: 24),

                    // TÍTULO SEÇÃO 2
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bar_chart,
                            color: Colors.green.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Análise de Dados',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // GRID SEÇÃO 2 (3 colunas)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: analiseItems.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 1.0,
                          ),
                      itemBuilder: (context, index) {
                        return _buildAnimatedCard(
                          analiseItems[index],
                          index + registrarItems.length,
                        );
                      },
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedCard(_MenuItem item, int index) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double start = index * 0.08;
        final double end = start + 0.4;
        double opacity;
        if (_controller.value < start) {
          opacity = 0.0;
        } else if (_controller.value > end) {
          opacity = 1.0;
        } else {
          opacity = (_controller.value - start) / (end - start);
        }
        final double translateY = 30 * (1 - opacity);
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: _isHovered
                        ? [widget.color.withOpacity(0.25), Colors.white]
                        : [Colors.grey.shade200, Colors.grey.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isHovered ? 0.2 : 0.12),
                      blurRadius: _isHovered ? 12 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, size: 28, color: widget.color),
                    const SizedBox(height: 6),
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
