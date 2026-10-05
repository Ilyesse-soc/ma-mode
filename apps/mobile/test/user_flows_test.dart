import 'dart:convert';
import 'dart:io';

import 'package:alamode/core/models.dart';
import 'package:alamode/core/network/api_client.dart';
import 'package:alamode/core/network/token_storage.dart';
import 'package:alamode/core/providers.dart';
import 'package:alamode/core/router.dart';
import 'package:alamode/core/theme/app_theme.dart';
import 'package:alamode/features/location/destination_screen.dart';
import 'package:alamode/features/location/location_controller.dart';
import 'package:alamode/features/preferences/preferences_screen.dart';
import 'package:alamode/features/recommendation/outfit_flow_screen.dart';
import 'package:alamode/features/settings/account_screens.dart';
import 'package:alamode/features/wardrobe/screens/garment_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Network doubles are confined to tests. Every screen uses its production API client.
class MemoryTokens extends TokenStorage {
  MemoryTokens({this.active = true});
  bool active;
  @override
  Future<String?> readAccess() async => active ? 'test-access' : null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, required String refresh}) async {
    active = true;
  }

  @override
  Future<void> clear() async {
    active = false;
  }
}

class ContractAdapter implements HttpClientAdapter {
  ContractAdapter(this.handler);
  final (int, Object?) Function(RequestOptions) handler;
  final List<RequestOptions> calls = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class ManualLocation extends LocationController {
  @override
  LocationState build() => const LocationState(
    permission: LocationPermissionState.manual,
    latitude: 48.8566,
    longitude: 2.3522,
    label: 'Paris',
  );
}

const garmentJson = <String, dynamic>{
  'id': 'g1',
  'name': 'Hoodie gris',
  'color': 'grey',
  'brand': 'Marque',
  'size': 'M',
  'material': 'coton',
  'season': 'winter',
  'warmth_level': 4,
  'category': {'id': 1, 'slug': 'hoodie', 'label': 'Sweat', 'group': 'top'},
  'images': <Object>[],
};

Recommendation recommendation({int rank = 1}) => Recommendation(
  id: 'r1',
  proposals: [
    OutfitProposal(
      rank: rank,
      score: .9,
      garmentIds: ['g1'],
      explanations: ['Adaptée à la météo réelle'],
      breakdown: const {},
    ),
  ],
  weatherSummary: const {'min_feels_like_c': 12, 'max_feels_like_c': 18},
  activity: 'work',
  originLabel: 'Paris',
);

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen,
  ContractAdapter adapter,
) async {
  final api = ApiClient(MemoryTokens())..dio.httpClientAdapter = adapter;
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/wardrobe/garment/:id',
        builder: (_, _) => const Scaffold(body: Text('Détail ouvert')),
      ),
      GoRoute(
        path: '/auth/welcome',
        builder: (_, _) => const Scaffold(body: Text('Déconnecté')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        locationControllerProvider.overrideWith(ManualLocation.new),
        wardrobeProvider.overrideWith(
          (ref) async => [Garment.fromJson(garmentJson)],
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late Directory cache;
  setUpAll(() async {
    cache = await Directory.systemTemp.createTemp('dressly-flow-tests-');
    Hive.init(cache.path);
    for (final box in [
      'settings_cache',
      'wardrobe_cache',
      'recommendations_cache',
    ]) {
      await Hive.openBox<String>(box);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await cache.delete(recursive: true);
  });

  test('cached garment keeps photos and editable fields', () {
    final garment = Garment.fromJson({
      ...garmentJson,
      'images': [
        {
          'id': 'image-1',
          'content_type': 'image/jpeg',
          'is_primary': true,
          'download_url': 'https://storage.test/image',
        },
      ],
    });
    final cached = Garment.fromJson(garment.toCacheJson());
    expect(cached.size, 'M');
    expect(cached.material, 'coton');
    expect(cached.season, 'winter');
    expect(cached.images.single.downloadUrl, isNull);
  });

  testWidgets(
    'garment detail loads its real endpoint independently of wardrobe list',
    (tester) async {
      final adapter = ContractAdapter((request) => (200, garmentJson));
      await pumpScreen(
        tester,
        const GarmentDetailScreen(garmentId: 'g1'),
        adapter,
      );
      expect(adapter.calls.single.path, '/garments/g1');
      expect(
        adapter.calls.single.headers['Authorization'],
        'Bearer test-access',
      );
      expect(find.text('Hoodie gris'), findsOneWidget);
      expect(find.text('coton'), findsOneWidget);
    },
  );

  testWidgets('garment fetch failure offers retry', (tester) async {
    var fail = true;
    final adapter = ContractAdapter(
      (request) => fail
          ? (
              503,
              {
                'error': {'code': 'offline', 'message': 'Service indisponible'},
              },
            )
          : (200, garmentJson),
    );
    await pumpScreen(
      tester,
      const GarmentDetailScreen(garmentId: 'g1'),
      adapter,
    );
    expect(find.text('Service indisponible'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Hoodie gris'), findsOneWidget);
  });

  testWidgets('preferences save failure keeps screen and exposes error', (
    tester,
  ) async {
    final adapter = ContractAdapter(
      (request) => request.method == 'GET'
          ? (
              200,
              {
                'preferred_styles': ['Streetwear'],
                'liked_colors': ['black'],
                'avoided_colors': ['red'],
                'cold_threshold_celsius': 12,
                'hot_threshold_celsius': 24,
              },
            )
          : (
              503,
              {
                'error': {
                  'code': 'unavailable',
                  'message': 'Enregistrement impossible',
                },
              },
            ),
    );
    await pumpScreen(
      tester,
      const PreferencesScreen(fromRegister: true),
      adapter,
    );
    await tester.scrollUntilVisible(find.text('Sauvegarder'), 250);
    await tester.tap(find.text('Sauvegarder'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrement impossible'), findsOneWidget);
    final payload = adapter.calls.last.data as Map;
    expect(payload['avoided_colors'], ['red']);
    expect(payload['preferred_styles'], ['Streetwear']);
  });

  testWidgets('export exposes actual JSON and copies it', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final adapter = ContractAdapter(
      (request) => (
        200,
        {
          'user': {'email': 'real@example.com'},
          'garments': [],
          'outfits': [],
          'history': [],
        },
      ),
    );
    await pumpScreen(tester, const ExportScreen(), adapter);
    expect(adapter.calls.single.path, '/privacy/export');
    await tester.tap(find.text('Copier mon export JSON'));
    await tester.pumpAndSettle();
    expect(jsonDecode(copied!)['user']['email'], 'real@example.com');
  });

  testWidgets('destination selection returns chosen coordinates', (
    tester,
  ) async {
    Place? chosen;
    final adapter = ContractAdapter((request) => (200, []));
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              chosen = await Navigator.push<Place>(
                context,
                MaterialPageRoute(
                  builder: (_) => const DestinationScreen(select: true),
                ),
              );
            },
            child: const Text('Ouvrir destination'),
          ),
        ),
      ),
      adapter,
    );
    await tester.tap(find.text('Ouvrir destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lille, France'));
    await tester.pumpAndSettle();
    expect(chosen!.latitude, 50.6292);
    expect(chosen!.longitude, 3.0573);
    expect(adapter.calls.every((call) => call.method == 'GET'), isTrue);
  });

  testWidgets(
    'outfit explains an existing recommendation without regenerating',
    (tester) async {
      final adapter = ContractAdapter((request) => (200, {}));
      await pumpScreen(
        tester,
        OutfitFlowScreen(initialRecommendation: recommendation(rank: 3)),
        adapter,
      );
      await tester.tap(find.text('Pourquoi cette tenue ?'));
      await tester.pumpAndSettle();
      expect(find.text('Adaptée à la météo réelle'), findsOneWidget);
      expect(find.text('Hoodie gris'), findsOneWidget);
      expect(adapter.calls, isEmpty);
    },
  );

  testWidgets(
    'empty generation returns an actionable error instead of crashing',
    (tester) async {
      final adapter = ContractAdapter(
        (request) => (
          201,
          {
            'id': 'r1',
            'proposals': [],
            'weather_summary': {},
            'activity': 'everyday',
          },
        ),
      );
      await pumpScreen(tester, const OutfitFlowScreen(), adapter);
      final generateButton = find.widgetWithText(
        FilledButton,
        'Générer ma tenue ✨',
      );
      await tester.scrollUntilVisible(generateButton, 250);
      await tester.ensureVisible(generateButton);
      await tester.pumpAndSettle();
      await tester.tap(generateButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Aucune tenue disponible'), findsOneWidget);
      expect(adapter.calls.single.path, '/recommendations/generate');
      expect((adapter.calls.single.data as Map)['origin_latitude'], 48.8566);
    },
  );

  testWidgets('outfit setup remains usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = ContractAdapter(
      (_) => (
        201,
        {
          'id': 'r1',
          'proposals': [],
          'weather_summary': {},
          'activity': 'work',
        },
      ),
    );
    await pumpScreen(tester, const OutfitFlowScreen(), adapter);
    final activity = find.widgetWithText(ChoiceChip, 'Travail');
    await tester.scrollUntilVisible(activity, 180);
    await tester.ensureVisible(activity);
    await tester.pumpAndSettle();
    await tester.tap(activity);
    final button = find.widgetWithText(FilledButton, 'Générer ma tenue ✨');
    await tester.scrollUntilVisible(button, 180);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Aucune tenue disponible'), findsOneWidget);
    expect((adapter.calls.single.data as Map)['activity'], 'work');
  });

  testWidgets('feedback failure can be retried and never shows success', (
    tester,
  ) async {
    final adapter = ContractAdapter(
      (request) => (
        503,
        {
          'error': {'code': 'unavailable', 'message': 'Retour non enregistré'},
        },
      ),
    );
    await pumpScreen(
      tester,
      OutfitFlowScreen(initialRecommendation: recommendation()),
      adapter,
    );
    await tester.scrollUntilVisible(
      find.text('Donner mon avis'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Donner mon avis'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Valider'), 200);
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(find.text('Retour non enregistré'), findsOneWidget);
    expect(find.text('Merci pour ton retour'), findsNothing);
    expect(adapter.calls.single.path, '/recommendations/r1/feedback');
  });

  testWidgets(
    'private routes redirect guests and registration opens preferences',
    (tester) async {
      final tokens = MemoryTokens(active: false);
      final adapter = ContractAdapter(
        (request) => switch (request.path) {
          '/auth/register' => (
            201,
            {'access_token': 'access', 'refresh_token': 'refresh'},
          ),
          '/me' => (
            200,
            {
              'id': 'u1',
              'first_name': 'Alex',
              'email': 'alex@example.com',
              'mannequin_presentation': 'female',
              'email_verified': false,
            },
          ),
          '/me/preferences' => (
            200,
            {
              'preferred_styles': [],
              'liked_colors': [],
              'avoided_colors': [],
              'cold_threshold_celsius': 12,
              'hot_threshold_celsius': 24,
            },
          ),
          _ => (200, {}),
        },
      );
      final api = ApiClient(tokens)..dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStorageProvider.overrideWithValue(tokens),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      router.go('/privacy/export');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/auth/welcome');
      router.go('/auth/register');
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container
            .read(authControllerProvider.notifier)
            .register(
              firstName: 'Alex',
              email: 'alex@example.com',
              password: 'correct-password-10',
              mannequinPresentation: 'female',
            ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/preferences');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['from'],
        'register',
      );
      expect(find.text('Tes préférences'), findsOneWidget);
    },
  );

  testWidgets('menu opens wardrobe tab and profile on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tokens = MemoryTokens();
    final adapter = ContractAdapter(
      (request) => switch (request.path) {
        '/me' => (
          200,
          {
            'id': 'u1',
            'first_name': 'Alex',
            'email': 'alex@example.com',
            'mannequin_presentation': 'female',
            'email_verified': true,
          },
        ),
        '/garments' => (200, {'items': [], 'total': 0}),
        '/outfits' => (200, []),
        '/recommendations/last' => (200, null),
        '/weather/current' => (
          503,
          {
            'error': {'code': 'unavailable', 'message': 'Météo indisponible'},
          },
        ),
        _ => (200, {}),
      },
    );
    final api = ApiClient(tokens)..dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStorageProvider.overrideWithValue(tokens),
        locationControllerProvider.overrideWith(ManualLocation.new),
        wardrobeProvider.overrideWith((ref) async => <Garment>[]),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garde-robe').last);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['tab'],
      'wardrobe',
    );
    expect(find.text('Ma garde-robe'), findsOneWidget);
    expect(find.text('Ta garde-robe est vide'), findsOneWidget);
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Mes préférences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
