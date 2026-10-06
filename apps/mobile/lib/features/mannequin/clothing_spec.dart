import 'dart:convert';

import '../../core/models.dart';
import 'dressing_controller.dart';

/// Maps real wardrobe selections to fitted, authored meshes, never to photo claims.
class ClothingSpec {
  static String? templateFor(Garment garment) =>
      switch (garment.category.slug) {
        'tshirt' || 'polo' => 'tshirt',
        'hoodie' => 'hoodie',
        'shirt' || 'sweater' || 'top_other' => 'sweater',
        'cardigan' || 'jacket' || 'blazer' || 'coat' || 'puffer' => 'jacket',
        'cargo' => 'cargo',
        'jeans' || 'trousers' || 'joggers' || 'bottom_other' => 'trousers',
        'shorts' => 'shorts',
        'skirt' => 'skirt',
        'dress' => 'dress',
        'sneakers' || 'shoes_other' || 'dress_shoes' => 'sneakers',
        'boots' => 'boots',
        _ => null,
      };

  static const _colors = {
    'black': '#202124',
    'noir': '#202124',
    'white': '#e8e7e2',
    'blanc': '#e8e7e2',
    'grey': '#929498',
    'gray': '#929498',
    'gris': '#929498',
    'dark_grey': '#45474b',
    'light_grey': '#c5c6c8',
    'navy': '#263247',
    'blue': '#487496',
    'bleu': '#487496',
    'light_blue': '#8ba7bc',
    'beige': '#c0ac8e',
    'cream': '#d9ceb9',
    'brown': '#765644',
    'marron': '#765644',
    'green': '#50694f',
    'vert': '#50694f',
    'khaki': '#73755a',
    'olive': '#73755a',
    'red': '#a34e48',
    'rouge': '#a34e48',
    'burgundy': '#683e49',
    'pink': '#c392a3',
    'rose': '#c392a3',
    'purple': '#786280',
    'violet': '#786280',
    'orange': '#ba7a48',
    'yellow': '#c5b06b',
    'jaune': '#c5b06b',
  };

  static String colorFor(String color) {
    final normalized = color.trim().toLowerCase().replaceAll(' ', '_');
    if (RegExp(r'^#[a-f0-9]{6}$').hasMatch(normalized)) return normalized;
    return _colors[normalized] ?? '#929498';
  }

  static Map<String, String> forGarments(Iterable<Garment> garments) {
    final selected = DressingSelection(garments);
    return {
      for (final garment in selected.items)
        if (templateFor(garment) case final String template)
          template: colorFor(garment.color),
    };
  }

  static String encode(Iterable<Garment> garments) =>
      jsonEncode(forGarments(garments));

  /// Assemble the reference silhouette using only pieces owned by this account.
  /// No sample garment is inserted when a slot is missing from the wardrobe.
  static List<Garment> referenceGarments(Iterable<Garment> wardrobe) {
    final items = wardrobe.toList();
    final result = <Garment>[];
    void choose(List<String> slugs, String color) {
      final choices = items
          .where((g) => slugs.contains(g.category.slug))
          .toList();
      int score(Garment g) =>
          (slugs.length - slugs.indexOf(g.category.slug)) * 10 +
          (colorFor(g.color) == colorFor(color) ? 5 : 0);
      choices.sort((a, b) => score(b).compareTo(score(a)));
      if (choices.isNotEmpty) result.add(choices.first);
    }

    choose([
      'hoodie',
      'sweater',
      'shirt',
      'tshirt',
      'polo',
      'top_other',
    ], 'grey');
    choose(['jacket', 'blazer', 'cardigan', 'coat', 'puffer'], 'black');
    choose(['cargo', 'trousers', 'jeans', 'joggers', 'bottom_other'], 'black');
    choose(['sneakers', 'shoes_other', 'dress_shoes', 'boots'], 'white');
    return result;
  }

