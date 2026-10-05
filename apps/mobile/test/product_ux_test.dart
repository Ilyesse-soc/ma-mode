import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alamode/core/models.dart';
import 'package:alamode/core/network/api_client.dart';
import 'package:alamode/core/providers.dart';
import 'package:alamode/features/home/home_screen.dart';
import 'package:alamode/features/location/location_controller.dart';
import 'package:alamode/features/mannequin/mannequin_screen.dart';
import 'package:alamode/features/mannequin/outfit_composer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'user_flows_test.dart' show MemoryTokens, ContractAdapter;

Garment piece(String id, String group, String slug, String color) => Garment(
  id: id,
  name: id,
  color: color,
  category: GarmentCategory(id: 1, slug: slug, label: slug, group: group),
);

class PoissyLocation extends LocationController {
  @override
  LocationState build() => const LocationState(
    permission: LocationPermissionState.granted,
    latitude: 48.9295123,
    longitude: 2.0453123,
    label: 'Poissy',
    administrativeArea: 'Yvelines',
    accuracyMeters: 12,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'replacing one piece preserves the other slots, removal is explicit',
    () {
      final bottom = piece('jeans', 'bottom', 'jeans', 'blue');
      final shoes = piece('shoes', 'shoes', 'sneakers', 'white');
      final selection = DressingSelection([
        piece('old', 'top', 'hoodie', 'grey'),
        bottom,
        shoes,
      ]);
      selection.select(piece('new', 'top', 'tshirt', 'black'));
      expect(
        selection.items.map((g) => g.id),
        containsAll(['new', 'jeans', 'shoes']),
      );
      expect(selection.contains('old'), false);
      selection.remove('new');
      expect(selection.items.map((g) => g.id), ['jeans', 'shoes']);
    },
  );
  test('a dress replaces separate top/bottom while jacket remains a layer', () {
    final selection = DressingSelection([
      piece('top', 'top', 'tshirt', 'white'),
      piece('bottom', 'bottom', 'jeans', 'blue'),
      piece('jacket', 'top', 'jacket', 'black'),
    ]);
    selection.select(piece('dress', 'bottom', 'dress', 'beige'));
    expect(selection.items.map((g) => g.id), containsAll(['jacket', 'dress']));
    expect(selection.items.length, 2);
  });
  for (final presentation in ['male', 'female']) {
    test(
      '$presentation composition preserves supplied meshes and adds real generic geometry',
      () async {
        final bytes = await rootBundle.load(
          'assets/3d/mannequins/$presentation.glb',
        );
        final original = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        final derived = OutfitComposer.compose(original, [
          {'id': 'top', 'slug': 'tshirt', 'group': 'top', 'color': 'blue'},
          {'id': 'jeans', 'slug': 'jeans', 'group': 'bottom', 'color': 'black'},
          {
            'id': 'shoes',
            'slug': 'sneakers',
            'group': 'shoes',
            'color': 'white',
          },
        ]);
        final header = ByteData.sublistView(derived);
        expect(header.getUint32(8, Endian.little), derived.length);
        final jsonLength = header.getUint32(12, Endian.little);
        final document =
            jsonDecode(utf8.decode(derived.sublist(20, 20 + jsonLength)))
                as Map;
        final meshes = document['meshes'] as List;
        expect(
          meshes.map((m) => m['name']),
          containsAll([
            'Mannequin_Body',
            'Mannequin_Briefs',
            'Dressly_Generic_top',
            'Dressly_Generic_jeans',
            'Dressly_Generic_shoes',
          ]),
        );
        for (final mesh in meshes.skip(2)) {
          final accessor =
              document['accessors'][mesh['primitives'][0]['indices']];
          expect(accessor['count'], greaterThan(30));
        }
        final originalBin = original.sublist(
          28 + bytes.getUint32(12, Endian.little),
        );
        expect(
          derived.sublist(
            28 + jsonLength,
            28 + jsonLength + originalBin.length,
          ),
          originalBin,
        );
        // Ignored local artifact used for the real browser rendering check.
        final output = File('../../.tmp/dressing-$presentation.glb');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(derived);
      },
    );
  }
  test(
    'weather receives precise Poissy coordinates, never a Paris fallback',
    () async {
      final client = ApiClient(MemoryTokens());
      final adapter = ContractAdapter((options) {
        expect(options.queryParameters['latitude'], 48.9295123);
        expect(options.queryParameters['longitude'], 2.0453123);
        expect(options.queryParameters['location_label'], 'Poissy');
        return (
          200,
          {
            'latitude': 48.9295123,
            'longitude': 2.0453123,
            'provider': 'test',
            'current': {
              'timestamp': 1791220000,
              'temperature_c': 13,
              'feels_like_c': 11,
              'precip_probability': 0,
              'wind_kmh': 4,
              'humidity_pct': 50,
              'condition': 'clear',
            },
            'hourly': [],
          },
        );
      });
      client.dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          tokenStorageProvider.overrideWithValue(MemoryTokens()),
          locationControllerProvider.overrideWith(PoissyLocation.new),
        ],
      );
      addTearDown(container.dispose);
      final report = await container.read(currentWeatherProvider.future);
      expect(report?.current.temperatureC, 13);
      expect(adapter.calls, isNotEmpty);
    },
  );
}
