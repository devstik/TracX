import 'package:flutter/material.dart';
import '../views/RegistroEmbalagem.dart' as embalagem;
import '../views/RegistroTinturaria.dart';

// =========================================================================
// 🎨 PALETA OFICIAL (PADRÃO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFF2563EB);
const Color _kAccentColor = Color(0xFF60A5FA);

const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);

const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);

const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);

const Color _kBorderSoft = Color(0x33FFFFFF);

// =========================================================================
// TELA PRINCIPAL DE REGISTRO COM ABAS
// =========================================================================
class RegistroPrincipalScreen extends StatefulWidget {
  final String conferente;
  const RegistroPrincipalScreen({required this.conferente, super.key});

  @override
  State<RegistroPrincipalScreen> createState() =>
      _RegistroPrincipalScreenState();
}

class _RegistroPrincipalScreenState extends State<RegistroPrincipalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBottom,

      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        foregroundColor: _kTextPrimary,
        backgroundColor: _kBgBottom,

        title: const Text(
          'Registrar',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            fontSize: 18,
          ),
        ),

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),

        // 🔥 Fundo em gradiente igual Home/Splash
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kBgTop, _kSurface2, _kBgBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),

        // ✅ TabBar correta (sem quebrar o cabeçalho)
        bottom: TabBar(
          controller: _tabController,

          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: _kAccentColor, width: 3),
          ),

          labelColor: _kTextPrimary,
          unselectedLabelColor: _kTextSecondary,

          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),

          tabs: const [
            Tab(
              icon: Icon(Icons.inventory_2_outlined, size: 20),
              text: 'Embalagem',
            ),
            Tab(
              icon: Icon(Icons.color_lens_outlined, size: 20),
              text: 'Raschelina',
            ),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: [
          embalagem.RegistroScreen(conferente: widget.conferente),
          RegistroScreenTinturaria(conferente: widget.conferente),
        ],
      ),
    );
  }
}
