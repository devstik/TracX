import 'package:tracx/models/qr_code_data.dart';
import 'package:tracx/models/registro.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tracx/services/movimentacao_service.dart';
import '../screens/login_screen.dart';

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

// borda mais visível (antes tava apagada demais)
const Color _kBorderSoft = Color(0x33FFFFFF);

// =========================================================================
// QR SCANNER OVERLAY CORNERS
// =========================================================================
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =========================================================================
// BOTÃO DA LANTERNA
// =========================================================================
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
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: _kBorderSoft),
      ),
      child: IconButton(
        icon: Icon(
          isTorchOn ? Icons.flash_on : Icons.flash_off,
          color: isTorchOn ? _kAccentColor : Colors.white,
          size: 26,
        ),
        onPressed: _toggleTorch,
      ),
    );
  }
}

// =========================================================================
// TELA DO SCANNER
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

  bool _isDetected = false;

  QrCodeData? _parseQrCode(String? qrCode) {
    if (qrCode == null || qrCode.isEmpty) return null;

    try {
      final Map<String, dynamic> jsonMap = jsonDecode(qrCode);
      return QrCodeData.fromJson(jsonMap);
    } catch (e) {
      return null;
    }
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
        backgroundColor: _kBgBottom,
        foregroundColor: _kTextPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Escanear QR Code',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              if (_isDetected) return;

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? qrString = barcodes.first.rawValue;
                if (qrString != null) {
                  final qrData = _parseQrCode(qrString);

                  if (qrData != null) {
                    setState(() => _isDetected = true);
                    Navigator.pop(context, qrData);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR Code inválido ou incompleto!'),
                        backgroundColor: _kPrimaryColor,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              }
            },
          ),

          // Overlay escuro com recorte central
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

          // Cantos do scanner
          Center(
            child: CustomPaint(
              size: const Size(scannerSize, scannerSize),
              painter: _QrScannerCornersPainter(),
            ),
          ),

          // Texto instrução
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.60),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorderSoft),
                ),
                child: const Text(
                  'Posicione o QR Code dentro do quadro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

          // Botão lanterna
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 18.0),
              child: _TorchButton(controller: _cameraController),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// TELA DE REGISTRO (MODERNIZADA)
// =========================================================================
class RegistroScreen extends StatefulWidget {
  final String conferente;
  const RegistroScreen({required this.conferente, super.key});

  @override
  _RegistroScreenState createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ordemController = TextEditingController();
  final _quantidadeController = TextEditingController();
  final _artigoController = TextEditingController();
  final _corController = TextEditingController();
  final _pesoController = TextEditingController();
  final _metrosController = TextEditingController();
  final _dataTingimentoController = TextEditingController();
  final _numCorteController = TextEditingController();
  final _volumeProgController = TextEditingController();
  final _caixaController = TextEditingController();

  String? _localizacaoSelecionada;
  DateTime? _data;

  bool _isSaving = false;
  bool _isManualEntry = false;

  @override
  void initState() {
    super.initState();
    _data = DateTime.now();
    _removerRegistrosAntigos();
    _ordemController.addListener(_updateFormState);
  }

  @override
  void dispose() {
    _ordemController.removeListener(_updateFormState);
    _ordemController.dispose();
    _quantidadeController.dispose();
    _artigoController.dispose();
    _corController.dispose();
    _pesoController.dispose();
    _metrosController.dispose();
    _dataTingimentoController.dispose();
    _numCorteController.dispose();
    _volumeProgController.dispose();
    _caixaController.dispose();
    super.dispose();
  }

  void _updateFormState() {
    setState(() {});
  }

  void _removerRegistrosAntigos() async {
    final box = Hive.box<Registro>('registros');
    final agora = DateTime.now();

    final chavesParaRemover = box.keys.where((key) {
      final registro = box.get(key);
      return registro != null && agora.difference(registro.data).inHours > 1;
    }).toList();

    for (var key in chavesParaRemover) {
      await box.delete(key);
    }
  }

