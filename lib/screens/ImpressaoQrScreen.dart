// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;

// // =========================================================================
// // PALETA OFICIAL
// // =========================================================================
// const Color _kPrimaryColor = Color(0xFF2563EB);
// const Color _kAccentColor = Color(0xFF60A5FA);
// const Color _kBgTop = Color(0xFF050A14);
// const Color _kBgBottom = Color(0xFF0B1220);
// const Color _kSurface = Color(0xFF101B34);
// const Color _kSurface2 = Color(0xFF0F172A);
// const Color _kTextPrimary = Color(0xFFF9FAFB);
// const Color _kTextSecondary = Color(0xFF9CA3AF);
// const Color _kBorderSoft = Color(0x33FFFFFF);

// // =========================================================================
// // GERADOR ZPL PARA ZEBRA ZD220
// // =========================================================================
// class ZebraZPLGenerator {
//   /// Gera comando ZPL para etiqueta 80x50mm
//   static String gerarZPL({
//     required String qrData,
//     required String cdObj,
//     required String nome,
//     String detalhe = '',
//     String descricao = '',
//     String ean13 = '',
//     String metragem = '',
//   }) {
//     final buffer = StringBuffer();

//     // Cabeçalho
//     buffer.writeln('^XA'); // Iniciar
//     buffer.writeln('^LL393'); // Altura: 50mm em dots (203 DPI)
//     buffer.writeln('^PW628'); // Largura: 80mm em dots
//     buffer.writeln('^CI28'); // UTF-8

//     // QR Code (esquerda)
//     buffer.writeln('^BY3,3,100'); // Tamanho QR
//     buffer.writeln('^FO50,40^BQN,2,8^FDMA,$qrData^FS');

//     // Código do objeto (topo direita)
//     buffer.writeln('^FO340,40^AAN,20,15^FD$cdObj^FS');

//     // Nome
//     buffer.writeln('^FO340,80^AAN,16,12^FB280,2,0,L^FD$nome^FS');

//     // Detalhe
//     if (detalhe.isNotEmpty) {
//       buffer.writeln('^FO340,130^AAN,11,9^FDDet: $detalhe^FS');
//     }

//     // EAN13
//     if (ean13.isNotEmpty) {
//       buffer.writeln('^FO340,150^AAN,11,9^FDEAN: $ean13^FS');
//     }

//     // Metragem
//     if (metragem.isNotEmpty) {
//       buffer.writeln('^FO340,170^AAN,11,9^FDMtr: $metragem^FS');
//     }

//     // Finalizar
//     buffer.writeln('^XZ');

//     return buffer.toString();
//   }

//   /// Gera comando para testar impressora (imprime página de configuração)
//   static String gerarTesteImpressora() {
//     return '^XA^LL393^PW628^FO50,50^AAN,28,20^FDZEBRA ZD220^FS'
//         '^FO50,100^AAN,16,12^FDPronta para Usar!^FS'
//         '^XZ';
//   }
// }

// // =========================================================================
// // GERENCIADOR ZEBRA - COMUNICAÇÃO VIA SOCKET
// // =========================================================================
// class ZebraManager {
//   final String ipAddress;
//   final int port;

//   Socket? _socket;
//   bool _conectado = false;

//   ZebraManager({required this.ipAddress, this.port = 9100});

//   bool get conectado => _conectado;

//   /// Conecta à impressora via TCP Socket
//   Future<bool> conectar() async {
//     try {
//       _socket =
//           await Socket.connect(
//             ipAddress,
//             port,
//             timeout: const Duration(seconds: 5),
//           ).catchError((e) {
//             print('Erro ao conectar: $e');
//             throw Exception('Não conseguiu conectar à impressora');
//           });

//       _conectado = true;
//       print('✅ Conectado à Zebra em $ipAddress:$port');
//       return true;
//     } catch (e) {
//       _conectado = false;
//       print('❌ Erro de conexão: $e');
//       return false;
//     }
//   }

//   /// Desconecta da impressora
//   Future<void> desconectar() async {
//     if (_socket != null) {
//       await _socket!.close();
//       _socket = null;
//       _conectado = false;
//       print('Desconectado da impressora');
//     }
//   }

