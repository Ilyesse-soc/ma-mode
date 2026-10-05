import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Builds an in-memory level-1 visualization; source GLB assets are never edited.
/// Generic garment surfaces follow the supplied body and wardrobe category/color.
class OutfitComposer {
  static Uint8List compose(
    Uint8List input,
    List<Map<String, String>> garments,
  ) {
    final header = ByteData.sublistView(input);
    if (header.getUint32(0, Endian.little) != 0x46546c67) {
      throw const FormatException('Invalid mannequin');
    }
    final jsonSize = header.getUint32(12, Endian.little);
    final document =
        jsonDecode(utf8.decode(input.sublist(20, 20 + jsonSize)))
            as Map<String, dynamic>;
    final binOffset = 28 + jsonSize;
    final binary = input.sublist(binOffset);
    final source = ByteData.sublistView(binary);
    final views = document['bufferViews'] as List;
    final accessors = document['accessors'] as List;
    final meshes = document['meshes'] as List;
    final body = meshes.firstWhere(
      (m) => m['name'] == 'Mannequin_Body',
    )['primitives'][0];
    final positions = accessors[body['attributes']['POSITION']] as Map;
    final normalIndex = body['attributes']['NORMAL'];
    final Map? normals = normalIndex == null
        ? null
        : accessors[normalIndex] as Map;
    final indexAccessor = accessors[body['indices']] as Map;
    final indexView = views[indexAccessor['bufferView']] as Map;
    final indexBase =
        (indexView['byteOffset'] as int? ?? 0) +
        (indexAccessor['byteOffset'] as int? ?? 0);
    final boundsMin = (positions['min'] as List).cast<num>();
    final boundsMax = (positions['max'] as List).cast<num>();
    final floor = boundsMin[1].toDouble();
    final height = (boundsMax[1] - boundsMin[1]).toDouble();
    final chunks = BytesBuilder(copy: false)..add(binary);
    var byteLength = binary.length;
    int append(Uint8List bytes, int target) {
      final padding = (4 - byteLength % 4) % 4;
      if (padding > 0) {
        chunks.add(Uint8List(padding));
        byteLength += padding;
      }
      final index = views.length;
      views.add({
        'buffer': 0,
        'byteOffset': byteLength,
        'byteLength': bytes.length,
        'target': target,
      });
      chunks.add(bytes);
      byteLength += bytes.length;
      return index;
    }

    double component(Map accessor, int vertex, int axis) {
      final view = views[accessor['bufferView']] as Map;
      final offset =
          (view['byteOffset'] as int? ?? 0) +
          (accessor['byteOffset'] as int? ?? 0) +
          vertex * (view['byteStride'] as int? ?? 12) +
          axis * 4;
      return source.getFloat32(offset, Endian.little);
    }

    int sourceIndex(int i) => indexAccessor['componentType'] == 5125
        ? source.getUint32(indexBase + i * 4, Endian.little)
        : source.getUint16(indexBase + i * 2, Endian.little);
    final computedNormals = Float64List((positions['count'] as int) * 3);
    if (normals == null) {
      for (var i = 0; i < indexAccessor['count']; i += 3) {
        final a = sourceIndex(i),
            b = sourceIndex(i + 1),
            c = sourceIndex(i + 2);
        final ux = component(positions, b, 0) - component(positions, a, 0);
        final uy = component(positions, b, 1) - component(positions, a, 1);
        final uz = component(positions, b, 2) - component(positions, a, 2);
        final vx = component(positions, c, 0) - component(positions, a, 0);
        final vy = component(positions, c, 1) - component(positions, a, 1);
        final vz = component(positions, c, 2) - component(positions, a, 2);
        for (final vertex in [a, b, c]) {
          computedNormals[vertex * 3] += uy * vz - uz * vy;
          computedNormals[vertex * 3 + 1] += uz * vx - ux * vz;
          computedNormals[vertex * 3 + 2] += ux * vy - uy * vx;
        }
      }
      for (var i = 0; i < computedNormals.length; i += 3) {
        final length = math.sqrt(
          computedNormals[i] * computedNormals[i] +
              computedNormals[i + 1] * computedNormals[i + 1] +
              computedNormals[i + 2] * computedNormals[i + 2],
        );
        if (length > 0) {
          for (var axis = 0; axis < 3; axis++) {
            computedNormals[i + axis] /= length;
          }
        }
      }
    }
    void addGeometry(
      String name,
      List<double> p,
      List<double> n,
      List<int> indices,
      int material,
    ) {
      if (indices.isEmpty) return;
      final count = p.length ~/ 3;
      final minimum = List<double>.filled(3, double.infinity);
      final maximum = List<double>.filled(3, -double.infinity);
      for (var i = 0; i < p.length; i++) {
        minimum[i % 3] = math.min(minimum[i % 3], p[i]);
        maximum[i % 3] = math.max(maximum[i % 3], p[i]);
      }
      final pa = accessors.length;
      accessors.add({
        'bufferView': append(
          Float32List.fromList(p).buffer.asUint8List(),
          34962,
        ),
        'componentType': 5126,
        'count': count,
        'type': 'VEC3',
        'min': minimum,
        'max': maximum,
      });
      final na = accessors.length;
      accessors.add({
        'bufferView': append(
          Float32List.fromList(n).buffer.asUint8List(),
          34962,
        ),
        'componentType': 5126,
        'count': count,
        'type': 'VEC3',
      });
      final ia = accessors.length;
      accessors.add({
        'bufferView': append(
          Uint32List.fromList(indices).buffer.asUint8List(),
          34963,
        ),
        'componentType': 5125,
        'count': indices.length,
        'type': 'SCALAR',
      });
      final mesh = meshes.length;
      meshes.add({
        'name': name,
        'primitives': [
          {
            'attributes': {'POSITION': pa, 'NORMAL': na},
            'indices': ia,
            'material': material,
          },
        ],
      });
      final nodes = document['nodes'] as List;
      final node = nodes.length;
      nodes.add({'name': name, 'mesh': mesh});
      (document['scenes'][document['scene'] ?? 0]['nodes'] as List).add(node);
    }

    for (final garment in garments) {
      final slug = garment['slug']!;
      final group = garment['group']!;
      final color = colorFor(garment['color']!);
      final materials = document['materials'] as List;
      final material = materials.length;
      materials.add({
        'name': 'Generic wardrobe color',
        'doubleSided': true,
        'pbrMetallicRoughness': {
          'baseColorFactor': [...color, 1.0],
          'metallicFactor': 0.0,
          'roughnessFactor': 0.9,
        },
      });
      void ellipsoid(
        String suffix,
        double x,
        double y,
        double z,
        double rx,
        double ry,
        double rz,
      ) {
        final ep = <double>[], en = <double>[], ei = <int>[];
        for (var ring = 0; ring <= 16; ring++) {
          final phi = math.pi * ring / 16;
          for (var j = 0; j < 24; j++) {
            final theta = math.pi * 2 * j / 24;
            final nx = math.sin(phi) * math.cos(theta);
            final ny = math.cos(phi);
            final nz = math.sin(phi) * math.sin(theta);
            ep.addAll([
              height * (x + rx * nx),
              floor + height * (y + ry * ny),
              height * (z + rz * nz),
            ]);
            en.addAll([nx, ny, nz]);
            if (ring < 16) {
              final a = ring * 24 + j, b = ring * 24 + (j + 1) % 24;
              ei.addAll([a, b, a + 24, b, b + 24, a + 24]);
            }
          }
        }
        addGeometry(
          'Dressly_Generic_${suffix}_${garment['id']}',
          ep,
          en,
          ei,
          material,
        );
      }

      if (slug == 'bag') {
        ellipsoid('Bag', -0.17, 0.42, 0.07, 0.055, 0.07, 0.035);
      }
      if (slug == 'earrings') {
        for (final side in [-1, 1]) {
          ellipsoid(
            'Earring_$side',
            side * 0.052,
            0.908,
            0.02,
            0.006,
            0.015,
            0.006,
          );
        }
      }
      if (slug == 'watch') {
        ellipsoid('Watch', 0.145, 0.445, 0.054, 0.018, 0.017, 0.006);
      }
      if (slug == 'jewelry' || slug == 'misc_accessory') {
        ellipsoid('Pendant', 0, 0.78, 0.104, 0.01, 0.016, 0.004);
      }
      final outer = {
        'jacket',
        'blazer',
        'coat',
        'puffer',
        'cardigan',
      }.contains(slug);
      final shortSleeve = {'tshirt', 'polo', 'top_other'}.contains(slug);
      bool contains(double x, double y, double z) {
        final h = (y - floor) / height;
        final width = x.abs() / height;
        if (group == 'top' || slug == 'dress') {
          return h < 0.85 &&
              (width < 0.112
                  ? h > (outer ? 0.49 : 0.55)
                  : h > (shortSleeve ? 0.73 : 0.45));
        }
        if (group == 'bottom') {
          return slug != 'skirt' &&
              h > (slug == 'shorts' ? 0.35 : 0.065) &&
              h < 0.61 &&
              width < 0.12;
        }
        if (group == 'shoes') return h < (slug == 'boots' ? 0.17 : 0.065);
        if (group == 'head') {
          return !{'glasses', 'sunglasses', 'earrings'}.contains(slug) &&
              h > 0.965;
        }
        if (group == 'wrist') return h > 0.43 && h < 0.46 && x > height * 0.12;
        if (slug == 'belt') return h > 0.575 && h < 0.595 && width < 0.12;
        if (slug == 'socks') return h > 0.035 && h < 0.17 && width < 0.12;
        if (slug == 'scarf') return h > 0.8 && h < 0.855 && width < 0.09;
        return false;
      }

      final p = <double>[], n = <double>[], indices = <int>[];
      final vertexMap = <int, int>{};
      int vertex(int sourceVertex) => vertexMap.putIfAbsent(sourceVertex, () {
        final id = p.length ~/ 3;
        for (var axis = 0; axis < 3; axis++) {
          final normal = normals == null
              ? computedNormals[sourceVertex * 3 + axis]
              : component(normals, sourceVertex, axis);
          p.add(
            component(positions, sourceVertex, axis) +
                normal *
                    (outer
                        ? 0.045
                        : group == 'bottom'
                        ? 0.035
                        : 0.018),
          );
          n.add(normal);
        }
        return id;
      });
      for (var triangle = 0; triangle < indexAccessor['count']; triangle += 3) {
        final vertices = [
          sourceIndex(triangle),
          sourceIndex(triangle + 1),
          sourceIndex(triangle + 2),
        ];
        if (vertices.every(
          (i) => contains(
            component(positions, i, 0),
            component(positions, i, 1),
            component(positions, i, 2),
          ),
        )) {
          indices.addAll(vertices.map(vertex));
        }
      }
      addGeometry('Dressly_Generic_${garment['id']}', p, n, indices, material);
      if (group == 'top' || slug == 'dress') {
        // A loose, smooth torso shell avoids presenting painted skin as fabric.
        // Sleeves still follow the supplied arms; the cut remains generic.
        final tp = <double>[], tn = <double>[], ti = <int>[];
        for (var ring = 0; ring < 10; ring++) {
          final t = ring / 9;
          final width = height * (0.108 + 0.012 * t + (outer ? 0.015 : 0));
          final depth = height * (0.09 + 0.01 * t + (outer ? 0.012 : 0));
          for (var j = 0; j < 48; j++) {
            final angle = j * math.pi * 2 / 48;
            tp.addAll([
              width * math.cos(angle),
              floor +
                  height * ((outer ? 0.49 : 0.55) + t * (outer ? 0.32 : 0.26)),
              depth * math.sin(angle),
            ]);
            tn.addAll([math.cos(angle), 0, math.sin(angle)]);
            if (ring < 9) {
              final a = ring * 48 + j, b = ring * 48 + (j + 1) % 48;
              ti.addAll([a, a + 48, b, b, a + 48, b + 48]);
            }
          }
        }
        addGeometry(
          'Dressly_Generic_Torso_${garment['id']}',
          tp,
          tn,
          ti,
          material,
        );
      }
      if (group == 'bottom' && slug != 'skirt' && slug != 'dress') {
        final hp = <double>[], hn = <double>[], hi = <int>[];
        for (var ring = 0; ring < 8; ring++) {
          final t = ring / 7;
          for (var j = 0; j < 48; j++) {
            final angle = j * math.pi * 2 / 48;
            hp.addAll([
              height * (0.105 + 0.008 * t) * math.cos(angle),
              floor + height * (0.46 + t * 0.15),
              height * 0.105 * math.sin(angle),
            ]);
            hn.addAll([math.cos(angle), 0, math.sin(angle)]);
            if (ring < 7) {
              final a = ring * 48 + j, b = ring * 48 + (j + 1) % 48;
              hi.addAll([a, a + 48, b, b, a + 48, b + 48]);
            }
          }
        }
        addGeometry(
          'Dressly_Generic_Hips_${garment['id']}',
          hp,
          hn,
          hi,
          material,
        );
      }
      if (slug == 'skirt' || slug == 'dress') {
        final skirtP = <double>[], skirtN = <double>[], skirtI = <int>[];
        for (var ring = 0; ring < 8; ring++) {
          final t = ring / 7;
          for (var j = 0; j < 48; j++) {
            final angle = j * math.pi * 2 / 48;
            skirtP.addAll([
              math.cos(angle) * height * (0.115 + t * 0.035),
              floor + height * (0.6 - t * 0.28),
              math.sin(angle) * height * (0.09 + t * 0.035),
            ]);
            skirtN.addAll([math.cos(angle), 0, math.sin(angle)]);
            if (ring < 7) {
              final a = ring * 48 + j, b = ring * 48 + (j + 1) % 48;
              skirtI.addAll([a, b, a + 48, b, b + 48, a + 48]);
            }
          }
        }
        addGeometry(
          'Dressly_Generic_Skirt_${garment['id']}',
          skirtP,
          skirtN,
          skirtI,
          material,
        );
      }
      if (slug == 'glasses' || slug == 'sunglasses') {
        final gp = <double>[], gn = <double>[], gi = <int>[];
        for (final side in [-1, 1]) {
          final base = gp.length ~/ 3;
          for (var a = 0; a < 32; a++) {
            final angle = a * math.pi * 2 / 32;
            for (var b = 0; b < 6; b++) {
              final tube = b * math.pi * 2 / 6;
              gp.addAll([
                height *
                    (side * 0.029 +
                        math.cos(angle) * (0.022 + 0.002 * math.cos(tube))),
                floor +
                    height *
                        (0.914 +
                            math.sin(angle) * (0.013 + 0.002 * math.cos(tube))),
                height * (0.078 + math.sin(tube) * 0.002),
              ]);
              gn.addAll([
                math.cos(angle) * math.cos(tube),
                math.sin(angle) * math.cos(tube),
                math.sin(tube),
              ]);
              final i = base + a * 6 + b,
                  j = base + ((a + 1) % 32) * 6 + b,
                  k = base + a * 6 + (b + 1) % 6,
                  l = base + ((a + 1) % 32) * 6 + (b + 1) % 6;
              gi.addAll([i, j, k, j, l, k]);
            }
          }
        }
        addGeometry(
          'Dressly_Generic_Glasses_${garment['id']}',
          gp,
          gn,
          gi,
          material,
        );
      }
    }
    final binPadding = (4 - byteLength % 4) % 4;
    if (binPadding > 0) {
      chunks.add(Uint8List(binPadding));
      byteLength += binPadding;
    }
    document['buffers'][0]['byteLength'] = byteLength;
    final jsonBytes = utf8.encode(jsonEncode(document));
    final paddedJson = Uint8List((jsonBytes.length + 3) ~/ 4 * 4)
      ..fillRange(0, (jsonBytes.length + 3) ~/ 4 * 4, 32)
      ..setRange(0, jsonBytes.length, jsonBytes);
    final output = BytesBuilder(copy: false);
    final outHeader = ByteData(20)
      ..setUint32(0, 0x46546c67, Endian.little)
      ..setUint32(4, 2, Endian.little)
      ..setUint32(8, 28 + paddedJson.length + byteLength, Endian.little)
      ..setUint32(12, paddedJson.length, Endian.little)
      ..setUint32(16, 0x4E4F534A, Endian.little);
    final binHeader = ByteData(8)
      ..setUint32(0, byteLength, Endian.little)
      ..setUint32(4, 0x004E4942, Endian.little);
    output
      ..add(outHeader.buffer.asUint8List())
      ..add(paddedJson)
      ..add(binHeader.buffer.asUint8List())
      ..add(chunks.takeBytes());
    return output.takeBytes();
  }

  static List<double> colorFor(String value) {
    const colors = {
      'black': 0x222226,
      'noir': 0x222226,
      'white': 0xF2F0EA,
      'blanc': 0xF2F0EA,
      'grey': 0x85888C,
      'gray': 0x85888C,
      'gris': 0x85888C,
      'blue': 0x365D88,
      'bleu': 0x365D88,
      'beige': 0xBAA88C,
      'brown': 0x76563F,
      'marron': 0x76563F,
      'red': 0x993F45,
      'rouge': 0x993F45,
      'green': 0x4F6A54,
      'vert': 0x4F6A54,
      'pink': 0xC68E9C,
      'rose': 0xC68E9C,
      'navy': 0x29344B,
    };
    final key = value.toLowerCase().trim();
    final rgb =
        colors[key] ??
        (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(key)
            ? int.parse(key.substring(1), radix: 16)
            : 0x8B8983);
    // glTF factors are linear RGB, unlike UI sRGB colors.
    double linear(int channel) {
      final x = channel / 255;
      return x <= 0.04045
          ? x / 12.92
          : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }

    return [
      linear((rgb >> 16) & 255),
      linear((rgb >> 8) & 255),
      linear(rgb & 255),
    ];
  }
}
