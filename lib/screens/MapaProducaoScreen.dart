import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class MapaProducaoScreen extends StatefulWidget {
  const MapaProducaoScreen({super.key});

  @override
  State<MapaProducaoScreen> createState() => _MapaProducaoScreenState();
}

class _MapaProducaoScreenState extends State<MapaProducaoScreen> {
  static const String _empresaId = '2';
  static const String _tipoDocumentoId = '62';
  static const String _operacaoId = '62';
  static const String _finalidadeId = '7';
  static const String _centroCustosId = '13';
  static const String _localizacaoId = '2026';

  final _formKey = GlobalKey<FormState>();
  final String _baseUrl =
      'visions.topmanager.com.br'; // host used to consult production map
  final String _mapaPath =
      '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/consultar';
  bool _loading = false;

  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _turnoController = TextEditingController();
  final TextEditingController _ordemProducaoController =
      TextEditingController();
  final TextEditingController _produtoController = TextEditingController();
  final TextEditingController _loteController = TextEditingController();
  final TextEditingController _unidadeMedidaController =
      TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _dataController.dispose();
    _turnoController.dispose();
    _ordemProducaoController.dispose();
    _produtoController.dispose();
    _loteController.dispose();
    _unidadeMedidaController.dispose();
    _quantidadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Mapa de Produção'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.red.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informações do Documento',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildField(
                    label: 'Data (dd/MM/yyyy)',
                    controller: _dataController,
                    hint: '24/11/2025',
                    keyboardType: TextInputType.datetime,
                  ),
                  _buildField(
                    label: 'Turno',
                    controller: _turnoController,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Identificação da Produção',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildField(
                    label: 'Ordem de Produção ID',
                    controller: _ordemProducaoController,
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(
                    label: 'Objeto',
                    controller: _produtoController,
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(
                    label: 'Detalhe',
                    controller: _loteController,
                    keyboardType: TextInputType.number,
                  ),
                  _buildField(
                    label: 'Unidade de Medida',
                    controller: _unidadeMedidaController,
                  ),
                  _buildField(
                    label: 'Quantidade',
                    controller: _quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _salvarMapa,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(
                    'Salvar Mapa',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
    bool readOnly = false,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        validator: (value) =>
            value == null || value.isEmpty ? 'Campo obrigatório' : null,
      ),
    );
  }

  Future<void> _consultarMapa() async {
    FocusScope.of(context).unfocus();
    final dataBr = _dataController.text.trim();
    if (dataBr.isEmpty) {
      _showSnackBar(
        'Informe a Data para consultar.',
        isError: true,
      );
      return;
    }

    final dataIso = _parseDataBrToIso(dataBr);
    if (dataIso == null) {
      _showSnackBar('Data inválida. Use o formato dd/MM/yyyy.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final uri = Uri.https(_baseUrl, _mapaPath, {
        'empresaID': _empresaId,
        'tipoDeDocumentoID': _tipoDocumentoId,
        'data': dataIso,
      });

      print('[MapaProducao] Consultando: $uri');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is Map<String, dynamic>) {
            _preencherCampos(first);
            _showSnackBar('Dados carregados com sucesso.');
            print('[MapaProducao] Dados recebidos: $first');
          } else {
            _showSnackBar(
              'Estrutura da lista inesperada.',
              isError: true,
            );
            print('[MapaProducao][ERRO] Estrutura inesperada: $decoded');
          }
        } else if (decoded is Map<String, dynamic>) {
          _preencherCampos(decoded);
          _showSnackBar('Dados carregados com sucesso.');
          print('[MapaProducao] Dados recebidos: $decoded');
        } else {
          _showSnackBar(
            'Retorno inesperado do servidor.',
            isError: true,
          );
          print('[MapaProducao][ERRO] Retorno inesperado: $decoded');
        }
      } else {
        print(
          '[MapaProducao][ERRO] HTTP ${response.statusCode}: ${response.body}',
        );
        _showSnackBar(
          'Erro ${response.statusCode} ao consultar o mapa.',
          isError: true,
        );
      }
    } catch (e) {
      print('[MapaProducao][ERRO] Falha na consulta: $e');
      _showSnackBar('Falha na consulta: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _preencherCampos(Map<String, dynamic> data) {
    void setField(TextEditingController controller, List<String> keys) {
      for (final key in keys) {
        if (data.containsKey(key) && data[key] != null) {
          controller.text = data[key].toString();
          return;
        }
      }
    }

    setField(_dataController, ['data']);
    setField(_turnoController, ['turnoId', 'turnoID']);
    setField(_ordemProducaoController, ['ordemProducaoId', 'ordemProducaoID']);
    setField(_produtoController, ['produtoId', 'produtoID']);
    setField(_loteController, ['loteId', 'loteID']);
    setField(_unidadeMedidaController, ['unidadeDeMedida']);
    setField(_quantidadeController, ['quantidade']);
  }

  Future<void> _salvarMapa() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await _consultarMapa();

    final payload = {
      'empresaId': _empresaId,
      'operacaoId': _operacaoId,
      'tipoDeDocumentoId': _tipoDocumentoId,
      'finalidadeId': _finalidadeId,
      'centroDeCustosId': _centroCustosId,
      'localizacaoId': _localizacaoId,
      'data': _parseDataBrToIso(_dataController.text.trim()) ?? '',
      'turnoId': _turnoController.text.trim(),
      'ordemProducaoId': _ordemProducaoController.text.trim(),
      'produtoId': _produtoController.text.trim(),
      'loteId': _loteController.text.trim(),
      'unidadeDeMedida': _unidadeMedidaController.text.trim(),
      'quantidade': _quantidadeController.text.trim(),
    };

    print('[MapaProducao] Payload preparado: $payload');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }

  String? _parseDataBrToIso(String dataBr) {
    try {
      final parsed = DateFormat('dd/MM/yyyy').parseStrict(dataBr);
      return DateFormat("yyyy-MM-dd'T'00:00:00").format(parsed);
    } catch (_) {
      return null;
    }
  }
}
