import 'dart:io';
import 'package:alamode/features/onboarding/onboarding_page.dart';
import 'package:alamode/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('dressly-intro-');
    Hive.init(directory.path);
    await Hive.openBox<String>('settings_cache');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('all four ordered local images are bundled as actual PNGs', () async {
    final paths = [
      IntroAssets.splash,
      ...IntroAssets.pages.map((p) => p.image),
    ];
    expect(paths.map((p) => p.split('/').last).toList(), [
      'bording1.png',
      'boarding2.png',
      'boarding3.png',
      'boarding4.png',
    ]);
    for (final path in paths) {
      final data = await rootBundle.load(path);
      expect(data.buffer.asUint8List().take(8).toList(), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    }
  });

  testWidgets('swipe, next, pagination and commencer reach auth', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/auth/register',
          builder: (_, _) =>
              const Scaffold(body: Text('Authentication destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Une garde-robe intelligente'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Page 2 sur 3'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Page 3 sur 3'), findsOneWidget);
    expect(find.text('Commencer'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Commencer'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Authentication destination'), findsOneWidget);
    expect(Hive.box<String>('settings_cache').get('onboarding_seen'), '1');
    expect(tester.takeException(), isNull);
  });
}
