import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/garment_card.dart';
import '../home/home_screen.dart' show lastRecommendationProvider;
import '../history/history_screen.dart'
    show savedOutfitsProvider, historyProvider;
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';

/// Explore = historique des recommandations + favoris (données réelles).
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastRecommendationProvider);
    final wardrobe = ref.watch(wardrobeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Explorer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          children: [
            const SectionTitle('Dernière recommandation'),
            const SizedBox(height: AppTheme.spacingS),
            last.when(
              loading: () => const AppSkeleton(height: 90),
              error: (e, _) => AppErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(lastRecommendationProvider),
              ),
              data: (reco) => reco == null
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacingM),
                        child: Text('Aucune recommandation pour l\'instant.'),
                      ),
                    )
                  : Card(
                      child: ListTile(
                        leading: const Icon(Icons.dry_cleaning_outlined),
                        title: Text(
                          reco.destinationLabel != null
                              ? 'Vers ${reco.destinationLabel}'
                              : 'Tenue du jour',
                        ),
                        subtitle: Text(
                          reco.proposals.isNotEmpty &&
                                  reco.proposals.first.explanations.isNotEmpty
                              ? reco.proposals.first.explanations.first
                              : '',
                        ),
                        onTap: () => context.push('/outfit-flow', extra: reco),
                      ),
                    ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            const SectionTitle('Mes inspirations personnelles'),
            const SizedBox(height: 8),
            Text(
              'Tes favoris et les looks que tu as vraiment portés.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const SectionTitle('Mes tenues favorites'),
            ref
                .watch(savedOutfitsProvider)
                .when(
                  loading: () => const AppSkeleton(height: 80),
                  error: (e, _) => AppErrorView(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(savedOutfitsProvider),
                  ),
                  data: (outfits) {
                    final favorites = outfits
                        .where((outfit) => outfit['is_favorite'] == true)
                        .toList();
                    return Column(
                      children: [
                        if (favorites.isEmpty)
                          const ListTile(
                            title: Text('Aucune tenue favorite'),
                            subtitle: Text(
                              'Ajoute un favori depuis ton historique.',
                            ),
                          ),
                        for (final outfit in favorites)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.favorite),
                              title: Text(outfit['name'] as String),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (sheetContext) => SafeArea(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      ListTile(
                                        title: Text(outfit['name'] as String),
                                      ),
                                      for (final garment
                                          in wardrobe.valueOrNull ??
                                              <Garment>[])
                                        if ((outfit['garment_ids'] as List)
                                            .contains(garment.id))
                                          ListTile(
                                            title: Text(garment.name),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                            ),
                                            onTap: () {
                                              Navigator.pop(sheetContext);
                                              context.push(
                                                '/wardrobe/garment/${garment.id}',
                                              );
                                            },
                                          ),
                                      TextButton(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(apiClientProvider)
                                                .dio
                                                .patch(
                                                  '/outfits/${outfit['id']}',
                                                  data: {'is_favorite': false},
                                                );
                                            ref.invalidate(
                                              savedOutfitsProvider,
                                            );
                                            if (sheetContext.mounted) {
                                              Navigator.pop(sheetContext);
                                            }
                                          } on DioException catch (e) {
                                            if (sheetContext.mounted) {
                                              ScaffoldMessenger.of(
                                                sheetContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    ApiException.fromDio(
                                                      e,
                                                    ).message,
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text(
                                          'Retirer des favoris',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            const SizedBox(height: AppTheme.spacingL),
            const SectionTitle('Looks récents'),
            const SizedBox(height: 8),
            ref
                .watch(historyProvider)
                .when(
                  loading: () => const AppSkeleton(height: 100),
                  error: (_, _) => AppErrorView(
                    message: 'Historique indisponible',
                    onRetry: () => ref.invalidate(historyProvider),
                  ),
                  data: (entries) => Column(
                    children: [
                      if (entries.isEmpty)
                        ListTile(
                          title: const Text(
                            'Ton histoire de style commence ici',
                          ),
                          subtitle: const Text(
                            'Porte une première tenue pour la retrouver ici.',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/outfit-flow'),
                        ),
                      for (final entry in entries.take(3))
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(entry.destinationLabel ?? 'Ma tenue'),
                            subtitle: Text(
                              '${entry.garmentCount} pièces · ${entry.wornAt.split('T').first}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(
                              '/mannequin',
                              extra: entry.garmentIds,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: 24),
            SectionTitle(
              'Garde-robe',
              trailing: TextButton(
                onPressed: () => context.push('/history'),
                child: const Text('Historique'),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            wardrobe.when(
              loading: () => const AppSkeleton(height: 90),
              error: (_, _) =>
                  const AppErrorView(message: 'Garde-robe indisponible'),
              data: (garments) => garments.isEmpty
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacingM),
                        child: Text('Ta garde-robe est vide.'),
                      ),
                    )
                  : SizedBox(
                      height: 215,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: garments.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppTheme.spacingS),
                        itemBuilder: (context, i) => SizedBox(
                          width: 160,
                          child: GarmentCard(
                            garment: garments[i],
                            compact: true,
                            onTap: () => context.push(
                              '/wardrobe/garment/${garments[i].id}',
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