//   /// Envia comando ZPL para a impressora
//   Future<bool> enviarZPL(String zplCommand) async {
//     if (_socket == null || !_conectado) {
//       print('❌ Socket não está conectado');
//       return false;
//     }

//     try {
//       // Converter string para bytes UTF-8 e enviar
//       final bytes = utf8.encode(zplCommand);
//       _socket!.add(bytes);

//       // Aguardar confirmação
//       await _socket!.flush();
//       print('✅ Comando ZPL enviado com sucesso');
//       return true;
//     } catch (e) {
//       print('❌ Erro ao enviar ZPL: $e');
//       _conectado = false;
//       return false;
//     }
//   }

//   /// Testa a conexão enviando comando de teste
//   Future<bool> testarImpressora() async {
//     final comandoTeste = ZebraZPLGenerator.gerarTesteImpressora();
//     return await enviarZPL(comandoTeste);
//   }
// }

// // =========================================================================
// // TELA PRINCIPAL - IMPRESSÃO QR
// // =========================================================================
// class ImpressaoQrScreen extends StatefulWidget {
//   final String conferente;

//   const ImpressaoQrScreen({super.key, required this.conferente});

//   @override
//   State<ImpressaoQrScreen> createState() => _ImpressaoQrScreenState();
// }

// class _ImpressaoQrScreenState extends State<ImpressaoQrScreen> {
//   static const String _kBaseUrlFlask = "http://168.190.90.2:5000";

//   late ZebraManager _zebraManager;
//   final TextEditingController _codigoController = TextEditingController();
//   final TextEditingController _ipController = TextEditingController(
//     text: '192.168.1.100',
//   );

//   bool _loading = false;
//   bool _zebraConectada = false;
//   String? _erro;
//   List<Map<String, dynamic>> _resultados = [];

//   bool get _autorizado {
//     final nome = widget.conferente.trim().toLowerCase();
//     return nome == 'joao' || nome == 'admin';
//   }

//   @override
//   void initState() {
//     super.initState();
//     _inicializarZebra();
//   }

//   void _inicializarZebra() {
//     _zebraManager = ZebraManager(
//       ipAddress: _ipController.text.trim(),
//       port: 9100,
//     );
//   }

//   Future<void> _conectarImpressora() async {
//     setState(() => _loading = true);

//     try {
//       final sucesso = await _zebraManager.conectar();
//       setState(() {
//         _zebraConectada = sucesso;
//         if (sucesso) {
//           _erro = null;
//           _showSnack('✅ Impressora conectada!');
//         } else {
//           _erro = 'Não conseguiu conectar à impressora';
//           _showSnack(_erro!, isError: true);
//         }
//       });
//     } catch (e) {
//       setState(() {
//         _zebraConectada = false;
//         _erro = 'Erro: $e';
//       });
//       _showSnack('Erro ao conectar: $e', isError: true);
//     } finally {
//       setState(() => _loading = false);
//     }
//   }

//   Future<void> _testarImpressora() async {
//     if (!_zebraConectada) {
//       _showSnack('Conecte à impressora primeiro!', isError: true);
//       return;
//     }

//     setState(() => _loading = true);

//     try {
//       final sucesso = await _zebraManager.testarImpressora();
//       if (sucesso) {
//         _showSnack('✅ Teste enviado! Verifique a impressora.');
//       } else {
//         _showSnack('Erro ao enviar teste.', isError: true);
//       }
//     } catch (e) {
//       _showSnack('Erro: $e', isError: true);
//     } finally {
//       setState(() => _loading = false);
//     }
//   }

//   @override
//   void dispose() {
//     _codigoController.dispose();
//     _ipController.dispose();
//     _zebraManager.desconectar();
//     super.dispose();
//   }

//   void _showSnack(String msg, {bool isError = false}) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(msg),
//         backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
//         duration: Duration(seconds: isError ? 3 : 2),
//       ),
//     );
//   }

//   Future<void> _consultar() async {
//     final codigo = _codigoController.text.trim();
//     if (codigo.isEmpty) {
//       _showSnack('Informe o código do artigo ou EAN.', isError: true);
//       return;
//     }

//     setState(() {
//       _loading = true;
//       _erro = null;
//       _resultados = [];
//     });

//     try {
//       final uri = Uri.parse(
//         "$_kBaseUrlFlask/consultar/artigos",
//       ).replace(queryParameters: {'codigo': codigo});
//       final resp = await http.get(uri);

