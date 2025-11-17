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
// import '../screens/ListaRegistrosScreen.dart';

// =========================================================================
// CORES E CONSTANTES
// =========================================================================

const Color _kPrimaryColor = Color(
  0xFFCD1818,
); // Vermelho Principal (App Bar, Ações Principais)
const Color _kAccentColor = Color(0xFF3A59D1); // Azul (Ícones, Foco, QR Button)
const Color _kBackgroundColor = Color(0xFFF0F2F5); // Fundo Leve, moderno
const Color _kInputFillColor = Colors.white; // Cor de preenchimento do input

// =========================================================================
// TELA DE REGISTRO
// =========================================================================

class RegistroScreen extends StatefulWidget {
  final String conferente;
  const RegistroScreen({required this.conferente, super.key});

  @override
  // ignore: library_private_types_in_public_api
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
  final _caixaController = TextEditingController(); // Controller para Caixa

  String? _localizacaoSelecionada;

  DateTime? _data;
  // 🎯 REMOVIDO: A variável _formBloqueado não é mais necessária, pois os campos de texto serão bloqueados por padrão.
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _data = DateTime.now();
    _removerRegistrosAntigos();
    // 💡 NOVO: Adicionar listener para reagir a mudanças e controlar o botão
    _ordemController.addListener(_updateFormState);
  }

  @override
  void dispose() {
    _ordemController.removeListener(_updateFormState); // Remover o listener
    _ordemController.dispose();
    _quantidadeController.dispose();
    _artigoController.dispose();
    _corController.dispose();
    _pesoController.dispose();
    _metrosController.dispose();
    _dataTingimentoController.dispose();
    _numCorteController.dispose();
    _volumeProgController.dispose();
    _caixaController.dispose(); // Dispose do Controller
    super.dispose();
  }

  // 💡 NOVO: Função para atualizar o estado do formulário/botão
  void _updateFormState() {
    // Chama setState para reconstruir o widget e reavaliar a condição do botão/dropdown
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
    if (hour >= 6 && hour <= 14) return 'A';
    if (hour > 14 && hour <= 22) return 'B';
    return 'C';
  }

  Future<void> _scanQR() async {
    final qr = await Navigator.push<QrCodeData>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

    if (qr != null) {
      setState(() {
        _ordemController.text = qr.ordem.toString();
        _artigoController.text = qr.artigo;
        _corController.text = qr.cor;
        _quantidadeController.text = qr.numeroTambores.toString();
        _pesoController.text = qr.peso.toStringAsFixed(3);
        _volumeProgController.text = qr.volumeProg;
        _caixaController.text = qr.caixa; // Mapeamento do valor da Caixa
        _metrosController.text = qr.metros.toStringAsFixed(3);
        _dataTingimentoController.text = qr.dataTingimento;
        _numCorteController.text = qr.numCorte;
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
    _caixaController.clear(); // Limpar o Controller Caixa
    _localizacaoSelecionada = null;
    setState(() {});
  }

  void _showSuccessFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Registro salvo com sucesso!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _salvarRegistro() async {
    // 🎯 Condição para habilitar o Salvar, baseada no preenchimento da OP
    final bool isFormReady = _ordemController.text.isNotEmpty;

    if (!isFormReady) {
      return;
    }

    if (_formKey.currentState!.validate() && _data != null && !_isSaving) {
      setState(() {
        _isSaving = true;
      });

      // Captura o momento exato do cadastro e formata para enviar SOMENTE A DATA
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

        final registro = Registro(
          data: _data!,
          ordemProducao: int.parse(_ordemController.text),
          quantidade: int.parse(_quantidadeController.text),
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
          volumeProg: volumeDouble, // Valor Double Corrigido
          localizacao: _localizacaoSelecionada!,
          caixa: _caixaController.text, // Parâmetro 'caixa' usado
        );

        await box.add(registro);

        _showSuccessFeedback();

        enviarRegistroParaAPI(registro, dataCadastro);

        _limparFormulario();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar registro: $e'),
            backgroundColor: _kPrimaryColor,
          ),
        );
      } finally {
        setState(() {
          _isSaving = false;
        });
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
      // NOVO CAMPO DE MONITORAMENTO (Apenas Data)
      'DataCadastro': dataCadastro,
      'Caixa': registro.caixa, // Adicionado ao body Embalagem
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
      'Caixa': registro.caixa, // Adicionado ao body Movimentacao
    });

    final urlEmbalagem = Uri.parse(
      'http://168.190.90.2:5000/consulta/embalagem',
    );
    try {
      await http
          .post(urlEmbalagem, headers: headers, body: bodyEmbalagem)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // Log de erro
    }

    final urlMovimentacao = Uri.parse(
      'http://168.190.90.2:5000/consulta/movimentacao',
    );
    try {
      await http
          .post(urlMovimentacao, headers: headers, body: bodyMovimentacao)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // Log de erro
    }
  }

  // WIDGET: DROPWDOWN DE LOCALIZAÇÃO (Estilo M3 Aprimorado)
  Widget _buildLocalizacaoDropdown() {
    final List<String> localizacoes = const ['Mesas', 'Imatecs'];
    // 🎯 Condição para habilitar/desabilitar o dropdown
    final bool isEnabled = _ordemController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: _localizacaoSelecionada,
        // 💡 DECORAÇÃO: Muda a cor se estiver desabilitado (OP vazia)
        decoration: _getInputDecoration(
          'Localização',
          Icons.location_on,
          enabled: isEnabled,
        ),
        isExpanded: true,
        items: localizacoes.map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          );
        }).toList(),
        // 🎯 O Dropdown é desabilitado se a OP estiver vazia
        onChanged: isEnabled
            ? (String? newValue) {
                setState(() {
                  _localizacaoSelecionada = newValue;
                });
              }
            : null,
        validator: (value) {
          if (!isEnabled) return null; // Não valida se estiver desabilitado
          return value == null || value.isEmpty
              ? 'Selecione a Localização'
              : null;
        },
      ),
    );
  }

  // Função centralizada para estilizar a decoração dos inputs
  InputDecoration _getInputDecoration(
    String label,
    IconData icon, {
    bool enabled = true, // Controla o visual
  }) {
    return InputDecoration(
      labelText: label,
      hintText: '$label',
      prefixIcon: Icon(
        icon,
        color: enabled ? _kPrimaryColor : Colors.grey.shade400,
      ),
      filled: true,
      // Fundo cinza quando desabilitado (bloqueado)
      fillColor: enabled ? _kInputFillColor : Colors.grey.shade200,
      enabled: enabled, // Controla se a label flutua etc.
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
      // Borda para estado disabled (campo bloqueado)
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
    );
  }

  // WIDGET: CAMPO DE TEXTO
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumeric = false,
    bool isRequired = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
      child: TextFormField(
        controller: controller,
        enabled: false,
        decoration: _getInputDecoration(label, icon, enabled: false),

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

  // WIDGET: BOTÃO DE QR CODE
  Widget _buildQrButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 20.0),
      child: ElevatedButton.icon(
        onPressed: _scanQR,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Ler QR Code', style: TextStyle(fontSize: 18)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimaryColor, // Cor de destaque para o botão QR
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 5,
        ),
      ),
    );
  }

  // WIDGET: TÍTULO DA SEÇÃO
  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
      child: Row(
        children: [
          Icon(icon, color: _kPrimaryColor, size: 22),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // WIDGET: SEÇÃO DE IDENTIFICAÇÃO (OP, Artigo, Cor, Caixa)
  Widget _buildIdentificationSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Dados de Identificação', Icons.info_outline),
            _buildTextField(
              _ordemController,
              'Ordem de Produção',
              Icons.assignment,
              isNumeric: true,
            ),
            _buildTextField(
              _artigoController,
              'Artigo',
              Icons.fiber_manual_record,
            ),
            _buildTextField(_corController, 'Cor', Icons.color_lens),
            // CAMPO DA CAIXA
            _buildTextField(_caixaController, 'Caixa', Icons.inventory),
          ],
        ),
      ),
    );
  }

  // WIDGET: SEÇÃO DE MEDIDAS E QUANTIDADES
  Widget _buildMeasurementsSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Medidas e Quantidades', Icons.straighten),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _quantidadeController,
                    'Quantidade (Un)',
                    Icons.format_list_numbered,
                    isNumeric: true,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildTextField(
                    _volumeProgController,
                    'Volume Prog.',
                    Icons.view_module,
                    isNumeric: true,
                    isRequired: true,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _pesoController,
                    'Peso (Kg)',
                    Icons.line_weight,
                    isNumeric: true,
                  ),
                ),
                const SizedBox(width: 15),
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
      ),
    );
  }

  // WIDGET: SEÇÃO DE DETALHES DE PRODUÇÃO
  Widget _buildDetailsSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Detalhes de Produção', Icons.description),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _numCorteController,
                    'Nº do Corte',
                    Icons.cut,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildTextField(
                    _dataTingimentoController,
                    'Data Tingimento',
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // WIDGET: SEÇÃO DE LOCALIZAÇÃO E AÇÃO
  Widget _buildLocationAndActionSection() {
    final bool isFormReady = _ordemController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Dropdown de Localização
        _buildLocalizacaoDropdown(),
        const SizedBox(height: 20),
        // Botão de Salvar
        ElevatedButton.icon(
          // 🎯 O botão é desativado se estiver salvando OU se o form não estiver pronto (Ordem vazia).
          onPressed: _isSaving || !isFormReady ? null : _salvarRegistro,
          icon: _isSaving
              ? Container(
                  width: 24,
                  height: 24,
                  padding: const EdgeInsets.all(2.0),
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            _isSaving ? 'Salvando...' : 'Salvar Registro',
            style: const TextStyle(fontSize: 18),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kPrimaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15),
            elevation: 5,
            // 💡 Estilo visual para desativado
            disabledBackgroundColor: Colors.grey.shade400,
            disabledForegroundColor: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  // WIDGET: INFORMAÇÕES DE RODAPÉ (Conferente e Turno)
  Widget _buildFooterInfo() {
    return Padding(
      padding: const EdgeInsets.only(top: 10.0, bottom: 20.0),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _kInputFillColor,
          borderRadius: BorderRadius.circular(15),
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
                  'Turno: ${getTurno()}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Seção de QR Code
              _buildQrButton(),

              // Seções Organizadas
              _buildIdentificationSection(),
              _buildMeasurementsSection(),
              _buildDetailsSection(),
              _buildLocationAndActionSection(),

              // Informações de Rodapé
              _buildFooterInfo(),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// WIDGET: SCANNER DE QR CODE (MELHORADO, ORGANIZADO E COM LANTERNA)
// =========================================================================

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  // 1. Controller da câmera para controle de funções (e.g., lanterna)
  final MobileScannerController _cameraController = MobileScannerController(
    // 💡 OTIMIZAÇÃO: Limita o scanner a procurar apenas por códigos QR
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  // Função para parsear a string do QR Code e retornar o objeto QrCodeData
  QrCodeData? _parseQrCode(String? qrCode) {
    if (qrCode == null || qrCode.isEmpty) {
      return null;
    }

    try {
      // 1. Tenta decodificar a string do QR Code como um objeto JSON.
      final Map<String, dynamic> jsonMap = jsonDecode(qrCode);

      // 2. Usa o construtor de fábrica QrCodeData.fromJson para converter o JSON.
      final qrData = QrCodeData.fromJson(jsonMap);

      // 3. Validação de Negócio: Se a Ordem de Produção for 0, o código é inválido.
      if (qrData.ordem == 0) {
        return null;
      }

      // Se tudo estiver OK, o objeto QrCodeData é retornado
      return qrData;
    } catch (e) {
      // Se ocorrer um erro (não é um JSON válido, etc.), retorna null.
      return null;
    }
  }

  @override
  void dispose() {
    // ⚠️ Importante: Descartar o controller da câmera
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tamanho fixo para a área de escaneamento
    const double scannerSize = 250.0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Escanear QR Code'),
        backgroundColor: _kPrimaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. Scanner de Câmera (Fundo)
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final String? qrString = barcodes.first.rawValue;
                if (qrString != null) {
                  final qrData = _parseQrCode(qrString);
                  if (qrData != null) {
                    Navigator.pop(context, qrData);
                  } else {
                    // Feedback de QR Code inválido
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

          // 2. Overlay de Fundo Escuro com Recorte (Hole Punch Effect)
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
                      color: Colors.red, // Cor de placeholder
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. Pintura dos Cantos (Visual Aprimorado)
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

          // 5. Botão de Lanterna (Controle)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: _TorchButton(controller: _cameraController),
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
    // O comando real para ligar/desligar a lanterna
    widget.controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54, // Fundo semitransparente
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: IconButton(
        icon: Icon(
          isTorchOn ? Icons.flash_on : Icons.flash_off,
          color: isTorchOn
              ? _kAccentColor
              : Colors.white, // Cor de foco no estado "ligado"
          size: 28,
        ),
        onPressed: _toggleTorch,
        tooltip: isTorchOn ? 'Desligar Lanterna' : 'Ligar Lanterna',
      ),
    );
  }
}

// WIDGET: PINTURA DOS CANTOS (Mais limpo e usando a cor de destaque)
class _QrScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color =
          _kAccentColor // Cor de destaque
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
