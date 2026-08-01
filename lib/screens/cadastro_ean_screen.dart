import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ean_service.dart';
import '../services/etiquetas_service.dart';

class CadastroEanScreen extends StatefulWidget {
  const CadastroEanScreen({super.key});

  @override
  State<CadastroEanScreen> createState() => _CadastroEanScreenState();
}

class _CadastroEanScreenState extends State<CadastroEanScreen> {
  static const _bg = Color(0xFF020617);
  static const _surface = Color(0xFF172033);
  static const _field = Color(0xFF0F172A);
  static const _border = Color(0xFF334155);
  static const _gold = Color(0xFFD8B840);
  static const _text = Color(0xFFF8FAFC);
  static const _muted = Color(0xFF94A3B8);
  static const _success = Color(0xFF16A34A);
  static const _error = Color.fromARGB(255, 143, 7, 7);

  final _buscaController = TextEditingController();
  final _cdObjController = TextEditingController();
  final _nmObjController = TextEditingController();

  List<EanCadastro> _registros = [];
  ProximoEan? _proximo;
  bool _consultando = false;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarInicial();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _cdObjController.dispose();
    _nmObjController.dispose();
    super.dispose();
  }

  Future<void> _carregarInicial() async {
    setState(() {
      _consultando = true;
      _erro = null;
    });
    try {
      final results = await Future.wait([
        EanCadastroService.listar(),
        EanCadastroService.obterProximo(),
      ]);
      if (!mounted) return;
      setState(() {
        _registros = results[0] as List<EanCadastro>;
        _proximo = results[1] as ProximoEan?;
        _consultando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _limparErro(e);
        _consultando = false;
      });
    }
  }

  Future<void> _pesquisar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _consultando = true;
      _erro = null;
    });
    try {
      final registros = await EanCadastroService.pesquisar(
        _buscaController.text,
      );
      if (!mounted) return;
      setState(() {
        _registros = registros;
        _consultando = false;
      });
      if (registros.isEmpty) {
        _mostrarMensagem('Nenhum EAN encontrado para a pesquisa.', erro: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _limparErro(e);
        _consultando = false;
      });
    }
  }

  Future<void> _cadastrar() async {
    FocusScope.of(context).unfocus();
    final cdObj = int.tryParse(_cdObjController.text.trim()) ?? 0;
    final nmObj = _nmObjController.text.trim();

    if (cdObj <= 0) {
      _mostrarMensagem('Informe o código do artigo.', erro: true);
      return;
    }
    if (nmObj.isEmpty) {
      _mostrarMensagem('Informe o nome do artigo.', erro: true);
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final criado = await EanCadastroService.cadastrar(
        cdObj: cdObj,
        nmObj: nmObj,
      );
      final proximo = await EanCadastroService.obterProximo();
      if (!mounted) return;
      setState(() {
        _registros = [criado, ..._registros];
        _proximo = proximo;
        _salvando = false;
        _cdObjController.clear();
        _nmObjController.clear();
      });
      _mostrarMensagem(
        criado.nrCao.isEmpty
            ? 'EAN-13 cadastrado com sucesso.'
            : 'EAN-13 ${criado.nrCao} cadastrado com sucesso.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _limparErro(e);
        _salvando = false;
      });
    }
  }

  Future<void> _editar(EanCadastro item) async {
    final result = await showDialog<_EanEditResult>(
      context: context,
      builder: (context) => _EditarEanDialog(item: item),
    );
    if (result == null) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await EanCadastroService.atualizar(
        ean: item.nrCao,
        cdObj: result.cdObj,
        nmObj: result.nmObj,
      );
      if (!mounted) return;
      setState(() {
        _registros = _registros
            .map(
              (registro) => registro.nrCao == item.nrCao
                  ? EanCadastro(
                      id: registro.id,
                      cdObj: result.cdObj,
                      nmObj: result.nmObj,
                      nrCao: registro.nrCao,
                    )
                  : registro,
            )
            .toList();
        _salvando = false;
      });
      _mostrarMensagem('Registro atualizado com sucesso.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _limparErro(e);
        _salvando = false;
      });
    }
  }

  Future<void> _excluir(EanCadastro item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir EAN-13?'),
        content: Text(
          'Deseja excluir o EAN ${item.nrCao} do artigo ${item.nmObj}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await EanCadastroService.excluir(item.nrCao);
      final proximo = await EanCadastroService.obterProximo();
      if (!mounted) return;
      setState(() {
        _registros = _registros
            .where((registro) => registro.nrCao != item.nrCao)
            .toList();
        _proximo = proximo;
        _salvando = false;
      });
      _mostrarMensagem('Registro excluído com sucesso.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = _limparErro(e);
        _salvando = false;
      });
    }
  }

  void _selecionarArtigo(Map<String, dynamic> artigo) {
    final cdObj = _toInt(artigo['CdObj']);
    final nmObj = (artigo['NmObj'] ?? '').toString().trim();
    setState(() {
      _cdObjController.text = cdObj > 0 ? cdObj.toString() : '';
      _nmObjController.text = nmObj;
    });
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? _error : _success,
      ),
    );
  }

  String _limparErro(Object e) {
    return e.toString().replaceFirst('Exception: ', '');
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Cadastro de EAN',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _consultando || _salvando ? null : _carregarInicial,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregarInicial,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _buildCadastroCard(),
            const SizedBox(height: 14),
            _buildConsultaCard(),
            const SizedBox(height: 14),
            if (_erro != null) ...[
              _buildError(_erro!),
              const SizedBox(height: 12),
            ],
            if (_consultando)
              const _LoadingCard()
            else if (_registros.isEmpty)
              const _EmptyCard()
            else
              ..._registros.map(_buildEanCard),
          ],
        ),
      ),
    );
  }

  Widget _buildCadastroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.add_box_outlined, color: _gold),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cadastrar novo EAN-13',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildProximoEan(),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final artigoField = _ArtigoAutocompleteField(
                controller: _nmObjController,
                label: 'Artigo',
                hint: 'Digite o nome ou código do artigo',
                onSelected: _selecionarArtigo,
                onTyping: () => setState(() => _cdObjController.clear()),
              );
              final codigoField = _textField(
                controller: _cdObjController,
                label: 'Código do artigo',
                hint: 'Ex: 98182',
                icon: Icons.qr_code_2_rounded,
                numeric: true,
              );
              final saveButton = SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _salvando ? null : _cadastrar,
                  icon: _salvando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _salvando ? 'Salvando' : 'Cadastrar EAN',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  children: [
                    artigoField,
                    const SizedBox(height: 10),
                    codigoField,
                    const SizedBox(height: 12),
                    saveButton,
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: artigoField),
                      const SizedBox(width: 10),
                      Expanded(child: codigoField),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(width: 190, child: saveButton),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProximoEan() {
    final ultimo = _proximo?.ultimoEan;
    final proximo = _proximo?.proximoEan;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _InfoPill(
            icon: Icons.history_rounded,
            label: 'Último EAN',
            value: (ultimo ?? '').isEmpty ? '-' : ultimo!,
          ),
          _InfoPill(
            icon: Icons.auto_awesome_rounded,
            label: 'Próximo EAN',
            value: (proximo ?? '').isEmpty ? 'Gerado ao cadastrar' : proximo!,
            accent: _gold,
          ),
        ],
      ),
    );
  }

  Widget _buildConsultaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.manage_search_rounded, color: _gold),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Consultar EANs cadastrados',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 680;
              final field = TextField(
                controller: _buscaController,
                style: const TextStyle(
                  color: _text,
                  fontWeight: FontWeight.w800,
                ),
                onSubmitted: (_) => _pesquisar(),
                decoration: _decoration(
                  'Pesquisar',
                  Icons.search_rounded,
                ).copyWith(
                  hintText: 'Nome do artigo, código ou EAN',
                  suffixIcon: _buscaController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar pesquisa',
                          onPressed: () {
                            _buscaController.clear();
                            _carregarInicial();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              );
              final button = SizedBox(
                height: 54,
                width: narrow ? double.infinity : 150,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _consultando ? null : _pesquisar,
                  icon: _consultando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    _consultando ? 'Consultando' : 'Consultar',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  children: [
                    field,
                    const SizedBox(height: 10),
                    button,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  button,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEanCard(EanCadastro item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final header = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: 0.45)),
                ),
                child: const Icon(Icons.barcode_reader, color: _gold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nmObj.isEmpty ? 'Artigo sem descrição' : item.nmObj,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Código ${item.cdObj}',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final eanBox = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.confirmation_number_outlined, color: _gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.nrCao.isEmpty ? '-' : item.nrCao,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Copiar EAN',
                onPressed: item.nrCao.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: item.nrCao));
                        _mostrarMensagem('EAN copiado.');
                      },
                icon: const Icon(Icons.copy_rounded),
                color: _muted,
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: _salvando ? null : () => _editar(item),
                icon: const Icon(Icons.edit_rounded),
                color: _gold,
              ),
              IconButton(
                tooltip: 'Excluir',
                onPressed: _salvando ? null : () => _excluir(item),
                icon: const Icon(Icons.delete_outline_rounded),
                color: _error,
              ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                eanBox,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              SizedBox(width: 230, child: eanBox),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _error.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFEE2E2),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
          : null,
      style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
      decoration: _decoration(label, icon).copyWith(hintText: hint),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _gold),
      labelStyle: const TextStyle(color: Colors.white60),
      hintStyle: const TextStyle(color: Colors.white30),
      filled: true,
      fillColor: _field,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
    );
  }
}

