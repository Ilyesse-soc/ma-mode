import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/network/api_client.dart';

final garmentProvider = FutureProvider.autoDispose.family<Garment, String>(
  (ref, id) => ref.watch(wardrobeRepositoryProvider).getGarment(id),
);

/// Écran 15 — Détail vêtement : image, attributs, saison, actions.
class GarmentDetailScreen extends ConsumerWidget {
  const GarmentDetailScreen({super.key, required this.garmentId});

  final String garmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ref
        .watch(garmentProvider(garmentId))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: AppErrorView(
              message: e.toString(),
              onRetry: () => ref.invalidate(garmentProvider(garmentId)),
            ),
          ),
          data: (garment) => Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final router = GoRouter.of(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Supprimer ce vêtement ?'),
                        content: Text(garment.name),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await ref
                          .read(wardrobeRepositoryProvider)
                          .deleteGarment(garment.id);
                      ref.invalidate(wardrobeProvider);
                      messenger.showSnackBar(
                        SnackBar(content: Text('${garment.name} supprimé')),
                      );
                      router.pop();
                    } on ApiException catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                children: [
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child:
                        garment.images.isNotEmpty &&
                            garment.images.first.downloadUrl != null
                        ? Image.network(
                            garment.images.first.downloadUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Center(child: Text('Photo indisponible')),
                          )
                        : Center(
                            child: Text(
                              garment.name.substring(0, 1).toUpperCase(),
                              style: theme.textTheme.displayLarge,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text(
                    garment.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (garment.brand != null)
                    Text(
                      garment.brand!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  const SizedBox(height: AppTheme.spacingL),
                  _row(theme, 'Catégorie', garment.category.label),
                  _row(theme, 'Couleur', garment.color),
                  if (garment.size != null)
                    _row(theme, 'Taille', garment.size!),
                  if (garment.material != null)
                    _row(theme, 'Matière', garment.material!),
                  if (garment.reference != null)
                    _row(theme, 'Référence', garment.reference!),
                  _row(theme, 'Chaleur', '${garment.warmthLevel}/5'),
                  _row(theme, 'Saison', _seasonLabel(garment.season)),
                  const SizedBox(height: AppTheme.spacingM),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    children: [
                      if (garment.waterproof)
                        const Chip(
                          label: Text('Imperméable'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (garment.windproof)
                        const Chip(
                          label: Text('Coupe-vent'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ...garment.styles.map(
                        (s) => Chip(
                          label: Text(s),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  FilledButton(
                    onPressed: () async {
                      await context.push(
                        '/wardrobe/add',
                        extra: {'garment': garment},
                      );
                      ref.invalidate(garmentProvider(garmentId));
                    },
                    child: const Text('Modifier le vêtement'),
                  ),
                  Text(
                    'Représentation 3D : ${_visualLevelLabel(garment.visualLevel)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  static String _seasonLabel(String season) => switch (season) {
    'winter' => 'Hiver',
    'summer' => 'Été',
    'spring' => 'Printemps',
    'autumn' => 'Automne',
    _ => 'Toutes',
  };

  static String _visualLevelLabel(String level) => switch (level) {
    'exact' => 'modèle exact du produit',
    'approximate' => 'représentation rapprochée',
    _ => 'représentation générique (catégorie + couleur)',
  };
}
