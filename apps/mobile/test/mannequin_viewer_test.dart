import 'dart:convert';
import 'dart:typed_data';

import 'package:alamode/core/theme/app_theme.dart';
import 'package:alamode/features/mannequin/mannequin_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MissingModelBundle extends CachingAssetBundle {
  int attempts = 0;
  final bool corrupt;
  MissingModelBundle({this.corrupt = false});
  @override
  Future<ByteData> load(String key) async {
    attempts++;
    if (corrupt) return ByteData(20);
    throw FlutterError('Missing model');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final presentation in ['female', 'male']) {
    test(
      '$presentation maps to the supplied, bundled GLB and preserves meshes',
      () async {
        final viewer = MannequinViewer(
          presentation: presentation,
        ).createViewer();
        expect(viewer.src, 'assets/3d/mannequins/$presentation.glb');
        final bytes = await rootBundle.load(viewer.src);
        expect(bytes.getUint32(0, Endian.little), 0x46546c67);
        expect(bytes.getUint32(4, Endian.little), 2);
        expect(bytes.getUint32(8, Endian.little), bytes.lengthInBytes);
        final jsonLength = bytes.getUint32(12, Endian.little);
        final json =
            jsonDecode(
                  utf8.decode(
                    bytes.buffer.asUint8List(
                      bytes.offsetInBytes + 20,
                      jsonLength,
                    ),
                  ),
                )
                as Map;
        expect(
          (json['meshes'] as List).map((m) => m['name']),
          containsAll(['Mannequin_Body', 'Mannequin_Briefs']),
        );
        expect(viewer.cameraControls, true);
        expect(viewer.disableZoom, false);
        expect(viewer.autoRotate, false);
        expect(viewer.cameraTarget, 'auto auto auto');
        expect(viewer.scale, '1 1 1');
        expect(viewer.environmentImage, 'neutral');
        expect(viewer.relatedJs, contains("viewer.addEventListener('error'"));
      },
    );
  }

  for (final corrupt in [false, true]) {
    testWidgets(
      '${corrupt ? 'corrupt' : 'missing'} GLB shows retry without a substitute model',
      (tester) async {
        final bundle = MissingModelBundle(corrupt: corrupt);
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(
                body: MannequinViewer(presentation: 'female'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Le mannequin 3D est indisponible.'), findsOneWidget);
        final attempts = bundle.attempts;
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();
        expect(bundle.attempts, greaterThan(attempts));
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('unknown profile cannot select an arbitrary asset path', () {
    expect(() => MannequinViewer.assetFor('../other'), throwsArgumentError);
  });
}
