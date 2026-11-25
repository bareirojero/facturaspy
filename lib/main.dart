import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/bienvenida_screen.dart';
import 'screens/home_screen.dart';
import 'services/cola_procesamiento.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  runApp(const FacturasPyApp());
  // Retomar facturas que quedaron a medio leer si se cerró la app.
  ColaProcesamiento.instance.reanudarPendientes();
}

class FacturasPyApp extends StatelessWidget {
  const FacturasPyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Facturas PY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F4C81),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F4C81),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'PY'),
        Locale('es'),
      ],
      locale: const Locale('es', 'PY'),
      home: const _Inicio(),
    );
  }
}

/// Muestra la bienvenida la primera vez. Quien ya tiene una API key cargada
/// (usuarios de versiones anteriores) va directo al inicio.
class _Inicio extends StatefulWidget {
  const _Inicio();

  @override
  State<_Inicio> createState() => _InicioState();
}

class _InicioState extends State<_Inicio> {
  bool? _mostrarBienvenida;

  @override
  void initState() {
    super.initState();
    _decidir();
  }

  Future<void> _decidir() async {
    final s = SettingsService.instance;
    bool mostrar = !(await s.getBienvenidaVista());
    if (mostrar && (await s.getApiKey()).isNotEmpty) {
      await s.setBienvenidaVista(true);
      mostrar = false;
    }
    if (mounted) setState(() => _mostrarBienvenida = mostrar);
  }

  @override
  Widget build(BuildContext context) {
    final mostrar = _mostrarBienvenida;
    if (mostrar == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (mostrar) {
      return BienvenidaScreen(
        alTerminar: () => setState(() => _mostrarBienvenida = false),
      );
    }
    return const HomeScreen();
  }
}
