import 'package:tracx/models/qr_code_data_tinturaria.dart';
import 'package:tracx/models/registro_tinturaria.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// =========================================================================
// 🎨 PALETA OFICIAL (PADRÃO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFF2563EB); // Azul principal (moderno)
const Color _kAccentColor = Color(0xFF60A5FA); // Azul claro premium

const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);

const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);

const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);

// borda mais visível
const Color _kBorderSoft = Color(0x33FFFFFF);

// =========================================================================
// CLASSES AUXILIARES ORIGINAIS
// =========================================================================

class DateTextController extends TextEditingController {
  DateTextController({String? text}) : super(text: text);
}

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
      if (i == 2 || i == 4) formattedText += '/';
      formattedText += newText[i];
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}

// =========================================================================
// TELA DE REGISTRO TINTURARIA (MODERNA / PADRÃO EMBALAGEM)
// =========================================================================

class RegistroScreenTinturaria extends StatefulWidget {
  final String conferente;
  const RegistroScreenTinturaria({required this.conferente, super.key});

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

  bool _camposPreenchidos = false;
  DateTime? _data;

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

  // =========================================================================
  // UI PREMIUM HELPERS
  // =========================================================================

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [_kSurface.withOpacity(0.92), _kSurface2.withOpacity(0.92)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.55),
            blurRadius: 25,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _kPrimaryColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorderSoft),
          ),
          child: Icon(icon, color: _kAccentColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: _kTextPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  InputDecoration _getInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: _kTextSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: _kAccentColor,
        fontWeight: FontWeight.w800,
      ),
      prefixIcon: Icon(icon, color: _kTextSecondary, size: 20),
      filled: true,
      fillColor: _kSurface2.withOpacity(0.90),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _kBorderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _kAccentColor, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _kBorderSoft),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
      ),

      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        enabled: false, // sempre bloqueado
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(
          color: _kTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: _getInputDecoration(label, icon),
        validator: (value) =>
            value == null || value.isEmpty ? 'Campo obrigatório' : null,
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [_kSurface.withOpacity(0.9), _kSurface2.withOpacity(0.9)],
        ),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _kAccentColor),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: _kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // FUNÇÕES PRINCIPAIS
  // =========================================================================

  Future<void> _scanQR() async {
    try {
      final qr = await Navigator.push<QrCodeDataTinturaria>(
        context,
        MaterialPageRoute(
          builder: (_) => const QrScannerPage(),
          fullscreenDialog: true,
        ),
      );

      if (qr != null && mounted) {
        setState(() {
          _nomeMaterialController.text = qr.nomeMaterial;
          _larguraCruaController.text = qr.larguraCrua;
          _elasticidadeCruaController.text = qr.elasticidadeCrua;
          _nMaquinaController.text = qr.nMaquina;
          _dataCorteController.text = qr.dataCorte;
          _loteElasticoController.text = qr.loteElastico;
          _camposPreenchidos = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro ao ler QR Code. Tente novamente.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _salvarRegistro() async {
    if (_formKey.currentState!.validate() &&
        _data != null &&
        _camposPreenchidos) {
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

      await enviarRegistroParaAPI(registro);

      _nomeMaterialController.clear();
      _larguraCruaController.clear();
      _elasticidadeCruaController.clear();
      _nMaquinaController.clear();
      _dataCorteController.clear();
      _loteElasticoController.clear();

      setState(() {
        _camposPreenchidos = false;
      });
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Registro salvo com sucesso!'),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao salvar registro: ${response.statusCode}'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro de conexão ao salvar registro.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  // =========================================================================
  // UI BUILD
  // =========================================================================

  Widget _buildFormulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle("Leitura", Icons.qr_code_scanner_rounded),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _scanQR,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text(
                        "LER QR CODE",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _kPrimaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionTitle(
                    "Dados do Material",
                    Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 18),

                  _buildTextField(
                    _nomeMaterialController,
                    'Nome do Material',
                    Icons.texture,
                  ),
                  _buildTextField(
                    _larguraCruaController,
                    'Largura Crua',
                    Icons.straighten,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    _elasticidadeCruaController,
                    'Elasticidade Crua',
                    Icons.compare_arrows,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    _nMaquinaController,
                    'Número da Máquina',
                    Icons.precision_manufacturing_outlined,
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    _dataCorteController,
                    'Data de Corte',
                    Icons.calendar_month_outlined,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      DateTextFormatter(),
                    ],
                  ),
                  _buildTextField(
                    _loteElasticoController,
                    'Lote Elástico',
                    Icons.category_outlined,
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _camposPreenchidos ? _salvarRegistro : null,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text(
                        "SALVAR REGISTRO",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: _kPrimaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kPrimaryColor.withOpacity(
                          0.35,
                        ),
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                Expanded(
                  child: _buildBadge(
                    Icons.person_outline_rounded,
                    "Conferente: ${widget.conferente}",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBadge(
                    Icons.access_time_rounded,
                    "Turno: ${_getTurno()}",
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBottom,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: _buildFormulario()),
      ),
    );
  }
}

// =========================================================================
// SCANNER DE QR CODE (PADRÃO PREMIUM)
// =========================================================================

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _cameraController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;

  QrCodeDataTinturaria? _parseQrCode(String? qrCode) {
    if (qrCode == null || qrCode.isEmpty) return null;

    try {
      final Map<String, dynamic> jsonMap = jsonDecode(qrCode);
      return QrCodeDataTinturaria.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  void _handleQrCodeDetected(QrCodeDataTinturaria qrData) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text('QR Code detectado!'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 1),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) Navigator.of(context).pop(qrData);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double scannerSize = 260.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Escanear QR Code',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: _kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              if (_isProcessing) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? qrString = barcodes.first.rawValue;
                if (qrString != null) {
                  final qrData = _parseQrCode(qrString);
                  if (qrData != null) {
                    _handleQrCodeDetected(qrData);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.error, color: Colors.white),
                            SizedBox(width: 10),
                            Text('QR Code inválido ou incompleto!'),
                          ],
                        ),
                        backgroundColor: Colors.red.shade700,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
            },
          ),

          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.65),
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
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Center(
            child: CustomPaint(
              size: const Size(scannerSize, scannerSize),
              painter: _QrScannerCornersPainter(),
            ),
          ),

          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 46.0),
              child: Text(
                'Posicione o QR Code dentro do quadro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  backgroundColor: Color(0xAA000000),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 18.0),
              child: _TorchButton(controller: _cameraController),
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: _kAccentColor),
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
    setState(() => isTorchOn = !isTorchOn);
    widget.controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
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

class _QrScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kAccentColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.2;

    final cornerLength = size.width / 5;

    canvas.drawLine(const Offset(0, 0), Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, cornerLength), paint);

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