  // Static code is shared by the native WebView and the Web lifecycle adapter.
  // Only typed template/color values are embedded; garment names and URLs never are.
  static const controls = r'''
function installClothingControls(viewer, reset) {
  const parent = reset.parentElement;
  // Reserve a separate strip for controls; never cover the selected shoes.
  viewer.style.height = 'calc(100% - 60px)';
  const toolbar = document.createElement('div');
  toolbar.style.cssText = 'position:absolute;bottom:12px;left:72px;right:12px;z-index:2;display:flex;justify-content:center;gap:4px;padding:4px;border-radius:22px;background:#111214dd';
  function control(text, label, callback) {
    const button = document.createElement('button');
    button.textContent = text;
    button.setAttribute('aria-label', label);
    button.style.cssText = 'color:#ede2ce;background:transparent;border:0;border-radius:18px;padding:10px 8px;cursor:pointer;font:12px sans-serif;flex:1';
    button.addEventListener('click', callback);
    toolbar.append(button);
    return button;
  }
  const spin = control('360\u00b0', 'Rotation automatique du mannequin', () => {
    viewer.autoRotate = !viewer.autoRotate;
    spin.textContent = viewer.autoRotate ? 'Pause' : '360\u00b0';
    spin.setAttribute('aria-pressed', String(viewer.autoRotate));
  });
  control('Zoom', 'Zoomer sur la tenue', () => {
    const orbit = viewer.getCameraOrbit();
    viewer.cameraOrbit = `${orbit.theta}rad ${orbit.phi}rad ${orbit.radius * .82}m`;
  });
  reset.style.cssText = 'color:#ede2ce;background:transparent;border:0;border-radius:18px;padding:10px 8px;cursor:pointer;font:12px sans-serif;flex:1';
  reset.addEventListener('click', () => {
    viewer.autoRotate = false;
    viewer.resetTurntableRotation(0);
    spin.textContent = '360\u00b0';
    spin.setAttribute('aria-pressed', 'false');
  });
  viewer.addEventListener('dblclick', () => {
    viewer.autoRotate = false;
    viewer.resetTurntableRotation(0);
    spin.textContent = '360\u00b0';
    spin.setAttribute('aria-pressed', 'false');
  });
  toolbar.append(reset);
  parent.append(toolbar);
  return () => toolbar.remove();
}
''';

  static const runtime = r'''
function applyClothing(viewer) {
  const config = viewer.querySelector('[data-clothing-config]');
  if (!config || !viewer.model) return;
  const selected = JSON.parse(config.textContent);
  const visible = new Set(Object.keys(selected));
  const hasTop = ['tshirt', 'sweater', 'hoodie', 'dress', 'jacket'].some(k => visible.has(k));
  const innerTop = ['tshirt', 'sweater', 'hoodie', 'dress'].some(k => visible.has(k));
  const longSleeves = ['sweater', 'hoodie', 'jacket'].some(k => visible.has(k));
  const hasBottom = ['cargo', 'trousers', 'shorts', 'skirt', 'dress'].some(k => visible.has(k));
  const longPants = ['cargo', 'trousers'].some(k => visible.has(k));
  const hasShoes = ['sneakers', 'boots'].some(k => visible.has(k));
  const covered = {torso: hasTop, chest: innerTop, upperarms: longSleeves, forearms: longSleeves,
    pelvis: hasBottom, thighs: hasBottom, legs: longPants,
    feet: hasShoes, briefs: hasBottom};
  for (const material of viewer.model.materials) {
    if (material.name.startsWith('body:')) {
      const hidden = covered[material.name.split(':')[1]] === true;
      const pbr = material.pbrMetallicRoughness;
      const rgba = [...pbr.baseColorFactor];
      rgba[3] = hidden ? 0 : 1;
      material.setAlphaMode(hidden ? 'MASK' : 'OPAQUE');
      pbr.setBaseColorFactor(rgba);
      continue;
    }
    if (!material.name.startsWith('cloth:')) continue;
    const [, kind, detail] = material.name.split(':');
    const shown = visible.has(kind);
    const pbr = material.pbrMetallicRoughness;
    if (!shown) {
      material.setAlphaMode('MASK');
      pbr.setBaseColorFactor([0, 0, 0, 0]);
      continue;
    }
    material.setAlphaMode('OPAQUE');
    if (detail.startsWith('fixed')) {
      const value = detail.includes('zip') ? .15 : .76;
      pbr.setBaseColorFactor([value, value, value, 1]);
    } else {
      // API strings are sRGB, while numeric baseColorFactor values are linear.
      pbr.setBaseColorFactor(selected[kind]);
      if (detail === 'trim') {
        const rgba = [...pbr.baseColorFactor];
        for (let i = 0; i < 3; i++) rgba[i] *= .78;
        pbr.setBaseColorFactor(rgba);
      }
    }
  }
  viewer.dataset.clothingState = 'applied';
  viewer.dataset.clothingTemplates = [...visible].sort().join(',');
}
''';
}