  String getTurno() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 14) return 'A';
    if (hour >= 14 && hour < 22) return 'B';
    return 'C';
  }

  String _safeString(String? value) {
    return (value == null || value.isEmpty) ? '' : value;
  }

  Future<void> _scanQR() async {
    final qr = await Navigator.push<QrCodeData>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (qr != null) {
      double metrosUnitario =
          double.tryParse(qr.metros.toString().replaceAll(',', '.')) ?? 0.0;
      int quantidadeTambores = int.tryParse(qr.numeroTambores.toString()) ?? 0;

      double metrosTotal = metrosUnitario * quantidadeTambores;

      final String metrosFormatado = metrosTotal == 0.0
          ? '0'
          : metrosTotal.toStringAsFixed(3).replaceAll('.', ',');

      final String ordem = qr.ordem == 0 ? '0' : qr.ordem.toString();
      final String peso = qr.peso == 0.0 ? '0' : qr.peso.toStringAsFixed(3);
      final String quantidade = quantidadeTambores.toString();

      final String artigo = _safeString(qr.artigo);
      final String cor = _safeString(qr.cor);
      final String volumeProg = _safeString(qr.volumeProg);
      final String dataTingimento = _safeString(qr.dataTingimento);
      final String numCorte = _safeString(qr.numCorte);

      String caixa = _safeString(qr.caixa);
      if (caixa.isEmpty) caixa = '0';

      HapticFeedback.mediumImpact();

      setState(() {
        _ordemController.text = ordem;
        _artigoController.text = artigo;
        _corController.text = cor;
        _quantidadeController.text = quantidade;
        _pesoController.text = peso;
        _volumeProgController.text = volumeProg;
        _caixaController.text = caixa;
        _metrosController.text = metrosFormatado;
        _dataTingimentoController.text = dataTingimento;
        _numCorteController.text = numCorte;
      });
    }
  }

  void _limparFormulario() {
    _ordemController.clear();
    _quantidadeController.clear();
    _artigoController.clear();
    _corController.clear();
    _pesoController.clear();
    _metrosController.clear();
    _dataTingimentoController.clear();
    _numCorteController.clear();
    _volumeProgController.clear();
    _caixaController.clear();
    _localizacaoSelecionada = null;
    setState(() {});
  }

  int _parseIntFromController(TextEditingController controller) {
    final String text = controller.text.replaceAll(',', '.');
    final double? doubleValue = double.tryParse(text);
    return doubleValue?.toInt() ?? 0;
  }

  void _showSuccessFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Registro salvo com sucesso!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _salvarRegistro() async {
    final bool isFormReady = _ordemController.text.isNotEmpty;
    if (!isFormReady) return;

    if (_formKey.currentState!.validate() && _data != null && !_isSaving) {
      setState(() => _isSaving = true);

      final dataCadastro = DateTime.now().toLocal().toIso8601String().substring(
        0,
        10,
      );

      try {
        final box = Hive.box<Registro>('registros');

        final pesoStr = _pesoController.text;
        final metrosStr = _metrosController.text;

        final volumeStrTratada = _volumeProgController.text.replaceAll(
          ',',
          '.',
        );
        final volumeDouble = double.tryParse(volumeStrTratada) ?? 0.0;

        final String caixaValue = _caixaController.text.isEmpty
            ? '0.00'
            : _caixaController.text;

        final int ordemProducao = _parseIntFromController(_ordemController);
        final int quantidade = _parseIntFromController(_quantidadeController);

        final registro = Registro(
          data: _data!,
          ordemProducao: ordemProducao,
          quantidade: quantidade,
          artigo: _artigoController.text,
          cor: _corController.text,
          peso: pesoStr.isEmpty
              ? 0.0
              : double.parse(pesoStr.replaceAll(',', '.')),
          conferente: widget.conferente,
          turno: getTurno(),
          metros: metrosStr.isEmpty
              ? 0.0
              : double.parse(metrosStr.replaceAll(',', '.')),
          dataTingimento: _dataTingimentoController.text,
          numCorte: _numCorteController.text,
          volumeProg: volumeDouble,
          localizacao: _localizacaoSelecionada!,
          caixa: caixaValue,
        );

        await box.add(registro);

        _showSuccessFeedback();
        enviarRegistroParaAPI(registro, dataCadastro);
        _limparFormulario();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao salvar registro!'),
            backgroundColor: _kPrimaryColor,
          ),
        );
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> enviarRegistroParaAPI(
    Registro registro,
    String dataCadastro,
  ) async {
    final headers = {'Content-Type': 'application/json'};
    final now = DateTime.now().toLocal().toIso8601String();

    final bodyEmbalagem = jsonEncode({
      'Data': registro.data.toLocal().toIso8601String().substring(0, 10),
      'NrOrdem': registro.ordemProducao,
      'Quantidade': registro.quantidade,
      'Artigo': registro.artigo,
      'Cor': registro.cor,
      'Peso': registro.peso,
      'Conferente': registro.conferente,
      'Turno': registro.turno,
      'Metros': registro.metros,
      'DataTingimento': registro.dataTingimento,
      'NumCorte': registro.numCorte,
      'VolumeProg': registro.volumeProg,
      'DataCadastro': dataCadastro,
      'Caixa': registro.caixa,
    });

    final bodyMovimentacao = jsonEncode({
      'NrOrdem': registro.ordemProducao,
      'Artigo': registro.artigo,
      'Cor': registro.cor,
      'Quantidade': registro.quantidade,
      'Peso': registro.peso,
      'Conferente': registro.conferente,
      'Turno': registro.turno,
      'Metros': registro.metros,
      'NumCorte': registro.numCorte,
      'VolumeProg': registro.volumeProg,
      'Localizacao': registro.localizacao,
      'DataEntrada': now,
      'DataSaida': null,
      'Caixa': registro.caixa,
    });

    try {
      await http
          .post(
            Uri.parse('http://168.190.90.2:5000/consulta/embalagem'),
            headers: headers,
            body: bodyEmbalagem,
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {}

    try {
      await http
          .post(
            Uri.parse('http://168.190.90.2:5000/consulta/movimentacao'),
            headers: headers,
            body: bodyMovimentacao,
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {}
  }

  // =========================================================================
  // UI HELPERS (AJUSTADOS PARA CONTRASTE)
  // =========================================================================
  Widget _buildGlassCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kPrimaryColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorderSoft),
            ),
            child: Icon(icon, color: _kAccentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _getInputDecoration(
    String label,
    IconData icon, {
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: Icon(
        icon,
        color: enabled ? _kAccentColor : _kTextSecondary.withOpacity(0.6),
      ),

      filled: true,
      fillColor: enabled
          ? _kSurface2.withOpacity(0.95)
          : _kSurface2.withOpacity(0.55),

      enabled: enabled,

      labelStyle: TextStyle(
        color: enabled ? _kTextSecondary : _kTextSecondary.withOpacity(0.6),
        fontWeight: FontWeight.w700,
      ),

      hintStyle: TextStyle(
        color: _kTextSecondary.withOpacity(0.55),
        fontWeight: FontWeight.w600,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBorderSoft, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kBorderSoft, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kPrimaryColor, width: 2),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),

      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumeric = false,
    bool isRequired = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: _isManualEntry,
        cursorColor: _kAccentColor,
        style: const TextStyle(
          color: _kTextPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        decoration: _getInputDecoration(label, icon, enabled: _isManualEntry),
        keyboardType: isNumeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: isNumeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+[,.]?\d{0,3}'))]
            : [],
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return 'O campo $label é obrigatório.';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildLocalizacaoDropdown() {
    final List<String> localizacoes = const ['Mesas', 'Imatecs'];
    final bool isEnabled = _ordemController.text.isNotEmpty;

    return DropdownButtonFormField<String>(
      value: _localizacaoSelecionada,
      dropdownColor: _kSurface,
      decoration: _getInputDecoration(
        'Localização',
        Icons.location_on,
        enabled: isEnabled,
      ),
      isExpanded: true,
      style: const TextStyle(color: _kTextPrimary, fontWeight: FontWeight.w800),
      items: localizacoes.map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(value, style: const TextStyle(color: _kTextPrimary)),
        );
      }).toList(),
      onChanged: isEnabled
          ? (String? newValue) {
              setState(() {
                _localizacaoSelecionada = newValue;
              });
            }
          : null,
      validator: (value) {
        if (!isEnabled) return null;
        return value == null || value.isEmpty
            ? 'Selecione a Localização'
            : null;
      },
    );
  }

  Widget _buildQrButtons() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isManualEntry ? null : _scanQR,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Ler QR Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade700,
                    disabledForegroundColor: Colors.grey.shade300,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isManualEntry = !_isManualEntry;
                      if (!_isManualEntry) _limparFormulario();
                    });
                    HapticFeedback.lightImpact();
                  },
                  icon: Icon(_isManualEntry ? Icons.close : Icons.edit),
                  label: Text(_isManualEntry ? 'Cancelar' : 'Manual'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isManualEntry
                        ? Colors.orange.shade700
                        : _kAccentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _isManualEntry
                ? 'Modo Manual ativado: edite os campos.'
                : 'Use QR Code para preenchimento automático.',
            style: TextStyle(
              color: _kTextSecondary.withOpacity(0.9),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterBadges() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: _kAccentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.conferente,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 22, width: 1, color: _kBorderSoft),
          const SizedBox(width: 10),
          Row(
            children: [
              const Icon(Icons.access_time, size: 18, color: _kAccentColor),
              const SizedBox(width: 8),
              Text(
                'Turno ${getTurno()}',
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final bool isFormReady = _artigoController.text.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving || !isFormReady ? null : _salvarRegistro,
        icon: _isSaving
            ? Container(
                width: 22,
                height: 22,
                padding: const EdgeInsets.all(2.0),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Salvando...' : 'Salvar Registro',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade700,
          disabledForegroundColor: Colors.grey.shade300,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentificationSection() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Identificação', Icons.info_outline),
          _buildTextField(
            _ordemController,
            'Ordem de Produção',
            Icons.assignment,
            isNumeric: true,
            isRequired: false,
          ),
          _buildTextField(_artigoController, 'Artigo', Icons.qr_code_2),
          _buildTextField(_corController, 'Cor', Icons.color_lens),
          _buildTextField(_caixaController, 'Caixa', Icons.inventory),
        ],
      ),
    );
  }

  Widget _buildMeasurementsSection() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Medidas e Quantidades', Icons.straighten),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _quantidadeController,
                  'Tambor',
                  Icons.format_list_numbered,
                  isNumeric: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  _volumeProgController,
                  'Volume',
                  Icons.view_module,
                  isNumeric: true,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  _pesoController,
                  'Peso',
                  Icons.line_weight,
                  isNumeric: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  _metrosController,
                  'Metros',
                  Icons.square_foot,
                  isNumeric: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Detalhes de Produção', Icons.description),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_numCorteController, 'Corte', Icons.cut),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  _dataTingimentoController,
                  'Tingimento',
                  Icons.calendar_today,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BUILD
  // =========================================================================
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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildQrButtons(),
                  _buildIdentificationSection(),
                  _buildMeasurementsSection(),
                  _buildDetailsSection(),
                  _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionTitle('Finalização', Icons.check_circle),
                        _buildLocalizacaoDropdown(),
                        const SizedBox(height: 14),
                        _buildSaveButton(),
                      ],
                    ),
                  ),
                  _buildFooterBadges(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
