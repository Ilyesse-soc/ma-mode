import 'package:flutter/material.dart';

enum PhotoGuideChoice { photo, garment, manual }

class PhotoGuideScreen extends StatelessWidget {
  const PhotoGuideScreen({super.key, required this.labelMode});
  final bool labelMode;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        labelMode ? 'Photographier l’étiquette' : 'Photographier le vêtement',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          labelMode
              ? 'La bonne étiquette fait la différence'
              : 'Pour de meilleurs résultats',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text(
          labelMode
              ? 'Photographie de préférence l’étiquette intérieure ou celle qui contient la référence produit. Cadre bien le texte et évite les reflets.'
              : 'Pose le vêtement à plat ou photographie-le porté. Garde le vêtement entier visible, de face, avec une bonne lumière et un arrière-plan simple. Évite que plusieurs pièces se chevauchent.',
        ),
        if (labelMode) ...[
          const SizedBox(height: 24),
          Text(
            'Exemples d’étiquettes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _LabelExample(
                'MARQUE\nModèle / SKU\nRéférence ABC-123\nTaille M',
              ),
              _LabelExample(
                'COMPOSITION\n80 % coton\n20 % polyester\nEntretien',
              ),
              _LabelExample('EAN / UPC\n|||| ||| ||||||\nCode produit'),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Marque, référence, EAN/UPC, taille et composition : photographie ce qui est lisible. Une information incertaine restera à confirmer.',
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(PhotoGuideChoice.photo),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Prendre la photo'),
        ),
        if (labelMode) ...[
          const SizedBox(height: 12),
          Text(
            'Je n’ai pas cette étiquette',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(PhotoGuideChoice.garment),
            child: const Text('Photographier le vêtement'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(PhotoGuideChoice.manual),
          child: const Text('Saisie manuelle'),
        ),
      ],
    ),
  );
}

class _LabelExample extends StatelessWidget {
  const _LabelExample(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: 140,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF2EBDE),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF242326),
        fontSize: 12,
        height: 1.7,
      ),
    ),
  );
}
