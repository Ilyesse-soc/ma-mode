import 'package:alamode/features/mannequin/dressing_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'product_ux_test.dart' show piece;

void main() {
  test(
    'incompatible drop preserves all slots; compatible drop changes one',
    () {
      final jeans = piece('jeans', 'bottom', 'jeans', 'blue');
      final old = piece('old', 'top', 'tshirt', 'white');
      final next = piece('new', 'top', 'hoodie', 'black');
      final selection = DressingSelection([jeans, old]);
      expect(selection.drop(next, DressingDropZone.feet), isFalse);
      expect(selection.items.map((g) => g.id), ['jeans', 'old']);
      expect(selection.drop(next, DressingDropZone.torso), isTrue);
      expect(selection.items.map((g) => g.id), ['jeans', 'new']);
      selection.remove('new');
      expect(selection.items.map((g) => g.id), ['jeans']);
    },
  );
  test('head, wrist, shoe and belt drops use distinct target regions', () {
    expect(
      dropZoneFor(piece('cap', 'head', 'cap', 'black')),
      DressingDropZone.head,
    );
    expect(
      dropZoneFor(piece('watch', 'wrist', 'watch', 'silver')),
      DressingDropZone.wrists,
    );
    expect(
      dropZoneFor(piece('shoe', 'shoes', 'sneakers', 'white')),
      DressingDropZone.feet,
    );
    expect(
      dropZoneFor(piece('belt', 'other', 'belt', 'black')),
      DressingDropZone.waist,
    );
  });
}
