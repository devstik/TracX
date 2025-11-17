import 'package:tracx/models/qr_code_data_tinturaria.dart';
import 'package:tracx/models/registro_tinturaria.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../screens/ListaRegistrosScreen.dart';
import '../screens/login_screen.dart';

// =========================================================================
// CORES E CONSTANTES
// =========================================================================

const Color _kPrimaryColor = Color(
  0xFFCD1818,
); // Vermelho Principal (App Bar, Ações Principais, Ícones do Formulário)
const Color _kAccentColor = Color(0xFF3A59D1); // Azul (Cantos do QR Scanner)
const Color _kBackgroundColor = Color(0xFFF0F2F5); // Fundo Leve
const Color _kInputFillColor = Colors.white; // Cor de preenchimento do input

// =========================================================================
// CLASSES AUXILIARES ORIGINAIS
// =========================================================================

// Classe de controle de texto para data
class DateTextController extends TextEditingController {
  DateTextController({String? text}) : super(text: text);
}

// Classe que formata a entrada de texto em tempo real para dd/mm/yy
class DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll('/', '');

    if (newText.length > 6) {
      return oldValue;
    }

    String formattedText = '';
    for (int i = 0; i < newText.length; i++) {
      if (i == 2 || i == 4) {
        formattedText += '/';
      }
      formattedText += newText[i];
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

// =========================================================================
// TELA DE REGISTRO (ALTERADA)
// =========================================================================

class RegistroScreenTinturaria extends StatefulWidget {
  final String conferente;
  RegistroScreenTinturaria({required this.conferente});

  @override
  _RegistroScreenTinturariaState createState() =>
      _RegistroScreenTinturariaState();
}

class _RegistroScreenTinturariaState extends State<RegistroScreenTinturaria> {
  final _formKey = GlobalKey<FormState>();

  final _nomeMaterialController = TextEditingController();
  final _larguraCruaController = TextEditingController();
  final _elasticidadeCruaController = TextEditingController();
  final _nMaquinaController = TextEditingController();
  final _dataCorteController = DateTextController();
  final _loteElasticoController = TextEditingController();
  final _conferenteController = TextEditingController();
  final _turnoController = TextEditingController();

  DateTime? _data;
  // Variável _selectedIndex removida, pois esta tela deve ser apenas o formulário.
  bool _formBloqueado = false;

  @override
  void initState() {
    super.initState();
    _data = DateTime.now();
    _conferenteController.text = widget.conferente;
    _turnoController.text = _getTurno();
  }

  @override
  void dispose() {
    _nomeMaterialController.dispose();
    _larguraCruaController.dispose();
    _elasticidadeCruaController.dispose();
    _nMaquinaController.dispose();
    _dataCorteController.dispose();
    _loteElasticoController.dispose();
    _conferenteController.dispose();
    _turnoController.dispose();
    super.dispose();
  }

  String _getTurno() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour <= 14) return 'Turno A';
    if (hour > 14 && hour <= 22) return 'Turno B';
    return 'Turno C';
  }

  Future<void> _scanQR() async {
    try {
      final qr = await Navigator.push<QrCodeDataTinturaria>(
        context,
        MaterialPageRoute(
          builder: (_) => const QrScannerPage(),
          fullscreenDialog: true, // Adicione esta linha
        ),
      );

      if (qr != null && mounted) {
        // Verifique se o widget ainda está montado
        setState(() {
          _nomeMaterialController.text = qr.nomeMaterial;
          _larguraCruaController.text = qr.larguraCrua;
          _elasticidadeCruaController.text = qr.elasticidadeCrua;
          _nMaquinaController.text = qr.nMaquina;
          _dataCorteController.text = qr.dataCorte;
          _loteElasticoController.text = qr.loteElastico;
          _formBloqueado = true;
        });
      }
    } catch (e) {
      print('Erro ao escanear QR Code: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao ler QR Code. Tente novamente.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _salvarRegistro() async {
    if (_formKey.currentState!.validate() && _data != null) {
      final registro = RegistroTinturaria(
        nomeMaterial: _nomeMaterialController.text,
        larguraCrua: _larguraCruaController.text,
        elasticidadeCrua: _elasticidadeCruaController.text,
        nMaquina: _nMaquinaController.text,
        dataCorte: _dataCorteController.text,
        loteElastico: _loteElasticoController.text,
        conferente: _conferenteController.text,
        turno: _turnoController.text,
      );

      enviarRegistroParaAPI(registro);

      // Limpa os campos preenchidos pelo QR Code
      _nomeMaterialController.clear();
      _larguraCruaController.clear();
      _elasticidadeCruaController.clear();
      _nMaquinaController.clear();
      _dataCorteController.clear();
      _loteElasticoController.clear();

      // Desbloqueia o formulário para a próxima leitura/registro
      _formBloqueado = false;
      setState(() {});
    }
  }

  Future<void> enviarRegistroParaAPI(RegistroTinturaria registro) async {
    final url = Uri.parse('http://168.190.90.2:5000/consulta/tinturaria');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode(registro.toJson());

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Sucesso na API: ${response.statusCode} - ${response.body}");
      } else {
        print("❌ Erro na API: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ Exceção ao enviar registro: $e");
    }
  }

  // Função centralizada para estilizar a decoração dos inputs
  InputDecoration _getInputDecoration(
    String label,
    IconData icon, {
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: 'Informe o $label',
      prefixIcon: Icon(
        icon,
        color: enabled ? _kPrimaryColor : Colors.grey.shade400,
      ),
      filled: true,
      fillColor: enabled ? _kInputFillColor : Colors.grey.shade200,
      enabled: enabled,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide(
          color: enabled ? Colors.grey.shade300 : Colors.grey.shade400,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(color: _kPrimaryColor, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(color: _kPrimaryColor, width: 2.0),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 15.0,
        horizontal: 10.0,
      ),
      floatingLabelStyle: TextStyle(
        color: enabled ? _kPrimaryColor : Colors.grey.shade600,
        fontWeight: FontWeight.bold,
      ),
      counterText: '',
    );
  }

  // WIDGET: CAMPO DE TEXTO
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        maxLength: maxLength,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.black87),
        keyboardType: keyboardType,
        decoration: _getInputDecoration(label, icon, enabled: enabled),
        validator: (value) => value == null || value.isEmpty
            ? 'O campo $label é obrigatório.'
            : null,
      ),
    );
  }

  // WIDGET: INFORMAÇÕES DE RODAPÉ
  Widget _buildFooterInfo() {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 20.0),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _kInputFillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: _kPrimaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Conferente: ${widget.conferente}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.access_time, size: 20, color: _kPrimaryColor),
                const SizedBox(width: 8),
                Text(
                  'Turno: ${_getTurno()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulario() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0), // Ajuste de padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Botão de QR Code
            Padding(
              padding: const EdgeInsets.only(top: 0.0, bottom: 20.0),
              child: ElevatedButton.icon(
                onPressed: _scanQR,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text(
                  'Ler QR Code',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryColor, // Cor Principal
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 5,
                ),
              ),
            ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  // Campos do formulário
                  _buildTextField(
                    _nomeMaterialController,
                    'Nome do Material',
                    Icons.texture,
                    enabled: !_formBloqueado,
                  ),
                  _buildTextField(
                    _larguraCruaController,
                    'Largura Crua',
                    Icons.straighten,
                    keyboardType: TextInputType.number,
                    enabled: !_formBloqueado,
                  ),
                  _buildTextField(
                    _elasticidadeCruaController,
                    'Elasticidade Crua',
                    Icons.compare_arrows,
                    keyboardType: TextInputType.number,
                    enabled: !_formBloqueado,
                  ),
                  _buildTextField(
                    _nMaquinaController,
                    'Número da Máquina',
                    Icons.precision_manufacturing,
                    keyboardType: TextInputType.number,
                    enabled: !_formBloqueado,
                  ),
                  _buildTextField(
                    _dataCorteController,
                    'Data de Corte',
                    Icons.calendar_today,
                    keyboardType: TextInputType.datetime,
                    enabled: !_formBloqueado,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      DateTextFormatter(),
                    ],
                  ),
                  _buildTextField(
                    _loteElasticoController,
                    'Lote Elástico',
                    Icons.category,
                    enabled: !_formBloqueado,
                  ),

                  const SizedBox(height: 24),

                  // Botão Salvar
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _salvarRegistro,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 5,
                        // Estilo para desativado
                        disabledBackgroundColor: Colors.grey.shade400,
                        disabledForegroundColor: Colors.grey.shade700,
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text(
                        'Salvar Registro',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Informações de Rodapé
                  _buildFooterInfo(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // O método _getBody foi removido e a lógica transferida diretamente para o build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body:
          _buildFormulario(), // <--- Alterado para chamar diretamente o formulário
    );
  }
}

