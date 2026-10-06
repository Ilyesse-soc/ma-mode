import '../../core/models.dart';

enum DressingDropZone { head, torso, wrists, waist, legs, feet }

DressingDropZone dropZoneFor(Garment garment) {
  if (garment.category.group == 'top') return DressingDropZone.torso;
  if (garment.category.group == 'bottom') return DressingDropZone.legs;
  if (garment.category.group == 'shoes' || garment.category.slug == 'socks') {
    return DressingDropZone.feet;
  }
  if (garment.category.group == 'wrist') return DressingDropZone.wrists;
  if (garment.category.group == 'head' || garment.category.slug == 'scarf') {
    return DressingDropZone.head;
  }
  return DressingDropZone.waist;
}

/// Single source of truth for current outfit slots, used by tap and drag alike.
class DressingSelection {
  DressingSelection(Iterable<Garment> initial) {
    for (final garment in initial) {
      select(garment);
    }
  }
  final Map<String, Garment> _items = {};
  List<Garment> get items => _items.values.toList();
  static const outerSlugs = {'jacket', 'blazer', 'coat', 'puffer', 'cardigan'};
  static String slot(Garment garment) {
    if (outerSlugs.contains(garment.category.slug)) return 'outer';
    if (garment.category.group == 'head') {
      if ({'glasses', 'sunglasses'}.contains(garment.category.slug)) {
        return 'face';
      }
      if (garment.category.slug == 'earrings') return 'ears';
    }
    if (garment.category.group == 'other') return garment.category.slug;
    return garment.category.group;
  }

  void select(Garment garment) {
    if (garment.category.slug == 'dress') {
      _items.remove('top');
      _items.remove('bottom');
    }
    if (garment.category.group == 'top' &&
        !outerSlugs.contains(garment.category.slug) &&
        _items['bottom']?.category.slug == 'dress') {
      _items.remove('bottom');
    }
    _items[slot(garment)] = garment;
  }

  void remove(String id) => _items.removeWhere((_, g) => g.id == id);
  bool contains(String id) => _items.values.any((g) => g.id == id);

  /// Refresh selected objects after a wardrobe edit or deletion, retaining IDs.
  bool reconcile(Iterable<Garment> wardrobe) {
    final oldIds = items.map((g) => g.id).toList();
    final fresh = {for (final garment in wardrobe) garment.id: garment};
    _items.clear();
    for (final id in oldIds) {
      if (fresh[id] case final Garment garment) select(garment);
    }
    final newIds = items.map((g) => g.id).toSet();
    return oldIds.length != newIds.length ||
        oldIds.any((id) => !newIds.contains(id));
  }

  bool drop(Garment garment, DressingDropZone zone) {
    if (dropZoneFor(garment) != zone) return false;
    select(garment);
    return true;
  }
}
