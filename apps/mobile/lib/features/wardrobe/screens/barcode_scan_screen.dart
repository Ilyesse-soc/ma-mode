import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

/// Barcode scanner: EAN/UPC and other common formats via mobile_scanner.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );
  bool _handled = false;
  bool _busy = false;
  String? _error;

  void _detect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && RegExp(r'^[0-9A-Za-z\-]{6,32}$').hasMatch(value)) {
        _handled = true;
        context.pop(value);
        return;
      }
    }
  }

  Future<void> _cameraAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Cette commande est indisponible sur la caméra actuelle.',
        );
      }
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.stop();
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final capture = await _controller.analyzeImage(image.path);
      if (capture != null) _detect(capture);
      if (mounted && !_handled) {
        setState(
          () => _error =
              'Aucun code-barres lisible. Reprends une photo ou saisis le code.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Lecture de cette image indisponible. Tu peux saisir le code-barres.',
        );
      }
    } finally {
      if (mounted && !_handled) {
        setState(() => _busy = false);
        await _cameraAction(() => _controller.start());
      }
    }
  }

  Future<void> _manualCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _cameraAction(() => _controller.stop());
    if (!mounted) return;
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saisir le code-barres'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Code imprimé sur l’étiquette',
            ),
            validator: (value) =>
                RegExp(r'^[0-9A-Za-z\-]{6,32}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Saisis un code de 6 à 32 caractères',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
    // The dialog field is unmounted after its closing transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (value != null && mounted && !_handled) {
      _handled = true;
      context.pop(value);
    } else if (mounted) {
      setState(() => _busy = false);
      await _cameraAction(() => _controller.start());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un code-barres'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_outlined),
            tooltip: 'Flash',
            onPressed: _busy
                ? null
                : () => _cameraAction(() => _controller.toggleTorch()),
          ),
          IconButton(
            tooltip: 'Changer caméra',
            icon: const Icon(Icons.flip_camera_ios_outlined),
            onPressed: _busy
                ? null
                : () => _cameraAction(() => _controller.switchCamera()),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (!_busy) _detect(capture);
            },
            errorBuilder: (_, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'La caméra est indisponible. Vérifie son autorisation, choisis une image ou saisis le code-barres.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF57C4DC), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  const Text(
                    'Cadre le code-barres de l\'étiquette',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Lire une image',
                        onPressed: _busy ? null : _gallery,
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _manualCode,
                        child: const Text('Saisir le code'),
                      ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