// =========================================================================
// WIDGET: SCANNER DE QR CODE
// =========================================================================

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

// Substitua a classe _QrScannerPageState

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _cameraController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false; // Previne múltiplas leituras

  QrCodeDataTinturaria? _parseQrCode(String? qrCode) {
    if (qrCode == null || qrCode.isEmpty) {
      return null;
    }

    try {
      final Map<String, dynamic> jsonMap = jsonDecode(qrCode);
      final qrData = QrCodeDataTinturaria.fromJson(jsonMap);
      return qrData;
    } catch (e) {
      print('Erro ao decodificar QR Code como JSON: $e');
      return null;
    }
  }

  void _handleQrCodeDetected(QrCodeDataTinturaria qrData) async {
    if (_isProcessing) return; // Previne múltiplas execuções

    setState(() {
      _isProcessing = true;
    });

    // Feedback visual
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text('QR Code detectado!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );

    // Pequeno delay para dar feedback visual
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      // Retorna os dados para a tela anterior
      Navigator.of(context).pop(qrData);
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double scannerSize = 250.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Escanear QR Code'),
        backgroundColor: _kPrimaryColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // 1. Scanner de Câmera (Fundo)
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              if (_isProcessing) return; // Ignora se já está processando

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? qrString = barcodes.first.rawValue;
                if (qrString != null) {
                  final qrData = _parseQrCode(qrString);
                  if (qrData != null) {
                    _handleQrCodeDetected(qrData);
                  } else {
                    // Feedback de QR Code inválido
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.error, color: Colors.white),
                            SizedBox(width: 10),
                            Text('QR Code inválido ou incompleto!'),
                          ],
                        ),
                        backgroundColor: _kPrimaryColor,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
            },
          ),

          // 2. Overlay de Fundo Escuro com Recorte
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.6),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: scannerSize,
                    height: scannerSize,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Pintura dos Cantos
          Center(
            child: CustomPaint(
              size: const Size(scannerSize, scannerSize),
              painter: _QrScannerCornersPainter(),
            ),
          ),

          // 4. Instrução de texto
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 40.0),
              child: Text(
                'Posicione o QR Code dentro do quadro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  backgroundColor: Color(0xAA000000),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // 5. Botão de Lanterna
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: _TorchButton(controller: _cameraController),
            ),
          ),

          // 6. Indicador de processamento
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: _kPrimaryColor),
              ),
            ),
        ],
      ),
    );
  }
}

class _TorchButton extends StatefulWidget {
  final MobileScannerController controller;
  const _TorchButton({required this.controller});

  @override
  State<_TorchButton> createState() => _TorchButtonState();
}

class _TorchButtonState extends State<_TorchButton> {
  bool isTorchOn = false;

  void _toggleTorch() {
    setState(() {
      isTorchOn = !isTorchOn;
    });
    widget.controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: IconButton(
        icon: Icon(
          isTorchOn ? Icons.flash_on : Icons.flash_off,
          color: isTorchOn ? _kAccentColor : Colors.white,
          size: 28,
        ),
        onPressed: _toggleTorch,
        tooltip: isTorchOn ? 'Desligar Lanterna' : 'Ligar Lanterna',
      ),
    );
  }
}

// WIDGET: PINTURA DOS CANTOS
class _QrScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kAccentColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    final cornerLength = size.width / 5;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cornerLength), paint);

    // Top-Right
    canvas.drawLine(
      Offset(size.width - cornerLength, 0),
      Offset(size.width, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLength),
      paint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLength),
      paint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(size.width - cornerLength, size.height),
      Offset(size.width, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height - cornerLength),
      Offset(size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
