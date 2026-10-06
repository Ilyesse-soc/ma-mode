import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alamode/core/models.dart';
import 'package:alamode/features/mannequin/clothing_spec.dart';
import 'package:alamode/features/mannequin/dressing_controller.dart';
import 'package:alamode/features/mannequin/mannequin_viewer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Garment item(String id, String slug, String group, String color) => Garment(
  id: id,
  name: id,
  color: color,
  category: GarmentCategory(id: 1, slug: slug, label: slug, group: group),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reference look is built only from real owned items; missing slots stay empty',
    () {
      final hoodie = item('my-hoodie', 'hoodie', 'top', 'grey');
      final tee = item('my-tee', 'tshirt', 'top', 'white');
      expect(ClothingSpec.referenceGarments([]), isEmpty);
      expect(ClothingSpec.referenceGarments([tee, hoodie]), [hoodie]);
    },
  );
  test(
    'selection, replacement and removal drive the visible template and color',
    () {
      final jacket = item('jacket', 'jacket', 'top', 'black');
      final blue = item('old', 'hoodie', 'top', 'blue');
      final white = item('new', 'tshirt', 'top', 'white');
      final cargo = item('cargo', 'cargo', 'bottom', 'black');
      expect(ClothingSpec.forGarments([jacket, blue, cargo, white]), {
        'jacket': '#202124',
        'cargo': '#202124',
        'tshirt': '#e8e7e2',
      });
      expect(
        ClothingSpec.forGarments([jacket, cargo]),
        isNot(contains('tshirt')),
      );
    },
  );
  test(
    'wardrobe edits refresh clothing color; deleted IDs cannot remain saved',
    () {
      final selection = DressingSelection([
        item('a', 'hoodie', 'top', 'grey'),
        item('b', 'cargo', 'bottom', 'black'),
      ]);
      expect(
        selection.reconcile([
          item('a', 'hoodie', 'top', 'red'),
          item('b', 'cargo', 'bottom', 'black'),
        ]),
        false,
      );
      expect(ClothingSpec.forGarments(selection.items)['hoodie'], '#a34e48');
      expect(selection.reconcile([item('a', 'hoodie', 'top', 'red')]), true);
      expect(selection.items.map((g) => g.id), ['a']);
    },
  );
  test(
    'unsupported accessories stay photos; untrusted text cannot become script or an asset path',
    () {
      expect(
        ClothingSpec.templateFor(item('bag', 'bag', 'other', 'black')),
        isNull,
      );
      expect(
        ClothingSpec.colorFor('</script><img onerror=alert(1)>'),
        '#929498',
      );
      expect(ClothingSpec.colorFor('#abcdef'), '#abcdef');
      expect(
        () => MannequinViewer(
          presentation: '../male',
          garments: [item('x', 'hoodie', 'top', 'black')],
        ).sourceAsset,
        throwsArgumentError,
      );
    },
  );
  test('Web and native share the same clothing application code', () {
    final web = File('web/clothing-runtime.js').readAsStringSync();
    expect(
      web.replaceAll('\r\n', '\n'),
      contains('export ${ClothingSpec.runtime.trim()}'),
    );
    expect(
      web.replaceAll('\r\n', '\n'),
      contains('export ${ClothingSpec.controls.trim()}'),
    );
    expect(ClothingSpec.runtime, contains("material.setAlphaMode('MASK')"));
    expect(ClothingSpec.runtime, contains('chest: innerTop'));
    expect(ClothingSpec.controls, contains('viewer.resetTurntableRotation(0)'));
  });
  for (final sex in ['male', 'female']) {
    test(
      '$sex dressing contains real fitted meshes and byte-preserves the supplied body',
      () async {
        final original = await rootBundle.load('assets/3d/mannequins/$sex.glb');
        final dressed = await rootBundle.load(
          'assets/3d/clothing/$sex-dressing.glb',
        );
        Map document(ByteData bytes) =>
            jsonDecode(
                  utf8.decode(
                    bytes.buffer.asUint8List(
                      bytes.offsetInBytes + 20,
                      bytes.getUint32(12, Endian.little),
                    ),
                  ),
                )
                as Map;
        final oldDoc = document(original), newDoc = document(dressed);
        expect((newDoc['meshes'] as List).take(2).toList(), oldDoc['meshes']);
        final oldBinOffset = 28 + original.getUint32(12, Endian.little);
        final newBinOffset = 28 + dressed.getUint32(12, Endian.little);
        final binLength = original.getUint32(oldBinOffset - 8, Endian.little);
        expect(
          dressed.buffer.asUint8List(
            dressed.offsetInBytes + newBinOffset,
            binLength,
          ),
          original.buffer.asUint8List(
            original.offsetInBytes + oldBinOffset,
            binLength,
          ),
        );
        final materials = (newDoc['materials'] as List).cast<Map>();
        for (final kind in ['hoodie', 'jacket', 'cargo', 'sneakers']) {
          final matching = materials.where(
            (m) => (m['name'] as String).startsWith('cloth:$kind:'),
          );
          expect(matching, isNotEmpty);
          for (final material in matching) {
            expect(material['alphaMode'], 'MASK');
            expect(material['pbrMetallicRoughness']['baseColorFactor'][3], 0);
          }
        }
        expect(
          materials.map((m) => m['name']),
          containsAll(['body:chest', 'body:torso', 'body:briefs']),
        );
        expect(dressed.lengthInBytes, lessThan(6 * 1024 * 1024));
      },
    );
  }
}
