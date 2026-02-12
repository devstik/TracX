import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// --- CONFIGURAÇÃO DE REDE ---
const String _kBaseUrl = "http://168.190.90.2:5000";

// --- CORES IDENTIDADE STIK ---
const Color _kPrimaryRed = Color(0xFFD32F2F);
const Color _kBackground = Color(0xFFF8F9FA);

class RegistrosApontamento extends StatefulWidget {
  const RegistrosApontamento({super.key});

  @override
  State<RegistrosApontamento> createState() => _RegistrosApontamentoState();
}

class _RegistrosApontamentoState extends State<RegistrosApontamento>
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
      appBar: AppBar(
        backgroundColor: _kPrimaryRed,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'STIK - CONSULTA DE DADOS',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'PRODUÇÃO (A)', icon: Icon(Icons.analytics_outlined)),
            Tab(text: 'QUALIDADE (B)', icon: Icon(Icons.fact_check_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _ListaDadosGeral(endpoint: "tipoA"),
          const _ListaDadosGeral(endpoint: "tipoB"),
        ],
      ),
    );
  }
}

class _ListaDadosGeral extends StatelessWidget {
  final String endpoint;
  const _ListaDadosGeral({required this.endpoint});

  // Mapeia os códigos do servidor para as letras dos turnos
  String _mapearTurno(dynamic turnoRaw) {
    if (turnoRaw == null) return "N/A";
    String t = turnoRaw.toString();
    if (t == "8") return "A";
    if (t == "9") return "B";
    if (t == "10") return "C";
    return t; // Retorna o valor original caso venha diferente
  }

  Future<List<dynamic>> _buscarDados() async {
    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrl/apontamento/$endpoint"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Status: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Erro ao conectar.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _buscarDados(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kPrimaryRed),
          );
        }
        if (snapshot.hasError)
          return _buildErrorPlaceholder(snapshot.error.toString());
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("Nenhum registro."));
        }

        final dados = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: dados.length,
          itemBuilder: (context, index) {
            final item = dados[index];
            return endpoint == "tipoA"
                ? _buildCardProducao(item)
                : _buildCardQualidade(item);
          },
        );
      },
    );
  }

  Widget _buildCardProducao(Map<String, dynamic> item) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Artigo: ${item['Artigo'] ?? 'N/A'}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                _buildBadge("Turno ${_mapearTurno(item['Turno'])}"),
              ],
            ),
            const Divider(height: 24),
            _buildDataPoint(
              Icons.person,
              "Operador",
              item['Operador']?.toString(),
            ),
            _buildDataPoint(
              Icons.precision_manufacturing,
              "Máquina",
              item['Maq']?.toString(),
            ),
            _buildDataPoint(
              Icons.add_box,
              "Quantidade",
              item['Qtde']?.toString(),
            ),
            _buildDataPoint(
              Icons.calendar_today,
              "Data",
              _formatDate(item['Data']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardQualidade(Map<String, dynamic> item) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Colors.orange, width: 6)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "NC: ${item['Artigo'] ?? 'N/A'}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                _buildBadge(
                  "Turno ${_mapearTurno(item['turno'])}",
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Defeito: ${item['Defeito'] ?? 'Não informado'}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Divider(height: 24),
            _buildDataPoint(
              Icons.remove_circle,
              "Qtde Defeituosa",
              item['Qtde']?.toString(),
            ),
            _buildDataPoint(
              Icons.notes,
              "Observação",
              item['Detalhe']?.toString(),
            ),
            _buildDataPoint(Icons.timer, "Registro", _formatDate(item['data'])),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS DE APOIO COM TRATAMENTO DE STRING ---
  Widget _buildDataPoint(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kPrimaryRed),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          // O value ?? 'N/A' garante que nunca passaremos nulo para o Text
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, {Color color = _kPrimaryRed}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return "N/A";
    String d = date.toString();
    return d.length >= 10 ? d.substring(0, 10) : d;
  }

  Widget _buildErrorPlaceholder(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text("Erro: $error"),
      ),
    );
  }
}
