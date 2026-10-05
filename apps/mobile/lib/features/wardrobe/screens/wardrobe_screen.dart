import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';

/// Écrans 9/10 — Garde-robe : filtres par groupe, grille 3 colonnes, CTA ajout.
class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  String? _groupFilter; // null = Tous

  static const _filters = [
    (null, 'Tous'),
    ('top', 'Hauts'),
    ('bottom', 'Bas'),
    ('shoes', 'Chaussures'),
    ('head', 'Tête'),
    ('wrist', 'Poignets'),
    ('other', 'Autres'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final garments = ref.watch(wardrobeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma garde-robe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mon mannequin',
            onPressed: () => context.push('/mannequin'),
          ),
        ],
      ),
      body: SafeArea(
        child: garments.when(
          loading: () => GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(AppTheme.spacingM),
            mainAxisSpacing: AppTheme.spacingS,
            crossAxisSpacing: AppTheme.spacingS,
            children: List.generate(6, (_) => const AppSkeleton(height: 120)),
          ),
          error: (e, _) => AppErrorView(
            message: 'Impossible de charger la garde-robe',
            onRetry: () => ref.invalidate(wardrobeProvider),
          ),
          data: (items) {
            final filtered = _groupFilter == null
                ? items
                : items.where((g) => g.category.group == _groupFilter).toList();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(wardrobeProvider),
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in _filters)
                          Padding(
                            padding: const EdgeInsets.only(
                              right: AppTheme.spacingS,
                            ),
                            child: ChoiceChip(
                              label: Text(f.$2),
                              selected: _groupFilter == f.$1,
                              onSelected: (_) =>
                                  setState(() => _groupFilter = f.$1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.accessibility_new),
                      title: const Text('Mon mannequin'),
                      subtitle: const Text(
                        'Habille ton modèle avec ta garde-robe',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => context.push('/mannequin'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (items.isNotEmpty && filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aucun vêtement dans cette catégorie.'),
                    ),
                  if (items.isEmpty)
                    _EmptyWardrobe(onAdd: () => context.push('/wardrobe/add'))
                  else ...[
                    if (items.length < 10)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTheme.spacingM,
                        ),
                        child: Text(
                          'Ajoute encore quelques pièces pour obtenir des suggestions plus variées.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: AppTheme.spacingS,
                            crossAxisSpacing: AppTheme.spacingS,
                            childAspectRatio: 0.78,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) =>
                          _GarmentCard(garment: filtered[i]),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: garments.asData?.value.isEmpty == true
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/wardrobe/add'),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un vêtement'),
            ),
    );
  }
}

class _EmptyWardrobe extends StatelessWidget {
  const _EmptyWardrobe({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.checkroom_outlined,
      title: 'Ta garde-robe est vide',
      message:
          'Commence par ajouter quelques vêtements pour recevoir des suggestions personnalisées.',
      actionLabel: 'Ajouter un vêtement',
      onAction: onAdd,
    );
  }
}

class _GarmentCard extends ConsumerWidget {
  const _GarmentCard({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final imageUrl = garment.images.isNotEmpty
        ? garment.images.first.downloadUrl
        : null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      onTap: () => context.push('/wardrobe/garment/${garment.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          border: Border.all(color: theme.colorScheme.outline, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusM),
                ),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _GarmentPlaceholder(garment: garment),
                      )
                    : _GarmentPlaceholder(garment: garment),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    garment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    garment.category.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GarmentPlaceholder extends StatelessWidget {
  const _GarmentPlaceholder({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          garment.name.substring(0, 1).toUpperCase(),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
