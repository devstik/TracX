import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// Constantes de Autenticação e API WMS (Consulta de Mapas)
const String _empresaId = '2';
const String _tipoDocumentoId = '62';
const String _authEndpointWMS = // Endpoint de Autenticação WMS
    'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
const String _authEmailWMS = 'suporte.wms';
const String _authSenhaWMS = '123456';
const int _authUsuarioIdWMS = 21578;
const String _baseUrl = 'visions.topmanager.com.br';
const String _mapaPath =
    '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/consultar';

const String _prodBaseUrl = 'visions.topmanager.com.br';
const String _prodPath =
    '/Servidor_2.7.0_api/forcadevendas/objetodevenda/consultar';

// Constantes de Autenticação Força de Vendas (Consulta de Produtos)
const String _prodAuthEndpoint =
    'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';
const String _prodAuthEmail = 'Stik.ForcaDeVendas';
const String _prodAuthSenha = '123456';
const int _prodAuthUsuarioId = 15980;

// Média de tempo de resposta da API (3.2 segundos) para estimativa
const int _avgApiTimeMs = 3200;

// Map<int ProdutoID, String NomeProduto>
final Map<int, String> _produtosCache = {};
String? _prodApiKey; // Chave de API para o endpoint de produtos

class ConsultaMapaProducaoScreen extends StatefulWidget {
  const ConsultaMapaProducaoScreen({super.key});

  @override
  State<ConsultaMapaProducaoScreen> createState() =>
      _ConsultaMapaProducaoScreenState();
}

