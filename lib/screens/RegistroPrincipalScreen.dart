import 'package:flutter/material.dart';
// Certifique-se de que os caminhos de importação estão corretos em seu projeto.
import '../views/RegistroEmbalagem.dart' as embalagem;
import '../views/RegistroTinturaria.dart'; // Importação ajustada conforme solicitado

// =========================================================================
// CORES E CONSTANTES (Mantidas para um visual limpo)
// =========================================================================
const Color _kPrimaryColor = Color(0xFFCD1818); // Vermelho Principal
const Color _kBackgroundColor = Color(0xFFF5F5F5); // Fundo Cinza Claro

// =========================================================================
// TELA PRINCIPAL DE REGISTRO COM ABAS (Organizada e Simples)
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
    // Inicializa o TabController com 2 abas
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
      backgroundColor: _kBackgroundColor, // Define um fundo leve
      appBar: AppBar(
        // AppBar Principal: Fundo Vermelho
        backgroundColor: _kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Registrar',
          style: TextStyle(fontWeight: FontWeight.w600), // Fonte mais forte
        ),
        // Botão de voltar branco
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),

        // TabBar: Estilo mais minimalista e integrado
        bottom: TabBar(
          controller: _tabController,

          // Indicador: Apenas uma linha branca, simples e limpa.
          // Este é o principal ajuste para simplificar a estética da aba.
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: Colors.white, width: 3.0),
            insets: EdgeInsets.symmetric(
              horizontal: 16.0,
            ), // Centraliza a linha
          ),
          indicatorSize:
              TabBarIndicatorSize.label, // Linha apenas no texto/ícone

          labelColor: Colors.white, // Cor do texto/ícone selecionado (Branco)
          unselectedLabelColor: Colors
              .white70, // Cor do texto/ícone não selecionado (Branco mais claro)

          tabs: const [
            // Aba 2: Embalagem
            Tab(
              text: 'Embalagem',
              icon: Icon(
                Icons.inventory_2_outlined,
              ), // Ícone Outlined mais moderno
            ),
            // Aba 1: Tinturaria
            Tab(
              text: 'Tinturaria',
              icon: Icon(
                Icons.color_lens_outlined,
              ), // Ícone Outlined mais moderno
            ),
          ],
        ),
      ),
      // TabBarView para exibir o conteúdo das abas
      body: TabBarView(
        controller: _tabController,
        children: [
          // Conteúdo da aba Tinturaria (vindo de RegistroRaschelina.dart)
          embalagem.RegistroScreen(conferente: widget.conferente),
          
          RegistroScreenTinturaria(conferente: widget.conferente),

          // Conteúdo da aba Embalagem (vindo de RegistroEmbalagem.dart)
        ],
      ),
    );
  }
}