class _ArtigoAutocompleteField extends StatefulWidget {
  const _ArtigoAutocompleteField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onSelected,
    required this.onTyping,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final VoidCallback onTyping;

  @override
  State<_ArtigoAutocompleteField> createState() => _ArtigoAutocompleteFieldState();
}

class _ArtigoAutocompleteFieldState extends State<_ArtigoAutocompleteField> {
  static const _field = Color(0xFF0F172A);
  static const _border = Color(0xFF334155);
  static const _gold = Color(0xFFD8B840);
  static const _text = Color(0xFFF8FAFC);

  Timer? _debounce;
  bool _loading = false;
  bool _settingText = false;
  List<Map<String, dynamic>> _opcoes = [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _buscar(String value) {
    if (_settingText) return;
    widget.onTyping();
    _debounce?.cancel();
    final termo = value.trim();
    if (termo.length < 2) {
      setState(() => _opcoes = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final data = await EtiquetasService.buscarArtigosPorNome(termo);
        if (!mounted) return;
        setState(() {
          _opcoes = data.take(8).toList();
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _opcoes = [];
          _loading = false;
        });
      }
    });
  }

  void _selecionar(Map<String, dynamic> artigo) {
    final nome = (artigo['NmObj'] ?? '').toString().trim();
    _settingText = true;
    widget.controller.text = nome;
    _settingText = false;
    widget.onSelected(artigo);
    setState(() => _opcoes = []);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _buscar,
          style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded, color: _gold),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: _field,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _gold, width: 1.5),
            ),
          ),
        ),
        if (_opcoes.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 230),
            decoration: BoxDecoration(
              color: _field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _opcoes.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF1E293B)),
              itemBuilder: (context, index) {
                final item = _opcoes[index];
                final cdObj = item['CdObj']?.toString() ?? '';
                final nmObj = (item['NmObj'] ?? '').toString().trim();
                return ListTile(
                  dense: true,
                  onTap: () => _selecionar(item),
                  title: Text(
                    nmObj.isEmpty ? 'Artigo sem descrição' : nmObj,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    'Código $cdObj',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _EditarEanDialog extends StatefulWidget {
  const _EditarEanDialog({required this.item});

  final EanCadastro item;

  @override
  State<_EditarEanDialog> createState() => _EditarEanDialogState();
}

class _EditarEanDialogState extends State<_EditarEanDialog> {
  late final TextEditingController _cdObjController;
  late final TextEditingController _nmObjController;

  @override
  void initState() {
    super.initState();
    _cdObjController = TextEditingController(text: widget.item.cdObj.toString());
    _nmObjController = TextEditingController(text: widget.item.nmObj);
  }

  @override
  void dispose() {
    _cdObjController.dispose();
    _nmObjController.dispose();
    super.dispose();
  }

  void _salvar() {
    final cdObj = int.tryParse(_cdObjController.text.trim()) ?? 0;
    final nmObj = _nmObjController.text.trim();
    if (cdObj <= 0 || nmObj.isEmpty) return;
    Navigator.of(context).pop(_EanEditResult(cdObj: cdObj, nmObj: nmObj));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar cadastro'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _cdObjController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Código do artigo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nmObjController,
              decoration: const InputDecoration(
                labelText: 'Nome do artigo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'EAN: ${widget.item.nrCao}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _EanEditResult {
  const _EanEditResult({required this.cdObj, required this.nmObj});

  final int cdObj;
  final String nmObj;
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    this.accent = const Color(0xFF38BDF8),
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1224),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: const Column(
        children: [
          Icon(Icons.barcode_reader, color: Color(0xFFD8B840), size: 36),
          SizedBox(height: 10),
          Text(
            'Nenhum EAN encontrado.',
            style: TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Pesquise por artigo, código ou EAN para consultar os cadastros.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
