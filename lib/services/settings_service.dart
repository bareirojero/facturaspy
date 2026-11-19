import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._init();
  SettingsService._init();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _keyApiKey = 'gemini_api_key';
  static const String _keyModel = 'gemini_model';
  static const String _keyNombreTitular = 'titular_nombre';
  static const String _keyRucTitular = 'titular_ruc';

  static const String defaultModel = 'gemini-flash-latest';

  Future<String> getApiKey() async {
    return (await _storage.read(key: _keyApiKey)) ?? '';
  }

  Future<void> setApiKey(String value) async {
    await _storage.write(key: _keyApiKey, value: value.trim());
  }

  Future<String> getModel() async {
    final val = await _storage.read(key: _keyModel);
    return (val == null || val.trim().isEmpty) ? defaultModel : val.trim();
  }

  Future<void> setModel(String value) async {
    final clean = value.trim().isEmpty ? defaultModel : value.trim();
    await _storage.write(key: _keyModel, value: clean);
  }

  Future<String> getNombreTitular() async {
    return (await _storage.read(key: _keyNombreTitular)) ?? '';
  }

  Future<void> setNombreTitular(String value) async {
    await _storage.write(key: _keyNombreTitular, value: value.trim());
  }

  Future<String> getRucTitular() async {
    return (await _storage.read(key: _keyRucTitular)) ?? '';
  }

  Future<void> setRucTitular(String value) async {
    await _storage.write(key: _keyRucTitular, value: value.trim());
  }
}
