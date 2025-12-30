import 'package:intl/intl.dart';
import 'dart:async';
import '../screens/ConsultaMapaProducaoScreen.dart'; // Para acessar AppConstants e ApiService
import 'estoque_db_helper.dart';

class SyncService {
  static Future<void> sincronizarHistorico() async {
    final dbHelper = EstoqueDbHelper();
    
    // 1. Definir intervalo: 01 do mês atual até ontem
    DateTime agora = DateTime.now();
    DateTime dataInicial = DateTime(agora.year, agora.month, 1);
    DateTime dataOntem = agora.subtract(const Duration(days: 1));

    if (dataOntem.isBefore(dataInicial)) return;

    // 2. Autenticar uma única vez para o WMS
    String token = await ApiService.authenticate(
      endpoint: AppConstants.authEndpointWMS,
      email: AppConstants.authEmailWMS,
      senha: AppConstants.authSenhaWMS,
      usuarioId: AppConstants.authUsuarioIdWMS,
    );

    // 3. Gerar lista de datas que NÃO estão no banco
    List<DateTime> diasParaBuscar = [];
    for (DateTime d = dataInicial; !d.isAfter(dataOntem); d = d.add(const Duration(days: 1))) {
      String iso = DateFormat("yyyy-MM-dd'T'00:00:00").format(d);
      var existente = await dbHelper.getMapasByDate(iso);
      if (existente.isEmpty) diasParaBuscar.add(d);
    }

    if (diasParaBuscar.isEmpty) return;

    // 4. Executar consultas em PARALELO (Batch de requisições)
    // Limitamos a concorrência para não sobrecarregar o servidor ou o app
    await Future.wait(diasParaBuscar.map((data) async {
      String iso = DateFormat("yyyy-MM-dd'T'00:00:00").format(data);
      try {
        final registros = await ApiService.fetchMapByDate(
          apiKeyWMS: token,
          isoDate: iso,
        );
        if (registros.isNotEmpty) {
          await dbHelper.insertMapas(registros, iso);
        }
      } catch (e) {
        print("Erro ao sincronizar dia $iso: $e");
      }
    }));
  }
}