import 'dart:convert';
import 'package:alamode/core/models.dart';
import 'package:alamode/core/network/api_client.dart';
import 'package:alamode/core/observability.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:alamode/core/config.dart';
import 'package:alamode/core/network/token_storage.dart';
import 'dart:async';
import 'dart:typed_data';

import 'user_flows_test.dart' show MemoryTokens, ContractAdapter, garmentJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline import retains honesty flags without private image paths or candidate URLs',
    () {
      final garment = Garment.fromJson({
        ...garmentJson,
        'brand': 'Hypothesis',
        'import_metadata': {
          'source_type': 'screenshot',
          'save_mode': 'approximate',
          'exact_match': false,
          'fallback_mode': true,
          'brand_status': 'unverified',
          'original_image_path': 'private-object-key',
          'original_image_url': 'https://example.com/?signature=private',
          'candidates': [
            {
              'images': ['https://example.com/?signature=private'],
            },
          ],
        },
      });
      final encoded = jsonEncode(garment.toCacheJson());
      expect(encoded, isNot(contains('private-object-key')));
      expect(encoded, isNot(contains('signature=private')));
      expect(
        Garment.fromJson(jsonDecode(encoded)).brandLabel,
        contains('supposée'),
      );
    },
  );
  test(
    'secure storage writes are serialized and stale refresh cannot restore a session',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final tokens = TokenStorage();
      await tokens.save(access: 'old-access', refresh: 'old-refresh');
      await tokens.clear();
      final accepted = await tokens.saveIfCurrent(
        access: 'stale-access',
        refresh: 'stale-refresh',
        isCurrent: () => false,
      );
      expect(accepted, isFalse);
      expect(await tokens.readAccess(), isNull);
      final key = await tokens.cacheEncryptionKey();
      expect(key, hasLength(32));
      expect(await tokens.cacheEncryptionKey(), key);
    },
  );

  test(
    'concurrent 401s perform one refresh and retry each request once',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final tokens = TokenStorage();
      await tokens.save(access: 'old-access', refresh: 'old-refresh');
      final refreshAdapter = DelayedRefreshAdapter();
      final refresh = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
        ..httpClientAdapter = refreshAdapter;
      final api = ApiClient(tokens, refreshClient: refresh);
      api.dio.httpClientAdapter = ContractAdapter(
        (options) => options.headers['Authorization'] == 'Bearer new-access'
            ? (200, {'ok': true})
            : (401, {}),
      );
      final responses = await Future.wait([
        api.dio.get('/me'),
        api.dio.get('/me/preferences'),
      ]);
      expect(
        responses.map((response) => response.statusCode),
        everyElement(200),
      );
      expect(refreshAdapter.calls, 1);
      expect(await tokens.readRefresh(), 'new-refresh');
    },
  );
  test('signed image URLs are absent from offline cache', () {
    final garment = Garment.fromJson({
      ...garmentJson,
      'images': [
        {
          'id': 'image',
          'content_type': 'image/jpeg',
          'download_url': 'https://s3.example/photo?X-Amz-Signature=private',
          'object_key': 'users/user/photo.jpg',
        },
      ],
    });
    expect(
      jsonEncode(garment.toCacheJson()),
      isNot(contains('X-Amz-Signature')),
    );
  });

  test('foreign origin is blocked before adding Authorization', () async {
    final adapter = ContractAdapter((_) => (200, {}));
    final api = ApiClient(MemoryTokens())..dio.httpClientAdapter = adapter;
    await expectLater(
      api.dio.get('https://attacker.example/private'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, isEmpty);
  });

  test(
    'unauthorized response clears tokens and notifies expired session',
    () async {
      final tokens = MemoryTokens();
      var expired = false;
      final api = ApiClient(
        tokens,
        onSessionExpired: () async {
          expired = true;
        },
      );
      api.dio.httpClientAdapter = ContractAdapter(
        (_) => (401, {'error': 'expired'}),
      );
      await expectLater(api.dio.get('/me'), throwsA(isA<DioException>()));
      expect(tokens.active, isFalse);
      expect(expired, isTrue);
    },
  );

  test('Sentry keeps error type and strips personal content', () {
    final event = SentryEvent(
      user: SentryUser(email: 'private@example.com'),
      message: SentryMessage('OCR private-marker'),
      exceptions: [
        const SentryException(
          type: 'StateError',
          value: 'Bearer private-marker',
        ),
      ],
      request: SentryRequest(
        url: 'https://s3.example/photo?token=private-marker',
      ),
    );
    final encoded = jsonEncode(privacyFilteredEvent(event).toJson());
    expect(encoded, contains('StateError'));
    expect(encoded, isNot(contains('private-marker')));
    expect(encoded, isNot(contains('private@example.com')));
    expect(encoded, isNot(contains('https://s3')));
  });
}

class DelayedRefreshAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return ResponseBody.fromString(
      jsonEncode({
        'access_token': 'new-access',
        'refresh_token': 'new-refresh',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
