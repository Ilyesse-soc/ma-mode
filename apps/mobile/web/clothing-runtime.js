// Mirrored from ClothingSpec; a regression test checks parity.
export function applyClothing(viewer) {
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

export function installClothingControls(viewer, reset) {
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
