import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin store so tests can swap in an in-memory backend without calling
/// FlutterSecureStorage.setMockInitialValues from production code
/// (that API is `@visibleForTesting` and would trip flutter analyze).
abstract class AdminTokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAdminTokenStore implements AdminTokenStore {
  SecureAdminTokenStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryAdminTokenStore implements AdminTokenStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}

/// Persists the admin API key for authenticated admin-panel requests.
///
/// Uses [FlutterSecureStorage] (Keychain / Keystore on mobile; browser
/// storage on web — same XSS surface as SharedPreferences on web, but
/// OS-backed elsewhere). Migrates any legacy SharedPreferences value once.
///
/// Only used by the admin UI — player-facing routes stay unauthenticated.
class AdminAuthService {
  AdminAuthService._();

  static const _storageKey = 'admin_api_key';
  static String? _memoryToken;
  static AdminTokenStore _store = SecureAdminTokenStore();

  /// Widget / AdminApi debug tests should call this so token I/O uses an
  /// in-memory store (no platform secure-storage channel) and SharedPreferences
  /// does not hang on a missing platform channel.
  @visibleForTesting
  static void ensureTestStorage() {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    _store = MemoryAdminTokenStore();
  }

  @visibleForTesting
  static void debugReset() {
    _memoryToken = null;
    _store = MemoryAdminTokenStore();
  }

  @visibleForTesting
  static void setStoreForTest(AdminTokenStore store) {
    _store = store;
  }

  static Future<String?> getToken() async {
    if (_memoryToken != null) return _memoryToken;
    try {
      _memoryToken = await _store.read(_storageKey);
      if (_memoryToken != null && _memoryToken!.isNotEmpty) {
        return _memoryToken;
      }
      // One-shot migration from the previous SharedPreferences plaintext key.
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_storageKey);
      if (legacy != null && legacy.isNotEmpty) {
        await _store.write(_storageKey, legacy);
        await prefs.remove(_storageKey);
        _memoryToken = legacy;
      }
    } catch (_) {
      return null;
    }
    return _memoryToken;
  }

  static Future<void> saveToken(String token) async {
    _memoryToken = token.trim();
    try {
      await _store.write(_storageKey, _memoryToken!);
      // Ensure the legacy plaintext key cannot linger after a re-save.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Memory-only when platform store is unavailable (e.g. some test runs).
    }
  }

  static Future<void> clearToken() async {
    _memoryToken = null;
    try {
      await _store.delete(_storageKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}
