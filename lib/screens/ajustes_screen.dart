import 'package:flutter/material.dart';
import '../services/gemini_service.dart';
import '../services/settings_service.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _nombreTitularCtrl = TextEditingController();
  final _rucTitularCtrl = TextEditingController();

  bool _ocultarKey = true;
  bool _cargando = true;
  bool _probando = false;

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
  }

  Future<void> _cargarAjustes() async {
    final s = SettingsService.instance;
    _apiKeyCtrl.text = await s.getApiKey();
    _modelCtrl.text = await s.getModel();
    _nombreTitularCtrl.text = await s.getNombreTitular();
    _rucTitularCtrl.text = await s.getRucTitular();

    if (mounted) {
      setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _nombreTitularCtrl.dispose();
    _rucTitularCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarAjustes() async {
    final s = SettingsService.instance;
    await s.setApiKey(_apiKeyCtrl.text);
    await s.setModel(_modelCtrl.text);
    await s.setNombreTitular(_nombreTitularCtrl.text);
    await s.setRucTitular(_rucTitularCtrl.text);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ajustes guardados correctamente')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _probarConexion() async {
    setState(() => _probando = true);
    try {
      final msg = await GeminiService.instance.probarConexion(
        apiKey: _apiKeyCtrl.text,
        model: _modelCtrl.text,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: const Text('Conexión OK'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
          title: const Text('Error de conexión'),
          content: Text(e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Google Gemini API',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: _ocultarKey,
                  decoration: InputDecoration(
                    labelText: 'API Key de Gemini',
                    hintText: 'AIzaSy...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarKey ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _ocultarKey = !_ocultarKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Modelo Gemini',
                    hintText: SettingsService.defaultModel,
                    helperText: 'Por defecto: ${SettingsService.defaultModel}',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _probando ? null : _probarConexion,
                  icon: _probando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Probar conexión'),
                ),
                const Divider(height: 36),
                Text(
                  'Datos del Contribuyente (para el PDF)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nombreTitularCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre y Apellido / Razón Social',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rucTitularCtrl,
                  decoration: const InputDecoration(
                    labelText: 'RUC del Titular',
                    hintText: '4123456-7',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _guardarAjustes,
                  icon: const Icon(Icons.save),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Guardar Ajustes'),
                  ),
                ),
              ],
            ),
    );
  }
}
