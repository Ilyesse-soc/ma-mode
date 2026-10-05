import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/network/token_storage.dart';
import 'core/observability.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();
  await Hive.initFlutter();
  final key = await TokenStorage().cacheEncryptionKey();
  for (final name in ['wardrobe_cache', 'recommendations_cache']) {
    try {
      await Hive.openBox<String>(name, encryptionCipher: HiveAesCipher(key));
    } catch (_) {
      // Discard legacy plaintext caches; authoritative data remains on the API.
      await Hive.deleteBoxFromDisk(name);
      await Hive.openBox<String>(name, encryptionCipher: HiveAesCipher(key));
    }
  }
  await Hive.openBox<String>('settings_cache');
  await runWithErrorTracking(
    () => runApp(const ProviderScope(child: AlamodeApp())),
  );
}
