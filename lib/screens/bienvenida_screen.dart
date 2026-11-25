import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/gemini_service.dart';
import '../services/settings_service.dart';

/// Guía de la primera vez: qué hace la app, conectar Gemini, datos del
/// titular y consejos. Si [alTerminar] es null, al terminar vuelve atrás.
class BienvenidaScreen extends StatefulWidget {
  final VoidCallback? alTerminar;
  const BienvenidaScreen({super.key, this.alTerminar});

  @override
  State<BienvenidaScreen> createState() => _BienvenidaScreenState();
}

class _BienvenidaScreenState extends State<BienvenidaScreen> {
  static const _urlApiKey = 'https://aistudio.google.com/apikey';
  static const _paginas = 4;

  final _pagina = PageController();
  final _keyCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  int _actual = 0;
  bool _probando = false;
  String? _resultadoPrueba;
  bool _pruebaOk = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final s = SettingsService.instance;
    _keyCtrl.text = await s.getApiKey();
    _nombreCtrl.text = await s.getNombreTitular();
    _rucCtrl.text = await s.getRucTitular();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pagina.dispose();
    _keyCtrl.dispose();
    _nombreCtrl.dispose();
    _rucCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirAiStudio() async {
    final ok = await launchUrl(Uri.parse(_urlApiKey),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo abrir el navegador. Entrá a aistudio.google.com/apikey')),
      );
    }
  }

  Future<void> _probar() async {
    setState(() {
      _probando = true;
      _resultadoPrueba = null;
    });
    try {
      final model = await SettingsService.instance.getModel();
      await GeminiService.instance
          .probarConexion(apiKey: _keyCtrl.text, model: model);
      await SettingsService.instance.setApiKey(_keyCtrl.text);
      _pruebaOk = true;
      _resultadoPrueba = '¡Listo! Gemini está conectado.';
    } catch (e) {
      _pruebaOk = false;
      _resultadoPrueba = e.toString();
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  Future<void> _guardarYAvanzar() async {
    final s = SettingsService.instance;
    if (_actual == 1 && _keyCtrl.text.trim().isNotEmpty) {
      await s.setApiKey(_keyCtrl.text);
    }
    if (_actual == 2) {
      await s.setNombreTitular(_nombreCtrl.text);
      await s.setRucTitular(_rucCtrl.text);
    }
    if (!mounted) return;
    if (_actual < _paginas - 1) {
      FocusScope.of(context).unfocus();
      _pagina.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    await s.setBienvenidaVista(true);
    if (!mounted) return;
    if (widget.alTerminar != null) {
      widget.alTerminar!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pagina,
                onPageChanged: (i) => setState(() => _actual = i),
                children: [
                  _paginaInicio(theme),
                  _paginaGemini(theme),
                  _paginaTitular(theme),
                  _paginaConsejos(theme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  if (_actual > 0)
                    TextButton(
                      onPressed: () => _pagina.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('Atrás'),
                    )
                  else
                    const SizedBox(width: 64),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          _paginas,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _actual ? 20 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _actual
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _guardarYAvanzar,
                    child:
                        Text(_actual == _paginas - 1 ? 'Empezar' : 'Siguiente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marco(
      ThemeData theme, IconData icono, String titulo, List<Widget> contenido) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(icono, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ...contenido,
      ],
    );
  }

  Widget _paso(ThemeData theme, String numero, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            child: Text(numero, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }

  Widget _paginaInicio(ThemeData theme) {
    return _marco(theme, Icons.receipt_long, 'Bienvenido a Facturas PY', [
      Text(
        'Registrá tus facturas de gastos sin tipear nada y mandale a tu contador '
        'un PDF prolijo cada mes.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      _paso(theme, '1', 'Escaneás la factura con la cámara.'),
      _paso(theme, '2',
          'La inteligencia artificial de Google (Gemini) lee los datos: RUC, timbrado, montos e IVA.'),
      _paso(theme, '3', 'Revisás, corregís si hace falta y confirmás.'),
      _paso(theme, '4', 'A fin de mes generás el PDF y lo compartís.'),
      const SizedBox(height: 8),
      Text(
        'Tus facturas quedan guardadas solo en tu teléfono.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ]);
  }

  Widget _paginaGemini(ThemeData theme) {
    return _marco(theme, Icons.auto_awesome, 'Conectá Gemini', [
      Text(
        'Para leer las facturas, la app necesita una clave gratuita de Google '
        '(API key). Se crea una sola vez:',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 16),
      _paso(theme, '1',
          'Tocá el botón de abajo e iniciá sesión con tu cuenta de Google.'),
      _paso(theme, '2', 'Tocá "Create API key" (Crear clave) y copiala.'),
      _paso(theme, '3', 'Volvé acá, pegala en el campo y tocá "Probar".'),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: _abrirAiStudio,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Abrir Google AI Studio'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _keyCtrl,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Pegá acá tu API key',
          hintText: 'AIza...',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() => _resultadoPrueba = null),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: _probando || _keyCtrl.text.trim().isEmpty ? null : _probar,
        icon: _probando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.wifi_tethering),
        label: const Text('Probar'),
      ),
      if (_resultadoPrueba != null) ...[
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _pruebaOk ? Icons.check_circle : Icons.error_outline,
              color: _pruebaOk ? Colors.green : theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(_resultadoPrueba!)),
          ],
        ),
      ],
      const SizedBox(height: 16),
      Text(
        'Es gratis mientras no actives la facturación en Google. Podés hacer este '
        'paso después desde Ajustes; mientras tanto, podés cargar facturas a mano.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ]);
  }

  Widget _paginaTitular(ThemeData theme) {
    return _marco(theme, Icons.badge_outlined, 'Tus datos', [
      Text(
        'Aparecen en el encabezado del PDF que le mandás a tu contador.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _nombreCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Nombre y apellido / Razón social',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _rucCtrl,
        decoration: const InputDecoration(
          labelText: 'RUC',
          hintText: '1234567-8',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Opcional. Lo podés cambiar cuando quieras en Ajustes.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ]);
  }

  Widget _paginaConsejos(ThemeData theme) {
    Widget consejo(IconData icono, String titulo, String texto) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(texto, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _marco(theme, Icons.tips_and_updates_outlined, 'Algunos consejos', [
      consejo(Icons.document_scanner, 'Escaneá varias seguidas',
          'Con el botón + → "Escanear facturas" podés sacar todas juntas. Gemini las lee mientras seguís.'),
      consejo(Icons.fact_check_outlined, 'Revisá antes de confirmar',
          'Las facturas leídas quedan en "Por revisar". La IA puede equivocarse, sobre todo en los montos de IVA.'),
      consejo(Icons.swipe_left, 'Borrar',
          'Deslizá una factura hacia la izquierda o mantenela presionada.'),
      consejo(Icons.search, 'Buscar',
          'La lupa busca en todas tus facturas, de cualquier mes.'),
      consejo(Icons.bar_chart, 'Resumen anual',
          'El ícono de gráfico muestra tus gastos del año por mes, categoría y proveedor.'),
      consejo(Icons.backup_outlined, 'Copia de seguridad',
          'Una vez al mes, exportá una copia desde Ajustes y guardala en Drive.'),
    ]);
  }
}
