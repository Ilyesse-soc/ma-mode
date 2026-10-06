import 'dart:convert';
import 'dart:typed_data';

import 'package:alamode/core/models.dart';
import 'package:alamode/core/network/api_client.dart';
import 'package:alamode/core/providers.dart';
import 'package:alamode/features/home/home_screen.dart';
import 'package:alamode/features/location/location_controller.dart';
import 'package:alamode/features/mannequin/mannequin_screen.dart';
import 'package:alamode/features/mannequin/mannequin_viewer.dart';
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
      '$presentation preview uses the original GLB even with selected clothing',
      () async {
        final viewer = MannequinViewer(
          presentation: presentation,
          garments: [
            piece('top', 'top', 'tshirt', 'blue'),
            piece('bottom', 'bottom', 'jeans', 'black'),
          ],
        ).createViewer();
        expect(viewer.src, 'assets/3d/mannequins/$presentation.glb');
        expect(viewer.src.startsWith('data:'), false);
        final bytes = await rootBundle.load(viewer.src);
        final document =
            jsonDecode(
                  utf8.decode(
                    bytes.buffer.asUint8List(
                      bytes.offsetInBytes + 20,
                      bytes.getUint32(12, Endian.little),
                    ),
                  ),
                )
                as Map;
        expect((document['meshes'] as List).map((m) => m['name']), [
          'Mannequin_Body',
          'Mannequin_Briefs',
        ]);
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
