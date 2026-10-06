import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alamode/features/auth/screens/login_screen.dart';
import 'package:alamode/features/wardrobe/screens/import_image_screen.dart';
import 'package:alamode/features/wardrobe/screens/add_garment_screen.dart';
import 'package:alamode/features/wardrobe/screens/identification_review_screen.dart';
import 'package:dio/dio.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'user_flows_test.dart' show ContractAdapter, pumpScreen, garmentJson;

class SelectedFile extends FileSelectorPlatform {
  XFile? file;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

class PendingLogin extends ContractAdapter {
  PendingLogin()
    : super(
        (_) => (
          401,
          {
            'error': {
              'code': 'invalid_credentials',
              'message': 'Identifiants incorrects',
            },
          },
        ),
      );
  final gate = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await gate.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  testWidgets(
    'failed image upload offers retry and explicit manual continuation without claiming a saved photo',
    (tester) async {
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = SelectedFile()
        ..file = XFile.fromData(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAN0lEQVR4nO3RwQ0AMAjDwJTJM3pHMB9+vgGCZF7bXJrT9XhgwR8gEyETIRMhEyETIRMhEyEThXy+PQHA+Ry5NgAAAABJRU5ErkJggg==',
          ),
          name: 'capture.png',
        );
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final adapter = ContractAdapter((request) {
        if (request.path == '/garment-categories') {
          return (200, [garmentJson['category']]);
        }
        return (
          503,
          {
            'error': {
              'code': 'provider_unavailable',
              'message': 'Envoi indisponible',
            },
          },
        );
      });
      await pumpScreen(
        tester,
        const AddGarmentScreen(initialCategorySlug: 'hoodie'),
        adapter,
      );
      await tester.tap(find.text('Importer une image'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Fichier local')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Utiliser cette image'), 250);
      await tester.tap(find.text('Utiliser cette image'));
      await tester.pumpAndSettle();
      expect(find.text('Réessayer l’envoi de l’image'), findsOneWidget);
      expect(
        find.text(
          'Ton image est conservée. Vérifie la catégorie et la couleur ; laisse la marque vide si elle est inconnue.',
        ),
        findsNothing,
      );
      expect(adapter.calls.where((r) => r.path == '/media/upload').length, 1);
      expect(
        adapter.calls.where((r) => r.method == 'POST' && r.path == '/garments'),
        isEmpty,
      );
      await tester.tap(find.text('Continuer sans image'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('Réessayer l’envoi de l’image'), findsNothing);
    },
  );
  testWidgets('login validates locally and stays usable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final adapter = ContractAdapter((_) => (500, {}));
    await pumpScreen(tester, const LoginScreen(), adapter);
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    await tester.pumpAndSettle();
    expect(find.text('Email invalide'), findsOneWidget);
    expect(find.text('Mot de passe requis'), findsOneWidget);
    expect(adapter.calls, isEmpty);
    await tester.ensureVisible(find.text('Aide à la connexion'));
    await tester.tap(find.text('Aide à la connexion'));
    await tester.pumpAndSettle();
    expect(find.text('Utiliser mon code de réinitialisation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'login disables duplicate submissions while the real request is pending',
    (tester) async {
      final adapter = PendingLogin();
      await pumpScreen(tester, const LoginScreen(), adapter);
      await tester.enterText(
        find.byType(TextFormField).first,
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password');
      await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      adapter.gate.complete();
      await tester.pumpAndSettle();
      expect(adapter.calls.where((c) => c.path == '/auth/login').length, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'local import previews a selected image without uploading or invoking AI',
    (tester) async {
      final previous = FileSelectorPlatform.instance;
      final picker = SelectedFile()
        ..file = XFile.fromData(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAN0lEQVR4nO3RwQ0AMAjDwJTJM3pHMB9+vgGCZF7bXJrT9XhgwR8gEyETIRMhEyETIRMhEyEThXy+PQHA+Ry5NgAAAABJRU5ErkJggg==',
          ),
          name: 'capture.png',
        );
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = previous);
      final adapter = ContractAdapter((_) => (500, {}));
      await pumpScreen(tester, const ImportImageScreen(), adapter);
      expect(find.text('Galerie'), findsOneWidget);
      expect(find.text('Capture d’écran'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Fichier local')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Utiliser cette image'), 250);
      expect(find.text('Utiliser cette image'), findsOneWidget);
      expect(adapter.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown product offers both honest saving paths without network requests',
    (tester) async {
      final adapter = ContractAdapter((_) => (500, {}));
      await pumpScreen(
        tester,
        const IdentificationReviewScreen(
          garmentId: 'owned',
          result: {'candidates': [], 'evidence': {}},
        ),
        adapter,
      );
      await tester.scrollUntilVisible(
        find.text('Enregistrer comme vêtement personnalisé'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Enregistrer comme vêtement personnalisé'),
        findsOneWidget,
      );
      expect(find.text('Continuer avec une version approchée'), findsOneWidget);
      expect(adapter.calls, isEmpty);
    },
  );
}
