import 'package:flutter_test/flutter_test.dart';
import 'package:hidden_eleven/features/admin/services/admin_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.ensureTestStorage();
    AdminAuthService.debugReset();
  });

  tearDown(() {
    AdminAuthService.debugReset();
  });

  test(
    'saveToken / getToken round-trip via secure storage abstraction',
    () async {
      await AdminAuthService.saveToken('  secret-key-123  ');
      final token = await AdminAuthService.getToken();
      expect(token, 'secret-key-123');
    },
  );

  test('clearToken removes the key', () async {
    await AdminAuthService.saveToken('to-clear');
    await AdminAuthService.clearToken();
    expect(await AdminAuthService.getToken(), isNull);
  });

  test(
    'migrates legacy SharedPreferences key into secure store once',
    () async {
      SharedPreferences.setMockInitialValues({'admin_api_key': 'legacy-key'});
      final store = MemoryAdminTokenStore();
      AdminAuthService.setStoreForTest(store);

      final token = await AdminAuthService.getToken();
      expect(token, 'legacy-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('admin_api_key'), isNull);
      expect(await store.read('admin_api_key'), 'legacy-key');
    },
  );
}
