import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ConsultaMapaProducaoScreen extends StatefulWidget {
  const ConsultaMapaProducaoScreen({super.key});

  @override
  State<ConsultaMapaProducaoScreen> createState() =>
      _ConsultaMapaProducaoScreenState();
}

class _ConsultaMapaProducaoScreenState
    extends State<ConsultaMapaProducaoScreen> {
  static const String _empresaId = '2';
  static const String _tipoDocumentoId = '62';
  static const String _authEndpoint =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _authEmail = 'suporte.wms';
  static const String _authSenha = '123456';
  static const int _authUsuarioId = 21578;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dataInicialController = TextEditingController();
  final TextEditingController _dataFinalController = TextEditingController();

  final String _baseUrl = 'visions.topmanager.com.br';
  final String _mapaPath =
      '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/consultar';

  bool _loading = false;
  List<_MapaResultado> _resultados = [];

  @override
  void dispose() {
    _dataInicialController.dispose();
    _dataFinalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Consultar Mapas'),
        backgroundColor: Colors.red.shade700,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: 'Data inicial (dd/MM/yyyy)',
                        controller: _dataInicialController,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDateField(
                        label: 'Data final (dd/MM/yyyy)',
                        controller: _dataFinalController,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _consultar,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_loading ? 'Consultando...' : 'Consultar Mapas'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _resultados.isEmpty
                        ? Center(
                            child: Text(
                              'Nenhum mapa encontrado para o período informado.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _resultados.length,
                            itemBuilder: (_, index) {
                              final resultado = _resultados[index];
                              return _MapaCard(resultado: resultado);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Campo obrigatório' : null,
    );
  }

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dataInicial = _parseData(_dataInicialController.text.trim());
    final dataFinal = _parseData(_dataFinalController.text.trim());

    if (dataInicial == null || dataFinal == null) {
      _showSnackBar('Datas inválidas. Use o formato dd/MM/yyyy.', isError: true);
      return;
    }

    if (dataFinal.isBefore(dataInicial)) {
      _showSnackBar('A data final deve ser maior ou igual à inicial.',
          isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _resultados = [];
    });

    final List<_MapaResultado> novosResultados = [];

    try {
      final apiKey = await _obterChaveApi();

      for (DateTime data = dataInicial;
          !data.isAfter(dataFinal);
          data = data.add(const Duration(days: 1))) {
        final isoDate = DateFormat("yyyy-MM-dd'T'00:00:00").format(data);
        final uri = Uri.https(_baseUrl, _mapaPath, {
          'empresaID': _empresaId,
          'tipoDeDocumentoID': _tipoDocumentoId,
          'data': isoDate,
        });

        print('[ConsultaMapa] GET $uri');
        final response = await http.get(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        );
        if (response.statusCode != 200) {
          print(
            '[ConsultaMapa][ERRO] ${response.statusCode}: ${response.body}',
          );
          continue;
        }

        final decoded = jsonDecode(response.body);
        final List<Map<String, dynamic>> registros = [];

        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) registros.add(item);
          }
        } else if (decoded is Map<String, dynamic>) {
          registros.add(decoded);
        }

        if (registros.isNotEmpty) {
          novosResultados.add(
            _MapaResultado(data: data, registros: registros),
          );
        }
      }

      setState(() {
        _resultados = novosResultados;
      });

      _showSnackBar('Consulta finalizada.');
    } catch (e) {
      print('[ConsultaMapa][ERRO] $e');
      _showSnackBar('Erro na consulta: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  DateTime? _parseData(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }

  Future<String> _obterChaveApi() async {
    final response = await http.post(
      Uri.parse(_authEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'email': _authEmail,
          'senha': _authSenha,
          'usuarioID': _authUsuarioId,
        },
      ),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Falha ao autenticar. Código: ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body);
    final redirect = body['redirecionarPara']?.toString();
    if (redirect == null || redirect.isEmpty) {
      throw Exception('Resposta de autenticação inválida.');
    }

    try {
      final redirectUri = Uri.parse(redirect);
      final token = redirectUri.queryParameters.values.firstWhere(
        (value) => value.startsWith('ey'),
        orElse: () => '',
      );
      if (token.isNotEmpty) return token;
    } catch (_) {
      // fallback to regex below
    }

    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect);
    if (match != null) {
      return match.group(1)!;
    }

    throw Exception('Não foi possível extrair a chave da API.');
  }
}

class _MapaResultado {
  final DateTime data;
  final List<Map<String, dynamic>> registros;

  const _MapaResultado({
    required this.data,
    required this.registros,
  });
}

class _MapaCard extends StatelessWidget {
  final _MapaResultado resultado;

  const _MapaCard({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final dataFormatada = DateFormat('dd/MM/yyyy').format(resultado.data);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: ExpansionTile(
        title: Text(
          'Data: $dataFormatada',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${resultado.registros.length} registro(s)',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        children: resultado.registros
            .map(
              (registro) => ListTile(
                title: Text(
                  'OP: ${registro['ordemProducaoId'] ?? '--'}',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Objeto: ${registro['produtoId'] ?? '--'}'),
                    Text('Detalhe: ${registro['loteId'] ?? '--'}'),
                    Text('Qtd: ${registro['quantidade'] ?? '--'}'),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
