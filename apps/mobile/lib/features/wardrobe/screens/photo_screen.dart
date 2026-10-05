import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CapturedPhoto {
  const CapturedPhoto(this.bytes, this.name, {this.labelMode = false});
  final Uint8List bytes;
  final String name;
  final bool labelMode;
}

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key, this.labelMode = false});
  final bool labelMode;
  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  CapturedPhoto? _photo;
  bool _busy = false, _starting = true, _labelMode = false;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _labelMode = widget.labelMode;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  Future<void> _stopCamera() async {
    _epoch++;
    final camera = _camera;
    _camera = null;
    if (camera != null) await camera.dispose();
  }

  Future<void> _startCamera() async {
    final epoch = ++_epoch;
    CameraController? camera;
    if (mounted) {
      setState(() {
        _starting = true;
        _error = null;
      });
    }
    try {
      final cameras = await availableCameras();
      if (!mounted || epoch != _epoch) return;
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'Aucune caméra disponible');
      }
      final rear =
          cameras
              .where(
                (camera) => camera.lensDirection == CameraLensDirection.back,
              )
              .firstOrNull ??
          cameras.first;
      camera = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted || epoch != _epoch) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _starting = false;
      });
    } on CameraException catch (_) {
      await camera?.dispose();
      if (mounted && epoch == _epoch) {
        setState(() {
          _starting = false;
          _error =
              'Caméra indisponible. Vérifie son autorisation ou utilise la galerie.';
        });
      }
    } catch (_) {
      await camera?.dispose();
      if (mounted && epoch == _epoch) {
        setState(() {
          _starting = false;
          _error =
              'Impossible d’ouvrir la caméra. Tu peux utiliser la galerie.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed && _photo == null && !_busy) {
      unawaited(_startCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopCamera());
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy || camera == null || !camera.value.isInitialized) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await camera.takePicture();
      final bytes = await image.readAsBytes();
      await _stopCamera();
      if (mounted) {
        setState(
          () =>
              _photo = CapturedPhoto(bytes, image.name, labelMode: _labelMode),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'La photo n’a pas pu être prise. Réessaie.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _stopCamera();
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        if (mounted) {
          setState(
            () => _photo = CapturedPhoto(
              bytes,
              image.name,
              labelMode: _labelMode,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'La galerie est indisponible. Réessaie.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_photo == null) await _startCamera();
      }
    }
  }

  Widget _preview() {
    final camera = _camera;
    if (_photo != null) return Image.memory(_photo!.bytes, fit: BoxFit.contain);
    if (_starting) return const Center(child: CircularProgressIndicator());
    if (camera == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Caméra indisponible',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _startCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        final ratio = portrait
            ? 1 / camera.value.aspectRatio
            : camera.value.aspectRatio;
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxWidth / ratio,
                child: CameraPreview(camera),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Fermer',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(_labelMode ? 'Photo étiquette' : 'Photo vêtement'),
      actions: [
        if (_camera != null && _photo == null)
          IconButton(
            tooltip: 'Flash',
            icon: const Icon(Icons.flash_on_outlined),
            onPressed: _busy
                ? null
                : () async {
                    try {
                      final camera = _camera!;
                      await camera.setFlashMode(
                        camera.value.flashMode == FlashMode.off
                            ? FlashMode.auto
                            : FlashMode.off,
                      );
                      if (mounted) setState(() {});
                    } on CameraException catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'Flash indisponible sur cette caméra.',
                        );
                      }
                    }
                  },
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _preview(),
                    if (_photo == null && _camera != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            _labelMode
                                ? 'Cadre la référence et la composition'
                                : 'Cadre le vêtement entier sur un fond uni',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_error != null && (_camera != null || _photo != null))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_photo == null)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Photo')),
                      ButtonSegment(value: true, label: Text('Étiquette')),
                    ],
                    selected: {_labelMode},
                    onSelectionChanged: _busy
                        ? null
                        : (s) => setState(() => _labelMode = s.first),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Galerie',
                      onPressed: _busy ? null : _gallery,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    if (_photo == null)
                      Semantics(
                        button: true,
                        label: 'Prendre la photo',
                        child: IconButton.filled(
                          onPressed: _busy || _camera == null ? null : _capture,
                          iconSize: 48,
                          icon: const Icon(Icons.circle),
                        ),
                      )
                    else
                      Flexible(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() => _photo = null);
                                  unawaited(_startCamera());
                                },
                          child: const Text('Reprendre'),
                        ),
                      ),
                    const SizedBox(width: 48),
                  ],
                ),
                if (_photo != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(_photo),
                      child: const Text('Utiliser cette photo'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
