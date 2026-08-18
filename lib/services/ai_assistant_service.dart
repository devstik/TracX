import 'dart:convert';

import 'package:http/http.dart' as http;

class AiAssistantMessage {
  const AiAssistantMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AiAssistantResponse {
  const AiAssistantResponse({
    required this.answer,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final String answer;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
}

class AiAssistantService {
  static const String _defaultUrl = 'http://168.190.30.154:3005/api/ai/chat';
  static const String _apiUrl = String.fromEnvironment(
    'AI_ASSISTANT_URL',
    defaultValue: _defaultUrl,
  );

  static Future<AiAssistantResponse> enviarMensagem({
    required String message,
    List<AiAssistantMessage> history = const [],
  }) async {
    final pergunta = message.trim();
    if (pergunta.isEmpty) {
      throw 'Digite uma pergunta para a IA.';
    }

    final response = await http
        .post(
          Uri.parse(_apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': pergunta,
            'history': _normalizarHistorico(history),
            'feedbacks': const [],
          }),
        )
        .timeout(const Duration(seconds: 60));

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('application/json')) {
      throw 'A IA retornou uma resposta invalida. Verifique se o servidor Node esta rodando em $_apiUrl.';
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw 'Resposta invalida da IA.';
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw (decoded['error'] ?? 'Nao foi possivel consultar a IA.').toString();
    }

    final answer = (decoded['answer'] ?? '').toString().trim();
    if (answer.isEmpty) {
      throw 'A resposta da IA veio vazia.';
    }

    final usage = decoded['usage'];
    return AiAssistantResponse(
      answer: answer,
      inputTokens: _toInt(usage is Map ? usage['inputTokens'] : null),
      outputTokens: _toInt(usage is Map ? usage['outputTokens'] : null),
      totalTokens: _toInt(usage is Map ? usage['totalTokens'] : null),
    );
  }

  static List<Map<String, dynamic>> _normalizarHistorico(
    List<AiAssistantMessage> history,
  ) {
    return history
        .where(
          (item) =>
              item.content.trim().isNotEmpty &&
              const {'user', 'assistant', 'system'}.contains(item.role),
        )
        .map((item) => item.toJson())
        .toList();
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
