import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:hive/hive.dart';

/// Secure token persistence (Keychain on iOS, Keystore on Android).
class TokenStorage {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _sessionKey = 'session_v2';
  static const _cacheKey = 'offline_cache_key_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  Future<void> _pendingWrite = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pendingWrite.then((_) => operation());
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> save({required String access, required String refresh}) =>
      _serialize(() => _writeSession(access, refresh));

  Future<bool> saveIfCurrent({
    required String access,
    required String refresh,
    required bool Function() isCurrent,
  }) => _serialize(() async {
    if (!isCurrent()) return false;
    await _writeSession(access, refresh);
    return true;
  });

  Future<void> _writeSession(String access, String refresh) async {
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'access': access, 'refresh': refresh}),
    );
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<String?> _readToken(String field, String legacyKey) async {
    final session = await _storage.read(key: _sessionKey);
    if (session != null) return (jsonDecode(session) as Map)[field] as String?;
    return _storage.read(key: legacyKey);
  }

  Future<String?> readAccess() => _readToken('access', _accessKey);
  Future<String?> readRefresh() => _readToken('refresh', _refreshKey);

  Future<List<int>> cacheEncryptionKey() async {
    var key = await _storage.read(key: _cacheKey);
    if (key == null) {
      key = base64Encode(Hive.generateSecureKey());
      await _storage.write(key: _cacheKey, value: key);
    }
    return base64Decode(key);
  }

  Future<void> clear() => _serialize(() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  });
}
