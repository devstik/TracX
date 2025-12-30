import 'package:tracx/screens/ListaRegistrosScreen.dart';
import 'package:tracx/views/RegistroEmbalagem.dart' as embalagem;
import 'package:tracx/screens/login_screen.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:tracx/services/estoque_db_helper.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:tracx/services/update_service.dart';

class HomeMenuScreen extends StatefulWidget {
  final String conferente;
  final String? apiKey;

  const HomeMenuScreen({super.key, required this.conferente, this.apiKey});

  @override
  State<HomeMenuScreen> createState() => _HomeMenuScreenState();
}

final EstoqueDbHelper _dbHelper = EstoqueDbHelper();

class _HomeMenuScreenState extends State<HomeMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  // Dados da produção
  Map<String, dynamic>? _dadosProducao;
  bool _isLoadingProducao = true;

  Timer? _timerSincronizacao;
  List<Map<String, dynamic>> _dadosGrafico = [];
  bool _carregandoGrafico = false;
  String _ultimaAtualizacao = "Carregando...";

  final List<String> _admins = const ['Joao', 'Leide', 'Lidinaldo'];

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
    _gerenciarDadosProducao();
  }

  Future<void> _gerenciarDadosProducao() async {
    const String tipoCache = 'resumo_home';

    // 1. Tentar carregar dados locais imediatamente para não deixar a tela vazia
    final cacheLocal = await _dbHelper.buscarCacheGrafico(tipoCache);
    if (cacheLocal.isNotEmpty) {
      _atualizarInterfaceComCache(cacheLocal);
    }

    // 2. Verificar se precisa de atualização (se cache está vazio ou tem mais de 1h)
    bool precisaAtualizar = true;
    if (cacheLocal.isNotEmpty) {
      DateTime ultimaVez = DateTime.parse(cacheLocal.first['atualizado_em']);
      if (DateTime.now().difference(ultimaVez).inHours < 1) {
        precisaAtualizar = false;
        if (mounted) setState(() => _isLoadingProducao = false);
      }
    }

    // 3. Buscar da API se necessário ou se o cache estiver vazio
    if (precisaAtualizar) {
      await _buscarDadosAPIeSalvar(tipoCache);
    }
  }

  Future<void> _buscarDadosAPIeSalvar(String tipo) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://168.190.90.2:5000/consulta/Tracx/resumo_producao',
            ),
          )
          .timeout(
            const Duration(seconds: 7),
          ); // Timeout para evitar espera infinita

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Prepara os dados no formato esperado pelo seu método salvarCacheGrafico
        List<Map<String, dynamic>> paraSalvar = [
          {
            'periodo': 'DiasProduzidosMes',
            'valor': (data['DiasProduzidosMes'] ?? 0).toDouble(),
          },
          {
            'periodo': 'PrevisaoProducao',
            'valor': (data['PrevisaoProducao'] ?? 0).toDouble(),
          },
          {
            'periodo': 'TotalProducao',
            'valor': (data['TotalProducao'] ?? 0).toDouble(),
          },
        ];

        await _dbHelper.salvarCacheGrafico(paraSalvar, tipo);

        // Recarrega do banco para garantir consistência
        final novoCache = await _dbHelper.buscarCacheGrafico(tipo);
        _atualizarInterfaceComCache(novoCache);
      }
    } catch (e) {
      debugPrint('Rede indisponível. Mantendo dados locais.');
      if (mounted) setState(() => _isLoadingProducao = false);
    }
  }

  void _atualizarInterfaceComCache(List<Map<String, dynamic>> cache) {
    if (!mounted) return;

    setState(() {
      _dadosProducao = {
        "DiasProduzidosMes": cache.firstWhere(
          (e) => e['periodo'] == 'DiasProduzidosMes',
        )['valor'],
        "PrevisaoProducao": cache.firstWhere(
          (e) => e['periodo'] == 'PrevisaoProducao',
        )['valor'],
        "TotalProducao": cache.firstWhere(
          (e) => e['periodo'] == 'TotalProducao',
        )['valor'],
      };

      // Extrair e formatar a hora da última atualização
      final DateTime dataDb = DateTime.parse(cache.first['atualizado_em']);
      final String hora = dataDb.hour.toString().padLeft(2, '0');
      final String minuto = dataDb.minute.toString().padLeft(2, '0');
      _ultimaAtualizacao = "Atualizado às $hora:$minuto";

      _isLoadingProducao = false;
    });
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

  void _showUserActionsSheet() {
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
                _navigateWithTransition(context, CadastrarUsuarioScreen());
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
                _navigateWithTransition(context, ListarUsuariosScreen());
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color color = Colors.black87,
  }) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade200,
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: button) : button;
  }

  String _formatarNumero(double valor) {
    return valor
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  @override
  Widget build(BuildContext context) {
    final List<_MenuItem> menuItems = [
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
      if (widget.conferente == 'Joao')
        _MenuItem(
          title: 'Mapa de Produção',
          icon: Icons.map_outlined,
          color: Colors.indigo.shade600,
          onTap: () => _navigateWithTransition(context, MapaProducaoScreen()),
        ),
      _MenuItem(
        title: 'Registros',
        icon: Icons.list_alt,
        color: Colors.green.shade700,
        onTap: () => _navigateWithTransition(context, ListaRegistrosScreen()),
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
    const int crossAxisCount = 3;
    final double gridSpacing = isPhone ? 14 : 20;
    final double childAspectRatio = isPhone ? 0.9 : 1.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
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
                        _buildHeaderIconButton(
                          icon: Icons.system_update_alt,
                          tooltip: 'Verificar atualização',
                          onTap: () =>
                              UpdateService.check(context, showMessages: true),
                          color: Colors.green.shade700,
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(width: 12),
                          _buildHeaderIconButton(
                            icon: CupertinoIcons.person_crop_circle,
                            tooltip: 'Gerenciar usuários',
                            onTap: _showUserActionsSheet,
                            color: Colors.blueAccent,
                          ),
                        ],
                        const SizedBox(width: 12),
                        _buildHeaderIconButton(
                          icon: Icons.logout,
                          tooltip: 'Sair',
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => LoginScreen()),
                              (route) => false,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Grid de Menus
              GridView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: isPhone ? 16 : 32,
                  vertical: isPhone ? 12 : 24,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: menuItems.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: gridSpacing,
                  mainAxisSpacing: gridSpacing,
                  childAspectRatio: childAspectRatio,
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

              // Gráfico de Produção
              if (!_isLoadingProducao && _dadosProducao != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Cabeçalho do Card
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.trending_up,
                                color: Colors.orange.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Previsão Produção',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _ultimaAtualizacao,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          // Gráfico Gauge
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, child) {
                                final totalProducao =
                                    _dadosProducao!['TotalProducao'] as double;
                                final previsaoProducao =
                                    _dadosProducao!['PrevisaoProducao']
                                        as double;
                                final percentual =
                                    (totalProducao / previsaoProducao).clamp(
                                      0.0,
                                      1.0,
                                    );

                                return SizedBox(
                                  height: 140,
                                  child: CustomPaint(
                                    painter: GaugePainter(
                                      percentage:
                                          percentual * _controller.value,
                                      totalProducao: totalProducao,
                                      previsaoProducao: previsaoProducao,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Cards de Valores
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCardValor(
                                  label: 'Produção Atual',
                                  valor:
                                      _dadosProducao!['TotalProducao']
                                          as double,
                                  cor: const Color(0xFF8B1538),
                                  icon: Icons.factory,
                                ),
                                const SizedBox(height: 12),
                                _buildCardValor(
                                  label: 'Previsão do Mês',
                                  valor:
                                      _dadosProducao!['PrevisaoProducao']
                                          as double,
                                  cor: const Color(0xFF9C6BA8),
                                  icon: Icons.timeline,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardValor({
    required String label,
    required double valor,
    required Color cor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatarNumero(valor),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

// CustomPainter para o Gráfico Gauge
class GaugePainter extends CustomPainter {
  final double percentage;
  final double totalProducao;
  final double previsaoProducao;

  GaugePainter({
    required this.percentage,
    required this.totalProducao,
    required this.previsaoProducao,
  });

  String _formatarNumero(double valor) {
    return valor
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.75);
    final radius = math.min(size.width, size.height * 1.5) / 2 - 10;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Background (Previsão)
    final bgPaint = Paint()
      ..color = const Color(0xFFE8D5E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Foreground (Produção Atual)
    final fgPaint = Paint()
      ..color = const Color(0xFF8B1538)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * percentage,
      false,
      fgPaint,
    );

    // Calcular posição do ponto no final do arco de produção
    final endAngle = startAngle + (sweepAngle * percentage);
    final pointX = center.dx + radius * math.cos(endAngle);
    final pointY = center.dy + radius * math.sin(endAngle);
    final pointPosition = Offset(pointX, pointY);

    // Desenhar círculo branco (borda)
    final pointBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pointPosition, 12, pointBorderPaint);

    // Desenhar círculo vermelho (centro)
    final pointPaint = Paint()
      ..color = const Color(0xFF8B1538)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pointPosition, 8, pointPaint);

    // Desenhar label com valor da produção atual acima do ponto
    final labelText = _formatarNumero(totalProducao);
    final labelPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF8B1538),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();

    // Posicionar o texto acima do ponto
    final labelX = pointX - labelPainter.width / 2;
    final labelY = pointY - 30;

    // Fundo branco semi-transparente para o texto
    final labelBgPaint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.fill;

    final labelBgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        labelX - 6,
        labelY - 4,
        labelPainter.width + 12,
        labelPainter.height + 8,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(labelBgRect, labelBgPaint);

    // Desenhar borda do fundo
    final labelBorderPaint = Paint()
      ..color = const Color(0xFF8B1538).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(labelBgRect, labelBorderPaint);

    // Desenhar texto
    labelPainter.paint(canvas, Offset(labelX, labelY));

    // Texto central - Valor da Previsão
    final previsaoText = _formatarNumero(previsaoProducao);
    final textPainter = TextPainter(
      text: TextSpan(
        text: previsaoText,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(GaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage;
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSmallDevice = MediaQuery.of(context).size.width < 600;

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
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallDevice ? 8 : 12,
                  vertical: isSmallDevice ? 8 : 14,
                ),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                        child: Icon(
                          widget.icon,
                          size: isSmallDevice ? 32 : 40,
                          color: widget.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: isSmallDevice ? 48 : 60,
                      child: Center(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: isSmallDevice ? 14 : 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[900],
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
}
