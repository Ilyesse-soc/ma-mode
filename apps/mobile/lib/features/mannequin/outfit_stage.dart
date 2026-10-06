import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models.dart';
import '../../core/widgets/garment_card.dart';
import 'mannequin_viewer.dart';

/// Shared composition from the reference: owned garment rail and central model.
class OutfitStage extends StatelessWidget {
  const OutfitStage({
    super.key,
    required this.presentation,
    required this.garments,
    this.height = 400,
  });
  final String presentation;
  final List<Garment> garments;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (garments.isNotEmpty) ...[
              SizedBox(
                width: 64,
                child: ListView.separated(
                  itemCount: garments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => SizedBox(
                    height: 76,
                    child: Semantics(
                      button: true,
                      label: 'Détail ${garments[i].name}',
                      child: Material(
                        borderRadius: BorderRadius.circular(10),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.push(
                            '/wardrobe/garment/${garments[i].id}',
                          ),
                          child: GarmentVisual(garment: garments[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: MannequinViewer(
                presentation: presentation,
                garments: garments,
                height: height,
              ),
            ),
          ],
        ),
      ),
      if (garments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Prévisualisation stylisée · Les images de tes pièces accompagnent le mannequin. L’essayage 3D exact nécessite des vêtements 3D adaptés.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
    ],
  );
}
