import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tracx/screens/login_screen.dart';
import 'package:tracx/screens/ListaRegistrosScreen.dart';
import 'package:tracx/screens/CadastrarUsuarioScreen.dart';
import 'package:tracx/screens/ListarUsuariosScreen.dart';
import 'package:tracx/screens/AlterarSenhaScreen.dart';
import 'package:tracx/screens/LocalizacaoScreen.dart';
import 'package:tracx/screens/HistoricoMovimentacaoScreen.dart';
import 'package:tracx/screens/RegistroPrincipalScreen.dart';
import 'package:tracx/screens/MapaProducaoScreen.dart';
import 'package:tracx/screens/ConsultaMapaProducaoScreen.dart';
import 'package:tracx/screens/ApontamentoProdutividadeScreen.dart';
import 'package:tracx/screens/RegistrosApontamento.dart';
import 'package:tracx/services/estoque_db_helper.dart';
//import 'package:tracx/widgets/widgets_dados_integrados.dart';
import 'package:tracx/services/update_service.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  //late Future<List<DadosProducaoDiaria>> _futureHistoricoProducao;

  int _currentIndex = 0;

  Map<String, dynamic>? _dadosProducao;
  bool _isLoadingProducao = true;
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
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();
    _gerenciarDadosProducao();
    
  }

  // void _carregarDadosProducao() {
  //   _futureHistoricoProducao = DadosAnalyticsAPI.buscarHistoricoProducao();
  // }

  // void _refreshDadosProducao() {
  //   setState(() {
  //     _carregarDadosProducao();
  //   });
  // }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF101B34),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: const Center(
        child: SizedBox(
          height: 40,
          width: 40,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF60A5FA)),
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _gerenciarDadosProducao() async {
    const String tipoCache = 'resumo_home';

    final cacheLocal = await _dbHelper.buscarCacheGrafico(tipoCache);

    if (cacheLocal.isNotEmpty) {
      _atualizarInterfaceComCache(cacheLocal);
    }

    bool precisaAtualizar = true;

    if (cacheLocal.isNotEmpty) {
      DateTime ultimaVez = DateTime.parse(cacheLocal.first['atualizado_em']);
      if (DateTime.now().difference(ultimaVez).inHours < 1) {
        precisaAtualizar = false;
        if (mounted) setState(() => _isLoadingProducao = false);
      }
    }

    if (precisaAtualizar) {
      await _buscarDadosAPIeSalvar(tipoCache);
    }
  }

  // Trecho corrigido do método _buscarDadosAPIeSalvar (substitua o método existente)

  Future<void> _buscarDadosAPIeSalvar(String tipo) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'http://168.190.90.2:5000/consulta/Tracx/resumo_producao',
            ),
          )
          .timeout(const Duration(seconds: 7));

      print("STATUS CODE: ${response.statusCode}");
      print("BODY RAW: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        print("JSON DECODIFICADO: $data");
        print("PrevisaoFechamento recebido: ${data['PrevisaoFechamento']}");

        // Função robusta para converter qualquer valor para double
        double toDouble(dynamic value) {
          if (value == null) {
            print("⚠️ Valor nulo recebido, retornando 0.0");
            return 0.0;
          }
          if (value is int) return value.toDouble();
          if (value is double) {
            print("✓ Double recebido: $value");
            return value;
          }

          final resultado = double.tryParse(value.toString()) ?? 0.0;
          print("✓ Convertido para double: $resultado (de $value)");
          return resultado;
        }

        final previsao = toDouble(data['PrevisaoFechamento']);
        final dias = toDouble(data['DiasProduzidosMes']);
        final total = toDouble(data['TotalProducao']);

        print("✓ Conversões realizadas:");
        print("  - DiasProduzidosMes: $dias");
        print("  - PrevisaoFechamento: $previsao");
        print("  - TotalProducao: $total");

        List<Map<String, dynamic>> paraSalvar = [
          {'periodo': 'DiasProduzidosMes', 'valor': dias},
          {
            'periodo': 'PrevisaoFechamento', // ✓ CORRETO - Nova chave
            'valor': previsao, // ✓ Aqui vai o valor correto da API
          },
          {'periodo': 'TotalProducao', 'valor': total},
        ];

        print("🔄 DADOS QUE SERÃO SALVOS NO BANCO:");
        for (var item in paraSalvar) {
          print("  - ${item['periodo']}: ${item['valor']}");
        }

        // PASSO 1: Limpar dados antigos E CORROMPIDOS
        print("🧹 LIMPANDO CACHE ANTIGA...");
        await _dbHelper.limparCacheGrafico(tipo);
        print("✓ Cache antigo limpo para tipo: $tipo");

        // PASSO 2: Salvar dados novos
        print("💾 SALVANDO DADOS NOVOS...");
        await _dbHelper.salvarCacheGrafico(paraSalvar, tipo);

        // PASSO 3: Recuperar e verificar
        print("📊 VERIFICANDO O QUE FOI SALVO...");
        final novoCache = await _dbHelper.buscarCacheGrafico(tipo);

        print("✓ CACHE RECUPERADA DO BANCO (${novoCache.length} registros):");
        for (var item in novoCache) {
          print("  - ${item['periodo']}: ${item['valor']}");
        }

        _atualizarInterfaceComCache(novoCache);
      }
    } catch (e) {
      print("❌ ERRO NA REQUISIÇÃO: $e");
      debugPrint('Rede indisponível. Mantendo dados locais.');
      if (mounted) setState(() => _isLoadingProducao = false);
    }
  }

  void _atualizarInterfaceComCache(List<Map<String, dynamic>> cache) {
    if (!mounted || cache.isEmpty) return;

    print("═══════════════════════════════════════");
    print("ATUALIZANDO INTERFACE COM CACHE");
    print("═══════════════════════════════════════");
    print("CACHE RECEBIDO: ${cache.length} registros");
    for (var item in cache) {
      print(
        "  - ${item['periodo']}: ${item['valor']} (tipo: ${item['tipo_grafico']})",
      );
    }

    double buscarValor(List<String> periodos) {
      print("🔍 Procurando por: $periodos");

      for (var periodo in periodos) {
        final item = cache.where((e) => e['periodo'] == periodo).toList();
        if (item.isNotEmpty) {
          final valor = (item.first['valor'] ?? 0).toDouble();
          print("✓ Encontrado '$periodo' -> $valor");
          return valor;
        }
      }

      print("❌ NENHUM DOS PERÍODOS $periodos ENCONTRADO");
      print("   Períodos disponíveis na cache:");
      for (var item in cache) {
        print("   - '${item['periodo']}'");
      }
      return 0.0;
    }

    setState(() {
      final dias = buscarValor(['DiasProduzidosMes']);
      final previsao = buscarValor([
        'PrevisaoFechamento', // ✓ NOVO - Chave correta
        'PrevisaoProducao', // Compatibilidade com cache antigo
      ]);
      final total = buscarValor(['TotalProducao']);

      print("\n═══════════════════════════════════════");
      print("VALORES FINAIS PARA A INTERFACE:");
      print("═══════════════════════════════════════");
      print("Dias: $dias");
      print("Previsao: $previsao");
      print("Total: $total");
      print("═══════════════════════════════════════\n");

      _dadosProducao = {
        "DiasProduzidosMes": dias,
        "PrevisaoProducao": previsao,
        "TotalProducao": total,
      };

      final DateTime dataDb = DateTime.parse(cache.first['atualizado_em']);
      final String hora = dataDb.hour.toString().padLeft(2, '0');
      final String minuto = dataDb.minute.toString().padLeft(2, '0');
      _ultimaAtualizacao = "Atualizado às $hora:$minuto";

      _isLoadingProducao = false;
    });
  }

  void _navigateWithTransition(BuildContext context, Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, __) => page,
        transitionsBuilder: (_, animation, __, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          );

          final slide = Tween<Offset>(
            begin: const Offset(0.12, 0),
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

  void _showAdminSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0F1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Painel Admin",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _AdminTile(
                icon: Icons.system_update_alt,
                title: "Verificar Atualização",
                onTap: () {
                  Navigator.pop(context);
                  UpdateService.check(context, showMessages: true);
                },
              ),
              _AdminTile(
                icon: Icons.person_add_alt_1,
                title: "Cadastrar Usuário",
                onTap: () {
                  Navigator.pop(context);
                  _navigateWithTransition(context, CadastrarUsuarioScreen());
                },
              ),
              _AdminTile(
                icon: Icons.lock_reset,
                title: "Alterar Senha",
                onTap: () {
                  Navigator.pop(context);
                  _navigateWithTransition(context, AlterarSenhaScreen());
                },
              ),
              _AdminTile(
                icon: Icons.people_alt_outlined,
                title: "Listar Usuários",
                onTap: () {
                  Navigator.pop(context);
                  _navigateWithTransition(context, ListarUsuariosScreen());
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  String _formatarNumero(double valor) {
    return valor
        .toStringAsFixed(2)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  String _saudacao() {
    final hora = DateTime.now().hour;
    if (hora < 12) return "Bom dia";
    if (hora < 18) return "Boa tarde";
    return "Boa noite";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A14),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildDashboard(),
              _buildCadastros(),
              _buildRelatorios(),
              _buildConfig(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF070C17),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06), width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF070C17),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF4DA3FF),
        unselectedItemColor: Colors.white54,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            label: "Início",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: "Ações",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: "Dados",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: "Conta",
          ),
        ],
      ),
    );
  }

  // ---------------- DASHBOARD ----------------

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PremiumHeader(
            saudacao: _saudacao(),
            nome: widget.conferente,
            isAdmin: _isAdmin,
            onAdminTap: _showAdminSheet,
            onLogoutTap: _logout,
          ),

          const SizedBox(height: 18),

          _buildStatusCard(),

          const SizedBox(height: 16),

          _buildMainModules(),

          const SizedBox(height: 18),

          if (!_isLoadingProducao && _dadosProducao != null)
            _buildGaugeProducao(),

          const SizedBox(height: 16),

          if (widget.conferente == "Joao") _buildAdminShortcutCard(),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1220), Color(0xFF0D1630), Color(0xFF08101F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4DA3FF).withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF4DA3FF), Color(0xFF5EF7C5)],
              ),
            ),
            child: const Icon(
              Icons.radar_outlined,
              color: Colors.black,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Status do Sistema",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _ultimaAtualizacao,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: const [
                Icon(Icons.circle, size: 10, color: Color(0xFF5EF7C5)),
                SizedBox(width: 6),
                Text(
                  "Ativo",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainModules() {
    return Column(
      children: [
        _BigModuleCard(
          title: "Novo Registro",
          subtitle: "Crie um registro completo com localização e rastreio.",
          icon: Icons.app_registration,
          accent: const Color(0xFF4DA3FF),
          onTap: () {
            _navigateWithTransition(
              context,
              RegistroPrincipalScreen(conferente: widget.conferente),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGaugeProducao() {
    final totalProducao = _dadosProducao!['TotalProducao'] as double;
    final previsaoProducao = _dadosProducao!['PrevisaoProducao'] as double;

    final percentual = (totalProducao / previsaoProducao).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, color: Color(0xFFFFD166)),
              const SizedBox(width: 8),
              const Text(
                "Produção do mês",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Text(
                _ultimaAtualizacao,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 150,
                  child: CustomPaint(
                    painter: GaugePainter(
                      percentage: percentual,
                      totalProducao: totalProducao,
                      previsaoProducao: previsaoProducao,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    _MetricCard(
                      title: "Produção atual",
                      value: _formatarNumero(totalProducao),
                      icon: Icons.factory_outlined,
                      accent: const Color(0xFF4DA3FF),
                    ),
                    const SizedBox(height: 12),
                    _MetricCard(
                      title: "Previsão do mês",
                      value: _formatarNumero(previsaoProducao),
                      icon: Icons.timeline_outlined,
                      accent: const Color(0xFF5EF7C5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminShortcutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF101B34), Color(0xFF0B1220)],
        ),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: Color(0xFF4DA3FF), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Apontamento disponível",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _navigateWithTransition(context, ProducaoTabsScreen());
            },
            child: const Text("Abrir"),
          ),
        ],
      ),
    );
  }

  // ---------------- AÇÕES ----------------

  Widget _buildCadastros() {
    final List<_ActionItem> actions = [
      _ActionItem(
        title: "Registrar",
        subtitle: "Novo registro completo",
        icon: Icons.app_registration,
        onTap: () {
          _navigateWithTransition(
            context,
            RegistroPrincipalScreen(conferente: widget.conferente),
          );
        },
      ),
      _ActionItem(
        title: "Registros",
        subtitle: "Lista completa",
        icon: Icons.list_alt_outlined,
        onTap: () {
          _navigateWithTransition(
            context,
            ListaRegistrosScreen(conferente: widget.conferente),
          );
        },
      ),
      _ActionItem(
        title: "Localização",
        subtitle: "Consultar posição",
        icon: Icons.location_searching_outlined,
        onTap: () {
          _navigateWithTransition(
            context,
            Localizacaoscreen(conferente: widget.conferente, isAdmin: _isAdmin),
          );
        },
      ),
      _ActionItem(
        title: "Fluxo",
        subtitle: "Movimentação geral",
        icon: Icons.track_changes_outlined,
        onTap: () {
          _navigateWithTransition(
            context,
            HistoricoMovimentacaoScreen(
              nrOrdem: 0,
              titulo: "Movimentação Geral",
            ),
          );
        },
      ),
      _ActionItem(
        title: "Consultar Mapas",
        subtitle: "Mapas de produção",
        icon: Icons.analytics_outlined,
        onTap: () {
          _navigateWithTransition(context, const ConsultaMapaProducaoScreen());
        },
      ),
      _ActionItem(
        title: "Apontamento",
        subtitle: "Produtividade",
        icon: Icons.stacked_line_chart_outlined,
        onTap: () {
          _navigateWithTransition(context, const ProducaoTabsScreen());
        },
      ),
      _ActionItem(
        title: "Registros Apontamento",
        subtitle: "Consultar histórico",
        icon: Icons.fact_check_outlined,
        onTap: () {
          _navigateWithTransition(context, const RegistrosApontamento());
        },
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ações do sistema",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Tudo que você pode fazer dentro do TracX, organizado para acesso rápido.",
            style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 18),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              return _ActionTile(item: actions[index]);
            },
          ),
        ],
      ),
    );
  }

  // ---------------- RELATÓRIOS ----------------

  Widget _buildRelatorios() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Indicadores",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Resumo de dados e produtividade do sistema.",
            style: TextStyle(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 18),

          if (!_isLoadingProducao && _dadosProducao != null)
            _buildGaugeProducao(),

          const SizedBox(height: 12),

          _InfoCard(
            icon: Icons.lightbulb_outline,
            title: "Sugestão",
            subtitle:
                "Para vender esse módulo, o ideal é adicionar filtros por setor e gráficos de evolução semanal/mensal.",
          ),
        ],
      ),
    );
  }

  // ---------------- CONFIG ----------------

  Widget _buildConfig() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Conta",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Usuário logado: ${widget.conferente}",
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 18),

          _ConfigTile(
            icon: Icons.system_update_alt,
            title: "Verificar atualização",
            subtitle: "Baixar nova versão do aplicativo",
            onTap: () {
              UpdateService.check(context, showMessages: true);
            },
          ),
          _ConfigTile(
            icon: Icons.lock_outline,
            title: "Alterar senha",
            subtitle: "Atualize sua senha de acesso",
            onTap: () {
              _navigateWithTransition(context, AlterarSenhaScreen());
            },
          ),
          if (_isAdmin)
            _ConfigTile(
              icon: Icons.admin_panel_settings_outlined,
              title: "Painel Admin",
              subtitle: "Gerenciar usuários e permissões",
              onTap: _showAdminSheet,
            ),
          _ConfigTile(
            icon: Icons.logout,
            title: "Sair",
            subtitle: "Encerrar sessão do usuário",
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}