class _ConsultaMapaProducaoScreenState
    extends State<ConsultaMapaProducaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dataInicialController = TextEditingController();
  final TextEditingController _dataFinalController = TextEditingController();

  bool _loading = false;
  List<_MapaResultado> _resultados = [];

  // Variáveis para feedback de progresso
  int _diasTotais = 0;
  int _diasProcessados = 0;
  int _tempoEstimado = 0; // Em segundos
  // Variável para a data atualmente em consulta
  String _dataAtualProcessando = '';

  @override
  void dispose() {
    _dataInicialController.dispose();
    _dataFinalController.dispose();
    super.dispose();
  }

  // --- UI/APRESENTAÇÃO ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Consultar Mapas'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildFormArea(),
              const SizedBox(height: 24),
              Expanded(child: _buildResultsArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormArea() {
    return Column(
      children: [
        Form(
          key: _formKey,
          child: Row(
            children: [
              Expanded(
                child: _buildDateField(
                  label: 'Inicial',
                  controller: _dataInicialController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDateField(
                  label: 'Final',
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(_loading ? 'Consultando...' : 'Consultar Mapas'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
  }) {
    Future<void> selectDate() async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
        locale: const Locale('pt', 'BR'),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.red.shade700,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
              buttonTheme: const ButtonThemeData(
                textTheme: ButtonTextTheme.primary,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      }
    }

    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: selectDate,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        suffixIcon: const Icon(Icons.calendar_today, color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Selecione a data' : null,
    );
  }

  Widget _buildResultsArea() {
    if (_loading) {
      return _buildLoadingFeedback();
    }

    if (_resultados.isEmpty) {
      return Center(
        child: Text(
          'Nenhum mapa encontrado para o período informado.',
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: _resultados.length,
      itemBuilder: (_, index) {
        final resultado = _resultados[index];
        return _MapaCard(resultado: resultado);
      },
    );
  }

  Widget _buildLoadingFeedback() {
    final progresso = _diasTotais == 0 ? 0.0 : _diasProcessados / _diasTotais;
    final percentual = (progresso * 100).toStringAsFixed(0);

    final tempoRestante = (_tempoEstimado * (1.0 - progresso)).ceil().clamp(
      0,
      _tempoEstimado,
    );
    final tempoRestanteFormatado = tempoRestante == 0
        ? 'calculando...'
        : '${tempoRestante}s';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Consultando dados. Por favor, aguarde.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        Text(
          'Dia em consulta: $_dataAtualProcessando', // Exibe a data
          style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Barra de Progresso Linear
        LinearProgressIndicator(
          value: progresso,
          backgroundColor: Colors.grey.shade300,
          color: Colors.red.shade700,
        ),
        const SizedBox(height: 8),
        // Indicador de Progresso (X de Y dias e %)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dia: $_diasProcessados de $_diasTotais',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                '$percentual%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Indicador de tempo restante
        Text(
          'Tempo restante estimado: $tempoRestanteFormatado',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
      ],
    );
  }

  // --- LÓGICA DE NEGÓCIOS / API ---

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dataInicial = _parseData(_dataInicialController.text.trim());
    final dataFinal = _parseData(_dataFinalController.text.trim());

    if (dataInicial == null ||
        dataFinal == null ||
        dataFinal.isBefore(dataInicial)) {
      _showSnackBar('Verifique o período de datas.', isError: true);
      return;
    }

    final diasTotais = dataFinal.difference(dataInicial).inDays + 1;
    final tempoEstimado = (diasTotais * _avgApiTimeMs / 1000).ceil();

    setState(() {
      _loading = true;
      _resultados = [];
      _diasTotais = diasTotais;
      _diasProcessados = 0;
      _tempoEstimado = tempoEstimado;
      _dataAtualProcessando = 'Iniciando...';
      _produtosCache.clear(); // Limpa o cache de produtos para nova consulta
    });

    final startTime = DateTime.now();

    try {
      // Autenticação WMS para Mapas
      final apiKeyWMS = await _obterChaveApi(
        _authEndpointWMS,
        _authEmailWMS,
        _authSenhaWMS,
        _authUsuarioIdWMS,
      );

      final List<_MapaResultado> novosResultados = [];
      final Set<int> produtosIdsParaConsultar = {};

      print(
        '[ConsultaMapa] Iniciando consulta SEQUENCIAL. Estimativa: ${tempoEstimado} segundos.',
      );

      // 1. CONSULTA SEQUENCIAL DE MAPAS DE PRODUÇÃO
      for (
        DateTime data = dataInicial;
        !data.isAfter(dataFinal);
        data = data.add(const Duration(days: 1))
      ) {
        final isoDate = DateFormat("yyyy-MM-dd'T'00:00:00").format(data);
        final dataFormatada = DateFormat("dd/MM/yyyy").format(data);

        setState(() {
          _dataAtualProcessando = dataFormatada;
          _diasProcessados = data.difference(dataInicial).inDays;
        });

        final uri = Uri.https(_baseUrl, _mapaPath, {
          'empresaID': _empresaId,
          'tipoDeDocumentoID': _tipoDocumentoId,
          'data': isoDate,
        });

        final http.Response response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $apiKeyWMS'},
        );

        if (response.statusCode != 200) {
          print(
            '[ConsultaMapa][ERRO REQ][Data $dataFormatada] Status: ${response.statusCode}. Body: ${response.body}',
          );
        } else {
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
            // Coleta IDs de produtos únicos para consulta posterior
            for (final registro in registros) {
              if (registro['produtoId'] is int) {
                produtosIdsParaConsultar.add(registro['produtoId'] as int);
                // ✅ PRINT: Mostra o ID coletado antes da consulta de nomes
                print(
                  '[ConsultaMapa] Produto ID coletado para associação: ${registro['produtoId']}',
                );
              }
            }
          }
        }

        setState(
          () => _diasProcessados = data.difference(dataInicial).inDays + 1,
        );
      }

      // 2. CONSULTA DE NOMES DE PRODUTOS
      if (produtosIdsParaConsultar.isNotEmpty) {
        setState(() {
          _dataAtualProcessando =
              'Consultando nomes de ${produtosIdsParaConsultar.length} produtos...';
        });

        // Autenticação Força de Vendas para Produtos
        _prodApiKey = await _obterChaveApi(
          _prodAuthEndpoint,
          _prodAuthEmail,
          _prodAuthSenha,
          _prodAuthUsuarioId,
        );

        await _consultarEArmazenarNomes(produtosIdsParaConsultar);
      } else {
        print('[ConsultaMapa] Nenhuma Produto ID coletado. Pulando consulta de nomes.');
      }

      // 3. FINALIZAÇÃO
      final totalTime = DateTime.now().difference(startTime).inSeconds;
      print(
        '[ConsultaMapa] Consulta SEQUENCIAL FINALIZADA. Tempo: ${totalTime}s',
      );

      setState(() {
        _resultados = novosResultados;
        _diasProcessados = _diasTotais; // Garantir 100% no final
      });

      _showSnackBar(
        'Consulta finalizada. ${novosResultados.length} dia(s) com dados. Tempo: ${totalTime}s',
      );
    } catch (e) {
      print('[ConsultaMapa][ERRO GERAL] $e');
      _showSnackBar('Erro na consulta: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _dataAtualProcessando = ''; // Limpa ao finalizar
        });
      }
    }
  }

  // ✅ NOVO/MODIFICADO: Função para consultar nomes de produtos
  Future<void> _consultarEArmazenarNomes(Set<int> produtosIds) async {
    if (_prodApiKey == null) {
      print('[ConsultaNome] Chave de API de produto indisponível.');
      return;
    }

    // Utiliza o NOVO ENDPOINT e APENAS o parâmetro empresaID
    final uri = Uri.https(_prodBaseUrl, _prodPath, {
      'empresaID': _empresaId,
    });

    print('[ConsultaNome] Consultando nomes no endpoint: $uri');

    try {
      final http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_prodApiKey'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        int produtosEncontrados = 0;

        if (decoded is List) {
          // A estrutura de resposta esperada é uma lista de itens, onde cada item
          // contém um mapa 'objeto' com 'id' e 'nome'.
          for (final item in decoded) {
            if (item is Map<String, dynamic> && item['objeto'] is Map) {
              final objeto = item['objeto'] as Map<String, dynamic>;
              if (objeto['id'] is int && objeto['nome'] is String) {
                final id = objeto['id'] as int;
                final nome = objeto['nome'] as String;

                // Adiciona ao cache apenas se o ID estiver na lista de IDs que precisamos
                if (produtosIds.contains(id)) {
                  _produtosCache[id] = nome;
                  produtosEncontrados++;
                  // ✅ PRINT: Confirma a associação bem-sucedida
                  print(
                    '[ConsultaNome][Sucesso] ID: $id associado a Nome: $nome',
                  );
                }
              }
            }
          }
          print(
            '[ConsultaNome] Finalizada. $produtosEncontrados nome(s) associado(s) de ${produtosIds.length} IDs requeridos.',
          );
        } else {
          print(
            '[ConsultaNome][AVISO] Resposta do endpoint não é uma lista. Corpo: ${response.body.substring(0, 100)}...',
          );
        }
      } else {
        print(
          '[ConsultaNome][ERRO REQ] Status: ${response.statusCode}. Body: ${response.body}',
        );
      }
    } catch (e) {
      print('[ConsultaNome][ERRO GERAL] $e');
    }
  }

  // ✅ MODIFICADO: Função de Autenticação genérica (para WMS e Prod)
  Future<String> _obterChaveApi(String endpoint, String email, String senha,
      int usuarioId) async {
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'senha': senha,
        'usuarioID': usuarioId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Falha ao autenticar. Código: ${response.statusCode}');
    }

    final body = jsonDecode(response.body);
    final redirect = body['redirecionarPara']?.toString();

    // Lógica para extrair o token (chave) da string de redirecionamento
    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect!);

    if (match != null) {
      return match.group(1)!;
    }

    throw Exception('Não foi possível extrair a chave da API.');
  }

  DateTime? _parseData(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }
}

// Model para resultado (Mantido)
class _MapaResultado {
  final DateTime data;
  final List<Map<String, dynamic>> registros;

  const _MapaResultado({required this.data, required this.registros});
}

// ✅ MODIFICADO: _MapaCard para remover OP e usar o nome do produto do cache
class _MapaCard extends StatelessWidget {
  final _MapaResultado resultado;

  const _MapaCard({required this.resultado});

  // Função utilitária para obter o nome do produto do cache
  String _getNomeProduto(int? produtoId) {
    if (produtoId == null) return '-- Produto Desconhecido --';
    final nome =
        _produtosCache[produtoId] ?? 'ID: $produtoId (Nome não encontrado)';
    // ✅ PRINT: Mostra qual nome foi buscado para o Card
    print('[MapaCard] Exibindo Produto ID: $produtoId | Nome: $nome');
    return nome;
  }

  @override
  Widget build(BuildContext context) {
    final dataFormatada = DateFormat('dd/MM/yyyy').format(resultado.data);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.all(16),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        title: Text(
          'Data: $dataFormatada',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        subtitle: Text(
          '${resultado.registros.length} registro(s) encontrados',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        children: resultado.registros
            .map(
              (registro) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  // ✅ MODIFICADO: Exibe o nome do produto (Artigo)
                  title: Text(
                    'Produto: ${_getNomeProduto(registro['produtoId'] as int?)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✅ REMOVIDO: Linha que exibia a Ordem de Produção (OP)
                      Text('Lote: ${registro['loteId'] ?? '--'}'),
                      Text(
                        'Quantidade: ${registro['quantidade'] ?? '--'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}