import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tracx/models/HistoricoMov.dart';

class MovimentacaoService {
  static const String baseUrl =
      'http://168.190.90.2:5000/consulta/movimentacao';
  static const String historicoUrl =
      'http://168.190.90.2:5000/consulta/movimentacao_historico';

  // Registra movimentação COMPLETA (PUT) - MÉTODO ORIGINAL
  static Future<bool> registrarMovimentacaoCompleta({
    required int idPedido,
    required String localizacaoOrigem,
    required String localizacaoDestino,
    required String conferente,
    required DateTime dataMovimentacao,
    required String tipoMovimentacao,
  }) async {
    try {
      print('📤 Enviando movimentação COMPLETA:');
      print('   NrOrdem: $idPedido');
      print('   De: $localizacaoOrigem → Para: $localizacaoDestino');
      print('   Conferente: $conferente');
      print('   Tipo: $tipoMovimentacao');

      final response = await http.put(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'NrOrdem': idPedido,
          'LocalizacaoAnterior': localizacaoOrigem,
          'Localizacao': localizacaoDestino,
          'Conferente': conferente,
          // Converte para ISO 8601 string, o parser do Python sabe lidar com isso
          'DataSaida': dataMovimentacao.toIso8601String(),
          'TipoMovimentacao': tipoMovimentacao,
          // Sem 'QuantidadeMovida', API deve assumir movimento total
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Movimentação completa registrada com sucesso!');
        return true;
      } else if (response.statusCode == 404) {
        print('⚠️ Erro 404: ${response.body}');
        return false;
      } else {
        throw Exception(
          'Falha ao registrar movimentação. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Erro ao registrar movimentação completa: $e');
      rethrow;
    }
  }

  // Registra movimentação PARCIAL (PUT) - NOVO MÉTODO
  static Future<bool> registrarMovimentacaoParcial({
    required int idPedido,
    required String localizacaoOrigem,
    required String localizacaoDestino,
    required String conferente,
    required DateTime dataMovimentacao,
    required String tipoMovimentacao,
    required double metrosMovidos, // NOVO CAMPO
  }) async {
    try {
      print('📤 Enviando movimentação PARCIAL:');
      print('   NrOrdem: $idPedido');
      print('   Metros: $metrosMovidos');
      print('   De: $localizacaoOrigem → Para: $localizacaoDestino');
      print('   Conferente: $conferente');
      print('   Tipo: $tipoMovimentacao');

      // Endpoint é o mesmo, a API deve diferenciar pela presença de 'MetrosMovidos'
      final response = await http.put(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'NrOrdem': idPedido,
          'LocalizacaoAnterior': localizacaoOrigem,
          'Localizacao': localizacaoDestino,
          'Conferente': conferente,
          'DataSaida': dataMovimentacao.toIso8601String(),
          'TipoMovimentacao': tipoMovimentacao,
          'MetrosMovidos': metrosMovidos, // NOVO PARÂMETRO PARA API
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Movimentação parcial registrada com sucesso!');
        return true;
      } else if (response.statusCode == 404) {
        print('⚠️ Erro 404: ${response.body}');
        return false;
      } else {
        throw Exception(
          'Falha ao registrar movimentação parcial. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Erro ao registrar movimentação parcial: $e');
      rethrow;
    }
  }

  // 🛠️ FUNÇÃO CORRIGIDA 🛠️ (mantida, renomeada no escopo do arquivo)
  static Future<List<HistoricoMov>> buscarHistorico(int nrOrdem) async {
    try {
      // 1. Cria o mapa de parâmetros vazio
      Map<String, String> queryParams = {};

      // 2. Adiciona o nrOrdem SOMENTE se for maior que 0
      if (nrOrdem > 0) {
        queryParams['nrOrdem'] = nrOrdem.toString();
      }

      // 3. Monta a URI: se queryParams for vazio, replace usa o URL base sem '?'
      final uri = Uri.parse(
        historicoUrl,
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      print('🌐 URL: $uri');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);

        print('✅ Histórico encontrado: ${jsonList.length} registros');

        final historico = jsonList.map((jsonItem) {
          // Garante que o ID do histórico não seja nulo
          final int idHistorico = (jsonItem['ID'] as num?)?.toInt() ?? 0;

          return HistoricoMov(
            id: idHistorico,
            nrOrdem: jsonItem['NrOrdem'] ?? 0,
            localizacaoOrigem: jsonItem['LocalizacaoOrigem'] ?? 'N/A',
            localizacaoDestino: jsonItem['LocalizacaoDestino'] ?? 'N/A',
            dataMovimentacao: jsonItem['DataMovimentacao'] != null
                ? DateTime.parse(jsonItem['DataMovimentacao'])
                : DateTime.now(),
            conferente: jsonItem['Conferente'] ?? '',
            tipoMovimentacao: jsonItem['TipoMovimentacao'] ?? 'NORMAL',
          );
        }).toList();

        // Log para debug
        for (var mov in historico) {
          print(
            '   ${mov.localizacaoOrigem} → ${mov.localizacaoDestino} (${mov.tipoMovimentacao})',
          );
        }

        return historico;
      } else {
        throw Exception(
          'Falha ao carregar histórico. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Erro ao buscar histórico: $e');
      rethrow;
    }
  }
}
