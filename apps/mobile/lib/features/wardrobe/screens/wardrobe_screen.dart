import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/garment_card.dart';

/// Écrans 9/10 — Garde-robe : filtres par groupe, grille 3 colonnes, CTA ajout.
class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  String? _groupFilter; // null = Tous
  bool _searchOpen = false;
  String _query = '';

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
            icon: const Icon(Icons.search),
            tooltip: 'Rechercher un vêtement',
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _query = '';
            }),
          ),
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
            crossAxisCount:
                MediaQuery.sizeOf(context).width >= 360 &&
                    MediaQuery.textScalerOf(context).scale(14) < 20
                ? 3
                : 2,
            padding: const EdgeInsets.all(AppTheme.spacingM),
            mainAxisSpacing: 16,
            crossAxisSpacing: AppTheme.spacingS,
            children: List.generate(6, (_) => const AppSkeleton(height: 120)),
          ),
          error: (e, _) => AppErrorView(
            message: 'Impossible de charger la garde-robe',
            onRetry: () => ref.invalidate(wardrobeProvider),
          ),
          data: (items) {
            final filtered = items
                .where(
                  (g) =>
                      (_groupFilter == null ||
                          g.category.group == _groupFilter) &&
                      '${g.name} ${g.brand ?? ''} ${g.color} ${g.colorLabel} ${g.category.label}'
                          .toLowerCase()
                          .contains(_query.toLowerCase().trim()),
                )
                .toList();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(wardrobeProvider),
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                children: [
                  if (_searchOpen) ...[
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Nom, marque ou couleur',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:
                            MediaQuery.sizeOf(context).width >= 360 &&
                                MediaQuery.textScalerOf(context).scale(14) < 20
                            ? 3
                            : 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: AppTheme.spacingS,
                        mainAxisExtent:
                            130 +
                            MediaQuery.textScalerOf(context).scale(14) * 4,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => GarmentCard(
                        garment: filtered[i],
                        compact: true,
                        onTap: () =>
                            context.push('/wardrobe/garment/${filtered[i].id}'),
                      ),
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
          : FloatingActionButton(
              onPressed: () => context.push('/wardrobe/add'),
              tooltip: 'Ajouter un vêtement',
              child: const Icon(Icons.add),
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
      message: 'Commence par ajouter tes premiers vêtements.',
      actionLabel: 'Ajouter un vêtement',
      onAction: onAdd,
    );
  }
}
