import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_screen.dart';

/// User-selected images only; no URL fetch, upload or AI call before confirmation.
class ImportImageScreen extends StatefulWidget {
  const ImportImageScreen({super.key});

  @override
  State<ImportImageScreen> createState() => _ImportImageScreenState();
}

class _ImportImageScreenState extends State<ImportImageScreen> {
  CapturedPhoto? _photo;
  bool _busy = false;
  String? _error;

  Future<void> _pick(String source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile? file;
      if (source == 'file') {
        file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Images',
              extensions: ['jpg', 'jpeg', 'png', 'webp'],
              mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
              uniformTypeIdentifiers: [
                'public.jpeg',
                'public.png',
                'org.webmproject.webp',
              ],
            ),
          ],
        );
      } else {
        file = await ImagePicker().pickImage(source: ImageSource.gallery);
      }
      if (file == null) return;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Choisis une image de moins de 10 Mo.');
      }
      final bytes = await file.readAsBytes();
      final name = file.name;
      // Decode before accepting the preview; invalid files cannot be submitted.
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1000);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (mounted) {
        setState(
          () => _photo = CapturedPhoto(bytes, name, sourceType: source),
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Impossible d’ouvrir cette image. Réessaie ou utilise un fichier local.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Importer une image')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Une pièce repérée en ligne ?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Choisis une photo ou une capture. Recadre la pièce et évite les informations personnelles. Tu vérifieras les détails avant de l’ajouter.',
          ),
          const SizedBox(height: 24),
          for (final option in const [
            ('gallery', Icons.photo_library_outlined, 'Galerie'),
            ('file', Icons.folder_open_outlined, 'Fichier local'),
            ('screenshot', Icons.screenshot_outlined, 'Capture d’écran'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(option.$1),
                icon: Icon(option.$2),
                label: Text(option.$3),
              ),
            ),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_photo != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.memory(
                _photo!.bytes,
                height: 300,
                fit: BoxFit.contain,
                cacheWidth: 1000,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      'Format illisible. Choisis un JPEG, PNG ou WebP.',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'L’analyse IA est optionnelle. Si le produit reste inconnu, tu pourras enregistrer cette image comme vêtement personnalisé.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => Navigator.pop(context, _photo),
              child: const Text('Utiliser cette image'),
            ),
          ],
        ],
      ),
    ),
  );
}
