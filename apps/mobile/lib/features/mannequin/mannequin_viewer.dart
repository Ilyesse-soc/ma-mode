import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../core/models.dart';
import 'clothing_spec.dart';

/// Original body plus offline-authored clothing selected from the real wardrobe.
/// These meshes are a stylized preview, not a reconstruction of product photos.
class MannequinViewer extends StatefulWidget {
  static const controlsHeight = 60.0;
  const MannequinViewer({
    super.key,
    required this.presentation,
    this.garments = const [],
    this.height = 420,
  });

  final String presentation;
  final List<Garment> garments;
  final double height;

  static String assetFor(String presentation) => switch (presentation) {
    'male' => 'assets/3d/mannequins/male.glb',
    'female' => 'assets/3d/mannequins/female.glb',
    _ => throw ArgumentError.value(presentation, 'presentation'),
  };

  String get sourceAsset {
    final original = assetFor(presentation);
    return ClothingSpec.forGarments(garments).isEmpty
        ? original
        : 'assets/3d/clothing/$presentation-dressing.glb';
  }

  String get clothingSignature => ClothingSpec.encode(garments);

  static const statusHtml = '''
<div slot="progress-bar" style="position:absolute;inset:0;display:grid;place-items:center;color:#ede2ce;font:14px sans-serif;pointer-events:none">Chargement du mannequin…</div>
''';
  // Handles native WebView failures; web lifecycle uses web/mannequin-runtime.js.
  // Retry reloads this isolated viewer; no substitute mesh is displayed.
  static const statusJs = r'''
const viewer = document.querySelector('model-viewer');
const started = performance.now();
const failure = document.createElement('div');
failure.setAttribute('role', 'alert');
failure.style.cssText = 'display:none;position:absolute;inset:0;z-index:10;background:#191a1b;color:#ede2ce;font:14px sans-serif;text-align:center;align-items:center;justify-content:center;flex-direction:column;padding:24px;box-sizing:border-box';
const message = document.createElement('p');
message.textContent = 'Le mannequin 3D ne peut pas être affiché.';
const retry = document.createElement('button');
retry.textContent = 'Réessayer';
retry.style.cssText = 'background:#ede2ce;color:#191a1b;border:0;border-radius:24px;padding:12px 24px;cursor:pointer';
failure.append(message, retry);
document.body.append(failure);
const reset = document.createElement('button');
reset.textContent = 'Recentrer';
reset.setAttribute('aria-label', 'Réinitialiser la caméra du mannequin');
reset.style.cssText = 'position:absolute;right:12px;bottom:12px;z-index:2;background:#151517dd;color:#ede2ce;border:1px solid #393939;border-radius:18px;padding:10px 14px';
reset.addEventListener('click', () => { viewer.cameraOrbit = '0deg 90deg 105%'; viewer.cameraTarget = 'auto auto auto'; viewer.jumpCameraToGoal(); });
document.body.append(reset);
function showFailure() {
  viewer.style.visibility = 'hidden';
  failure.style.display = 'flex';
  viewer.dataset.loadState = 'error';
}
const timeout = setTimeout(showFailure, 45000);
viewer.addEventListener('error', () => { clearTimeout(timeout); showFailure(); });
viewer.addEventListener('load', () => {
  clearTimeout(timeout);
  viewer.querySelector('[slot="progress-bar"]').style.display = 'none';
  failure.style.display = 'none';
  viewer.style.visibility = 'visible';
  viewer.dataset.loadState = 'loaded';
  viewer.dataset.loadMs = String(Math.round(performance.now() - started));
});
retry.addEventListener('click', () => location.reload());
viewer.addEventListener('dblclick', () => { viewer.cameraOrbit = '0deg 90deg 105%'; viewer.cameraTarget = 'auto auto auto'; });
document.body.style.background = 'transparent';
''';

  /// Actual renderer settings, also used by regression tests.
  ModelViewer createViewer({String? source}) => ModelViewer(
    // model_viewer_plus does not propagate material config after initState.
    // Remount on a real clothing/color change; the GLB uses the renderer cache.
    key: ValueKey('$sourceAsset-$clothingSignature-${source?.hashCode ?? 0}'),
    src: kIsWeb && (source ?? sourceAsset).startsWith('assets/')
        ? 'assets/${source ?? sourceAsset}'
        : source ?? sourceAsset,
    alt: presentation == 'male' ? 'Mannequin homme' : 'Mannequin femme',
    cameraControls: true,
    disablePan: true,
    autoRotate: false,
    autoRotateDelay: 0,
    rotationPerSecond: '20deg',
    disableZoom: false,
    interactionPrompt: InteractionPrompt.none,
    loading: Loading.eager,
    cameraTarget: 'auto auto auto',
    cameraOrbit: '0deg 90deg 105%',
    minCameraOrbit: 'auto 25deg 45%',
    maxCameraOrbit: 'auto 155deg 180%',
    fieldOfView: '30deg',
    orientation: '0deg 0deg 0deg',
    scale: '1 1 1',
    environmentImage: 'neutral',
    exposure: 1.2,
    shadowIntensity: 0.4,
    shadowSoftness: 1,
    backgroundColor: Colors.transparent,
    debugLogging: false,
    innerModelViewerHtml:
        '$statusHtml<script type="application/json" data-clothing-config>$clothingSignature</script>',
    relatedJs:
        '$statusJs\n${ClothingSpec.runtime}\n${ClothingSpec.controls}\ninstallClothingControls(viewer, reset);\nfunction dress() { try { applyClothing(viewer); } catch (_) { viewer.dataset.clothingState = "error"; message.textContent = "Impossible de charger les vêtements 3D."; showFailure(); } }\nviewer.addEventListener("load", dress);\nif (viewer.loaded) dress();',
  );

  @override
  State<MannequinViewer> createState() => _MannequinViewerState();
}

class _MannequinViewerState extends State<MannequinViewer> {
  Future<String?>? _asset;

  Future<String?> _checkAsset() async {
    try {
      final bytes = await DefaultAssetBundle.of(
        context,
      ).load(widget.sourceAsset);
      final valid =
          bytes.lengthInBytes >= 20 &&
          bytes.getUint32(0, Endian.little) == 0x46546c67 &&
          bytes.getUint32(4, Endian.little) == 2 &&
          bytes.getUint32(8, Endian.little) == bytes.lengthInBytes;
      if (!valid) return null;
      return widget.sourceAsset;
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _asset = _checkAsset();
  }

  @override
  void didUpdateWidget(MannequinViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceAsset != widget.sourceAsset) {
      _asset = _checkAsset();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Mannequin 3D — fais glisser pour tourner à 360 degrés, pince pour zoomer',
    child: SizedBox(
      height: widget.height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF282622), Color(0xFF141517)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -.18),
                      radius: .85,
                      colors: [Color(0xFF55575A), Color(0xFF202123)],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: CustomPaint(painter: _DressingPainter()),
            ),
            FutureBuilder<String?>(
              future: _asset,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.data == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Le mannequin 3D est indisponible.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _asset = _checkAsset();
                            }),
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return widget.createViewer(source: snapshot.data);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _DressingPainter extends CustomPainter {
  const _DressingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final floor = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0xFF151617), Color(0xFF292A2C)],
          ).createShader(
            Rect.fromLTWH(0, size.height * .78, size.width, size.height * .22),
          );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .92),
        width: size.width * .6,
        height: size.height * .11,
      ),
      floor,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
