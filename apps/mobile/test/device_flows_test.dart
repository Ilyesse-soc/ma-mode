import 'dart:async';
import 'dart:convert';

import 'package:alamode/features/settings/account_screens.dart';
import 'package:alamode/features/wardrobe/screens/photo_screen.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart'
    as sharing;

import 'user_flows_test.dart' show ContractAdapter, pumpScreen;

class TestCamera extends CameraPlatform {
  bool denied = false;
  int opened = 0, released = 0;
  final errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (denied) {
      throw CameraException('CameraAccessDenied', 'Permission denied');
    }
    return [
      const CameraDescription(
        name: 'rear',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    expectSync(enableAudio, false);
    return ++opened;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          960,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.grey);
  @override
  Future<XFile> takePicture(int cameraId) async => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4ZkAAAAASUVORK5CYII=',
    ),
    name: 'capture.png',
  );
  @override
  Future<void> dispose(int cameraId) async {
    released++;
  }
}

class TestShare extends sharing.SharePlatform {
  sharing.ShareParams? last;
  bool fail = false;
  @override
  Future<sharing.ShareResult> share(sharing.ShareParams params) async {
    last = params;
    if (fail) throw StateError('Share unavailable');
    return const sharing.ShareResult('', sharing.ShareResultStatus.dismissed);
  }
}

void main() {
  testWidgets('camera permission denial exposes gallery and retry', (
    tester,
  ) async {
    final old = CameraPlatform.instance;
    final camera = TestCamera()..denied = true;
    CameraPlatform.instance = camera;
    addTearDown(() => CameraPlatform.instance = old);
    await pumpScreen(
      tester,
      const PhotoScreen(),
      ContractAdapter((_) => (200, {})),
    );
    expect(find.textContaining('Caméra indisponible'), findsOneWidget);
    expect(find.byTooltip('Galerie'), findsOneWidget);
    camera.denied = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(camera.opened, 1);
    expect(find.bySemanticsLabel('Prendre la photo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(camera.released, 1);
  });

  testWidgets('capture releases camera and retake opens it again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final old = CameraPlatform.instance;
    final camera = TestCamera();
    CameraPlatform.instance = camera;
    addTearDown(() => CameraPlatform.instance = old);
    await pumpScreen(
      tester,
      const PhotoScreen(labelMode: true),
      ContractAdapter((_) => (200, {})),
    );
    await tester.tap(find.bySemanticsLabel('Prendre la photo'));
    await tester.pumpAndSettle();
    expect(find.text('Utiliser cette photo'), findsOneWidget);
    expect(camera.released, 1);
    await tester.tap(find.text('Reprendre'));
    await tester.pumpAndSettle();
    expect(camera.opened, 2);
    expect(find.text('Photo étiquette'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('camera is released in background and reopens on resume', (
    tester,
  ) async {
    final old = CameraPlatform.instance;
    final camera = TestCamera();
    CameraPlatform.instance = camera;
    addTearDown(() => CameraPlatform.instance = old);
    await pumpScreen(
      tester,
      const PhotoScreen(),
      ContractAdapter((_) => (200, {})),
    );
    expect(camera.opened, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(camera.released, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossible d’ouvrir'), findsNothing);
    expect(find.textContaining('Caméra indisponible'), findsNothing);
    expect(camera.opened, 2);
    expect(find.bySemanticsLabel('Prendre la photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(camera.released, 2);
  });

  testWidgets(
    'export shares API JSON as a file and keeps copy available on failure',
    (tester) async {
      final old = sharing.SharePlatform.instance;
      final share = TestShare();
      sharing.SharePlatform.instance = share;
      addTearDown(() => sharing.SharePlatform.instance = old);
      final data = {
        'user': {'email': 'owner@example.com'},
        'garments': [],
        'outfits': [],
        'history': [],
      };
      await pumpScreen(
        tester,
        const ExportScreen(),
        ContractAdapter((_) => (200, data)),
      );
      await tester.tap(find.text('Enregistrer ou partager le fichier JSON'));
      await tester.pumpAndSettle();
      expect(share.last!.fileNameOverrides, ['dressly-donnees.json']);
      expect(share.last!.files!.single.mimeType, 'application/json');
      expect(jsonDecode(await share.last!.files!.single.readAsString()), data);
      expect(share.last!.sharePositionOrigin!.width, greaterThan(0));
      share.fail = true;
      await tester.tap(find.text('Enregistrer ou partager le fichier JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Partage indisponible'), findsOneWidget);
      expect(find.text('Copier mon export JSON'), findsOneWidget);
    },
  );
}