// ======================= COMPONENTES PREMIUM =======================

class _PremiumHeader extends StatelessWidget {
  final String saudacao;
  final String nome;
  final bool isAdmin;
  final VoidCallback onLogoutTap;
  final VoidCallback onAdminTap;

  const _PremiumHeader({
    required this.saudacao,
    required this.nome,
    required this.isAdmin,
    required this.onLogoutTap,
    required this.onAdminTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B1220), Color(0xFF101B34)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(
              CupertinoIcons.person_crop_circle,
              color: Colors.white70,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$saudacao,",
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 2),
                Text(
                  nome,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isAdmin)
            IconButton(
              onPressed: onAdminTap,
              icon: const Icon(
                Icons.admin_panel_settings_outlined,
                color: Color(0xFF4DA3FF),
              ),
            ),
          IconButton(
            onPressed: onLogoutTap,
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _QuickCircleAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  const _QuickCircleAction({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Container(
          width: 86,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: const Color(0xFF0B1220),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(0.15),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _BigModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [accent.withOpacity(0.22), const Color(0xFF0B1220)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: accent.withOpacity(0.18),
              ),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _MiniModuleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: const Color(0xFF0B1220),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: accent.withOpacity(0.16),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: accent.withOpacity(0.12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  _ActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _ActionTile extends StatelessWidget {
  final _ActionItem item;

  const _ActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: const Color(0xFF0B1220),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withOpacity(0.04),
              ),
              child: Icon(item.icon, color: const Color(0xFF4DA3FF)),
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            const SizedBox(height: 6),
            Text(
              item.subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white54,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            const Spacer(),
            const Align(
              alignment: Alignment.bottomRight,
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ConfigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: const Color(0xFF0B1220),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF4DA3FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFF0B1220),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4DA3FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "$title\n",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _AdminTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF4DA3FF)),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    );
  }
}

// ======================= GAUGE =======================

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

    final bgPaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    final fgPaint = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * percentage,
      false,
      fgPaint,
    );

    final endAngle = startAngle + (sweepAngle * percentage);
    final pointX = center.dx + radius * math.cos(endAngle);
    final pointY = center.dy + radius * math.sin(endAngle);

    final pointPosition = Offset(pointX, pointY);

    final pointBorderPaint = Paint()
      ..color = const Color(0xFF0B1220)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(pointPosition, 12, pointBorderPaint);

    final pointPaint = Paint()
      ..color = const Color(0xFF4DA3FF)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(pointPosition, 7, pointPaint);

    final labelText = _formatarNumero(totalProducao);

    final labelPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    labelPainter.layout();

    final labelX = pointX - labelPainter.width / 2;
    final labelY = pointY - 30;

    labelPainter.paint(canvas, Offset(labelX, labelY));

    final previsaoText = _formatarNumero(previsaoProducao);

    final textPainter = TextPainter(
      text: TextSpan(
        text: previsaoText,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
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