//       if (resp.statusCode == 200) {
//         final decoded = jsonDecode(resp.body);
//         if (decoded is List) {
//           setState(() => _resultados = decoded.cast<Map<String, dynamic>>());
//           if (_resultados.isEmpty) {
//             _showSnack('Nenhum artigo encontrado.', isError: true);
//           }
//         } else {
//           setState(() => _erro = 'Resposta inválida do servidor.');
//         }
//       } else {
//         setState(() => _erro = 'Erro: ${resp.statusCode}');
//       }
//     } catch (e) {
//       setState(() => _erro = 'Erro de rede: $e');
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   Future<void> _imprimirItem(Map<String, dynamic> item) async {
//     if (!_zebraConectada) {
//       _showSnack('Conecte à impressora primeiro!', isError: true);
//       return;
//     }

//     final qrData = item['QrCode']?.toString() ?? '';
//     if (qrData.isEmpty) {
//       _showSnack('QR Code não disponível.', isError: true);
//       return;
//     }

//     setState(() => _loading = true);

//     try {
//       final zpl = ZebraZPLGenerator.gerarZPL(
//         qrData: qrData,
//         cdObj: item['CdObj']?.toString() ?? '',
//         nome: item['NmObj']?.toString() ?? '',
//         detalhe: item['Detalhe']?.toString() ?? '',
//         descricao: item['Descricao']?.toString() ?? '',
//         ean13: item['Ean13']?.toString() ?? '',
//         metragem: item['Metragem']?.toString() ?? '',
//       );

//       final sucesso = await _zebraManager.enviarZPL(zpl);

//       if (sucesso) {
//         _showSnack('✅ Etiqueta enviada para impressão!');
//       } else {
//         _showSnack('Erro ao enviar etiqueta.', isError: true);
//       }
//     } catch (e) {
//       _showSnack('Erro: $e', isError: true);
//     } finally {
//       setState(() => _loading = false);
//     }
//   }

//   Widget _buildResultadoCard(Map<String, dynamic> item) {
//     final cdObj = item['CdObj']?.toString() ?? '--';
//     final nome = item['NmObj']?.toString() ?? 'N/A';
//     final detalhe = item['Detalhe']?.toString() ?? '';
//     final ean13 = item['Ean13']?.toString() ?? '';
//     final metragem = item['Metragem']?.toString() ?? '';

//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: _kSurface2,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: _kBorderSoft),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             '$cdObj - $nome',
//             style: const TextStyle(
//               color: _kTextPrimary,
//               fontWeight: FontWeight.w800,
//               fontSize: 14,
//             ),
//           ),
//           const SizedBox(height: 6),
//           if (detalhe.isNotEmpty)
//             Text(
//               'Detalhe: $detalhe',
//               style: const TextStyle(color: _kTextSecondary, fontSize: 12),
//             ),
//           if (ean13.isNotEmpty)
//             Text(
//               'EAN13: $ean13',
//               style: const TextStyle(color: _kTextSecondary, fontSize: 12),
//             ),
//           if (metragem.isNotEmpty)
//             Text(
//               'Metragem: $metragem',
//               style: const TextStyle(color: _kTextSecondary, fontSize: 12),
//             ),
//           const SizedBox(height: 10),
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton.icon(
//               onPressed: _zebraConectada && !_loading
//                   ? () => _imprimirItem(item)
//                   : null,
//               icon: const Icon(Icons.print, size: 18),
//               label: const Text('Imprimir Etiqueta'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: _kPrimaryColor,
//                 foregroundColor: Colors.white,
//                 disabledBackgroundColor: Colors.grey,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (!_autorizado) {
//       return Scaffold(
//         backgroundColor: _kBgBottom,
//         appBar: AppBar(
//           title: const Text('Impressão QR'),
//           backgroundColor: _kBgBottom,
//           foregroundColor: _kTextPrimary,
//         ),
//         body: const Center(
//           child: Text(
//             'Acesso restrito.',
//             style: TextStyle(color: _kTextSecondary),
//           ),
//         ),
//       );
//     }

//     return Scaffold(
//       backgroundColor: _kBgBottom,
//       appBar: AppBar(
//         centerTitle: true,
//         elevation: 0,
//         foregroundColor: _kTextPrimary,
//         backgroundColor: _kBgBottom,
//         title: const Text(
//           'Impressão QR - Zebra',
//           style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
//         ),
//         flexibleSpace: Container(
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [_kBgTop, _kSurface2, _kBgBottom],
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//             ),
//           ),
//         ),
//       ),
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.all(18),
//           child: Column(
//             children: [
//               // ===== CARD DE CONEXÃO DA IMPRESSORA =====
//               Container(
//                 padding: const EdgeInsets.all(14),
//                 decoration: BoxDecoration(
//                   color: _kSurface,
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(
//                     color: _zebraConectada
//                         ? Colors.green.withAlpha(128)
//                         : Colors.orange.withAlpha(128),
//                     width: 2,
//                   ),
//                 ),
//                 child: Column(
//                   children: [
//                     // Status
//                     Row(
//                       children: [
//                         Container(
//                           width: 12,
//                           height: 12,
//                           decoration: BoxDecoration(
//                             shape: BoxShape.circle,
//                             color: _zebraConectada ? Colors.green : Colors.red,
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: Text(
//                             _zebraConectada
//                                 ? 'Zebra ZD220 Conectada'
//                                 : 'Desconectada',
//                             style: TextStyle(
//                               color: _zebraConectada
//                                   ? Colors.green
//                                   : Colors.redAccent,
//                               fontWeight: FontWeight.w600,
//                               fontSize: 14,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 12),

//                     // Input IP
//                     TextField(
//                       controller: _ipController,
//                       style: const TextStyle(color: _kTextPrimary),
//                       enabled: !_zebraConectada,
//                       decoration: InputDecoration(
//                         labelText: 'IP da Impressora',
//                         labelStyle: const TextStyle(color: _kTextSecondary),
//                         hintText: '192.168.1.100',
//                         hintStyle: const TextStyle(color: _kTextSecondary),
//                         filled: true,
//                         fillColor: _kSurface2,
//                         enabledBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: const BorderSide(color: _kBorderSoft),
//                         ),
//                         focusedBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: const BorderSide(
//                             color: _kAccentColor,
//                             width: 2,
//                           ),
//                         ),
//                         disabledBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: const BorderSide(color: _kBorderSoft),
//                         ),
//                         prefixIcon: const Icon(
//                           Icons.router,
//                           color: _kAccentColor,
//                         ),
//                       ),
//                       onChanged: (_) => _inicializarZebra(),
//                     ),
//                     const SizedBox(height: 12),

//                     // Botões
//                     Row(
//                       children: [
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             onPressed: _loading ? null : _conectarImpressora,
//                             icon: _loading
//                                 ? const SizedBox(
//                                     width: 18,
//                                     height: 18,
//                                     child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                       valueColor: AlwaysStoppedAnimation(
//                                         Colors.white,
//                                       ),
//                                     ),
//                                   )
//                                 : Icon(
//                                     _zebraConectada
//                                         ? Icons.check_circle
//                                         : Icons.bluetooth_connect,
//                                   ),
//                             label: Text(
//                               _zebraConectada ? 'Conectada' : 'Conectar',
//                             ),
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: _zebraConectada
//                                   ? Colors.green
//                                   : _kPrimaryColor,
//                               foregroundColor: Colors.white,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         ElevatedButton.icon(
//                           onPressed: _zebraConectada && !_loading
//                               ? _testarImpressora
//                               : null,
//                           icon: const Icon(Icons.print_outlined, size: 18),
//                           label: const Text('Testar'),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: _kAccentColor,
//                             foregroundColor: Colors.white,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),

//               // ===== CARD DE CONSULTA =====
//               Container(
//                 padding: const EdgeInsets.all(14),
//                 decoration: BoxDecoration(
//                   color: _kSurface,
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(color: _kBorderSoft),
//                 ),
//                 child: Column(
//                   children: [
//                     TextField(
//                       controller: _codigoController,
//                       style: const TextStyle(color: _kTextPrimary),
//                       decoration: InputDecoration(
//                         labelText: 'Código do artigo ou EAN',
//                         labelStyle: const TextStyle(color: _kTextSecondary),
//                         hintText: 'Digite o código',
//                         hintStyle: const TextStyle(color: _kTextSecondary),
//                         filled: true,
//                         fillColor: _kSurface2,
//                         enabledBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: const BorderSide(color: _kBorderSoft),
//                         ),
//                         focusedBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: const BorderSide(
//                             color: _kAccentColor,
//                             width: 2,
//                           ),
//                         ),
//                         prefixIcon: const Icon(
//                           Icons.qr_code_2,
//                           color: _kAccentColor,
//                         ),
//                       ),
//                       onSubmitted: (_) => _consultar(),
//                     ),
//                     const SizedBox(height: 12),
//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton.icon(
//                         onPressed: _loading ? null : _consultar,
//                         icon: _loading
//                             ? const SizedBox(
//                                 width: 18,
//                                 height: 18,
//                                 child: CircularProgressIndicator(
//                                   strokeWidth: 2,
//                                   valueColor: AlwaysStoppedAnimation(
//                                     Colors.white,
//                                   ),
//                                 ),
//                               )
//                             : const Icon(Icons.search),
//                         label: Text(_loading ? 'Consultando...' : 'Consultar'),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: _kPrimaryColor,
//                           foregroundColor: Colors.white,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),

//               // ===== MENSAGEM DE ERRO =====
//               if (_erro != null)
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 12,
//                     vertical: 8,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Colors.red.shade900.withAlpha(50),
//                     borderRadius: BorderRadius.circular(8),
//                     border: Border.all(color: Colors.redAccent),
//                   ),
//                   child: Text(
//                     _erro!,
//                     style: const TextStyle(
//                       color: Colors.redAccent,
//                       fontSize: 12,
//                     ),
//                   ),
//                 ),
//               const SizedBox(height: 12),

//               // ===== LISTA DE RESULTADOS =====
//               Expanded(
//                 child: _resultados.isEmpty
//                     ? Center(
//                         child: Text(
//                           _zebraConectada
//                               ? 'Nenhum artigo consultado.'
//                               : 'Conecte à impressora primeiro',
//                           style: const TextStyle(color: _kTextSecondary),
//                           textAlign: TextAlign.center,
//                         ),
//                       )
//                     : ListView.builder(
//                         itemCount: _resultados.length,
//                         itemBuilder: (context, index) =>
//                             _buildResultadoCard(_resultados[index]),
//                       ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =========================================================================
// PALETA OFICIAL
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

class ImpressaoQrScreen extends StatefulWidget {
  final String conferente;

  const ImpressaoQrScreen({super.key, required this.conferente});

  @override
  State<ImpressaoQrScreen> createState() => _ImpressaoQrScreenState();
}

class _ImpressaoQrScreenState extends State<ImpressaoQrScreen> {
  static const String _kBaseUrlFlask =
      "http://168.190.90.2:5000"; // API artigos
  static const String _kServidorImpressora =
      "http://168.190.30.154:5000"; // Servidor print

  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _servidorController = TextEditingController(
    text: 'http://168.190.30.154:5000',
  );

  bool _loading = false;
  bool _servidorConectado = false;
  String? _erro;
  List<Map<String, dynamic>> _resultados = [];

  bool get _autorizado {
    final nome = widget.conferente.trim().toLowerCase(); // ✅ CERTO
    return nome == 'joao' || nome == 'admin';
  }

  @override
  void initState() {
    super.initState();
    _testarServidor();
  }

  Future<void> _testarServidor() async {
    try {
      final response = await http
          .get(Uri.parse('${_servidorController.text}/status'))
          .timeout(const Duration(seconds: 3));

      setState(() {
        _servidorConectado = response.statusCode == 200;
      });

      if (_servidorConectado) {
        _showSnack('✅ Servidor de impressão conectado!');
      }
    } catch (e) {
      setState(() => _servidorConectado = false);
      _showSnack('Servidor de impressão não encontrado', isError: true);
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _servidorController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: isError ? 3 : 2),
      ),
    );
  }

  Future<void> _consultar() async {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) {
      _showSnack('Informe o código do artigo ou EAN.', isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _erro = null;
      _resultados = [];
    });

    try {
      final uri = Uri.parse(
        "$_kBaseUrlFlask/consultar/artigos",
      ).replace(queryParameters: {'codigo': codigo});
      final resp = await http.get(uri);

      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is List) {
          setState(() => _resultados = decoded.cast<Map<String, dynamic>>());
          if (_resultados.isEmpty) {
            _showSnack('Nenhum artigo encontrado.', isError: true);
          }
        } else {
          setState(() => _erro = 'Resposta inválida do servidor.');
        }
      } else {
        setState(() => _erro = 'Erro: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() => _erro = 'Erro de rede: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _imprimirItem(Map<String, dynamic> item) async {
    if (!_servidorConectado) {
      _showSnack('Servidor de impressão não está conectado!', isError: true);
      return;
    }

    final qrCode = item['QrCode']?.toString() ?? '';
    if (qrCode.isEmpty) {
      _showSnack('QR Code não disponível.', isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      final payload = {
        'cdObj': item['CdObj']?.toString() ?? '',
        'nome': item['NmObj']?.toString() ?? '',
        'qrCode': qrCode,
        'detalhe': item['Detalhe']?.toString() ?? '',
        'ean13': item['Ean13']?.toString() ?? '',
        'metragem': item['Metragem']?.toString() ?? '',
      };

      final response = await http
          .post(
            Uri.parse('${_servidorController.text}/imprimir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _showSnack('✅ Enviado para impressora!');
      } else {
        _showSnack('Erro ao enviar para impressora.', isError: true);
      }
    } catch (e) {
      _showSnack('Erro: $e', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildResultadoCard(Map<String, dynamic> item) {
    final cdObj = item['CdObj']?.toString() ?? '--';
    final nome = item['NmObj']?.toString() ?? 'N/A';
    final detalhe = item['Detalhe']?.toString() ?? '';
    final ean13 = item['Ean13']?.toString() ?? '';
    final metragem = item['Metragem']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$cdObj - $nome',
            style: const TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          if (detalhe.isNotEmpty)
            Text(
              'Detalhe: $detalhe',
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          if (ean13.isNotEmpty)
            Text(
              'EAN13: $ean13',
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          if (metragem.isNotEmpty)
            Text(
              'Metragem: $metragem',
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _servidorConectado && !_loading
                  ? () => _imprimirItem(item)
                  : null,
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Imprimir Etiqueta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_autorizado) {
      return Scaffold(
        backgroundColor: _kBgBottom,
        appBar: AppBar(
          title: const Text('Impressão QR'),
          backgroundColor: _kBgBottom,
          foregroundColor: _kTextPrimary,
        ),
        body: const Center(
          child: Text(
            'Acesso restrito.',
            style: TextStyle(color: _kTextSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kBgBottom,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: _kTextPrimary,
        backgroundColor: _kBgBottom,
        title: const Text(
          'Impressão QR - Zebra',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kBgTop, _kSurface2, _kBgBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              // ===== STATUS DO SERVIDOR =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _servidorConectado
                        ? Colors.green.withAlpha(128)
                        : Colors.orange.withAlpha(128),
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _servidorConectado ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _servidorConectado
                            ? 'Impressora Conectada'
                            : 'Impressora Desconectada',
                        style: TextStyle(
                          color: _servidorConectado
                              ? Colors.green
                              : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _testarServidor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccentColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Conectar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===== CARD DE CONSULTA =====
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _kBorderSoft),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _codigoController,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Código do artigo ou EAN',
                        labelStyle: const TextStyle(color: _kTextSecondary),
                        hintText: 'Digite o código',
                        hintStyle: const TextStyle(color: _kTextSecondary),
                        filled: true,
                        fillColor: _kSurface2,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _kAccentColor,
                            width: 2,
                          ),
                        ),
                        prefixIcon: const Icon(
                          Icons.qr_code_2,
                          color: _kAccentColor,
                        ),
                      ),
                      onSubmitted: (_) => _consultar(),
                    ),
                    const SizedBox(height: 12),
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
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_loading ? 'Consultando...' : 'Consultar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ===== ERRO =====
              if (_erro != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    _erro!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // ===== RESULTADOS =====
              Expanded(
                child: _resultados.isEmpty
                    ? Center(
                        child: Text(
                          _servidorConectado
                              ? 'Nenhum artigo consultado.'
                              : 'Conecte a impressora primeiro',
                          style: const TextStyle(color: _kTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _resultados.length,
                        itemBuilder: (context, index) =>
                            _buildResultadoCard(_resultados[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
