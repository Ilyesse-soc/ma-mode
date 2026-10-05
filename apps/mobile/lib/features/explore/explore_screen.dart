import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../home/home_screen.dart' show lastRecommendationProvider;
import '../history/history_screen.dart' show savedOutfitsProvider;
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
                        leading: const Icon(Icons.auto_awesome),
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
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: garments.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppTheme.spacingS),
                        itemBuilder: (context, i) =>
                            _MiniGarmentCard(garment: garments[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniGarmentCard extends StatelessWidget {
  const _MiniGarmentCard({required this.garment});

  final Garment garment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = garment.images.isNotEmpty
        ? garment.images.first.downloadUrl
        : null;
    return InkWell(
      onTap: () => context.push('/wardrobe/garment/${garment.id}'),
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          border: Border.all(color: theme.colorScheme.outline, width: 0.5),
        ),
        child: Column(
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
                        width: double.infinity,
                      )
                    : Center(
                        child: Text(
                          garment.name.substring(0, 1).toUpperCase(),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                garment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
