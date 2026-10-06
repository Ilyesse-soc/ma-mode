// model_viewer_plus web inserts markup via innerHTML: embedded scripts do not run.
// Load the already bundled renderer and attach lifecycle handlers to each real view.
import './assets/packages/model_viewer_plus/assets/model-viewer.min.js';

const initialized = new WeakSet();
const active = new Map();

function attach(viewer) {
  if (initialized.has(viewer)) return;
  initialized.add(viewer);
  const parent = viewer.parentElement;
  parent.style.position = 'relative';
  const failure = document.createElement('div');
  failure.setAttribute('role', 'alert');
  failure.style.cssText = 'display:none;position:absolute;inset:0;z-index:10;background:#191a1b;color:#ede2ce;font:14px sans-serif;align-items:center;justify-content:center;flex-direction:column;text-align:center;padding:24px;box-sizing:border-box';
  const message = document.createElement('p');
  message.textContent = 'Le mannequin 3D ne peut pas être affiché.';
  const retry = document.createElement('button');
  retry.textContent = 'Réessayer';
  retry.style.cssText = 'background:#ede2ce;color:#191a1b;border:0;border-radius:24px;padding:12px 24px;cursor:pointer';
  failure.append(message, retry);
  parent.append(failure);
  const reset = document.createElement('button');
  reset.textContent = 'Recentrer';
  reset.setAttribute('aria-label', 'Réinitialiser la caméra du mannequin');
  reset.style.cssText = 'position:absolute;right:12px;bottom:12px;z-index:2;background:#151517dd;color:#ede2ce;border:1px solid #393939;border-radius:18px;padding:10px 14px;cursor:pointer';
  reset.addEventListener('click', () => {
    viewer.cameraOrbit = '0deg 90deg 105%';
    viewer.cameraTarget = 'auto auto auto';
    viewer.jumpCameraToGoal();
  });
  parent.append(reset);
  let timeout, started;
  const progress = viewer.querySelector('[slot="progress-bar"]');
  const failed = () => {
    clearTimeout(timeout);
    viewer.dataset.loadState = 'error';
    failure.style.display = 'flex';
    if (progress) progress.style.display = 'none';
  };
  const ready = () => {
    clearTimeout(timeout);
    viewer.dataset.loadState = 'loaded';
    viewer.dataset.loadMs = String(Math.round(performance.now() - started));
    failure.style.display = 'none';
    if (progress) progress.style.display = 'none';
  };
  const start = () => {
    clearTimeout(timeout);
    started = performance.now();
    viewer.dataset.loadState = 'loading';
    if (progress) progress.style.display = 'grid';
    failure.style.display = 'none';
    timeout = setTimeout(failed, 45000);
  };
  viewer.addEventListener('load', ready);
  viewer.addEventListener('error', failed);
  viewer.addEventListener('dblclick', () => {
    viewer.cameraOrbit = '0deg 90deg 105%';
    viewer.cameraTarget = 'auto auto auto';
  });
  retry.addEventListener('click', () => {
    const source = viewer.src;
    start();
    viewer.src = '';
    requestAnimationFrame(() => { viewer.src = source; });
  });
  active.set(viewer, () => { clearTimeout(timeout); reset.remove(); failure.remove(); });
  start();
  if (viewer.loaded) ready();
}

function update() {
  document.querySelectorAll('model-viewer').forEach(attach);
  for (const [viewer, cancel] of active) {
    if (!viewer.isConnected) { cancel(); active.delete(viewer); }
  }
}
new MutationObserver(update).observe(document.documentElement, {childList: true, subtree: true});
update();
