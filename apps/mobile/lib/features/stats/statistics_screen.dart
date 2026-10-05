import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class _Stats {
  const _Stats({
    required this.outfitsWorn,
    required this.garments,
    required this.outfitsSaved,
    required this.favorites,
  });

  final int outfitsWorn;
  final int garments;
  final int outfitsSaved;
  final int favorites;
}

final _statsProvider = FutureProvider<_Stats>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final resp = await ref
        .read(apiClientProvider)
        .dio
        .get('/outfits/stats/summary');
    final data = resp.data as Map<String, dynamic>;
    return _Stats(
      outfitsWorn: data['outfits_worn'] as int,
      garments: data['garments'] as int,
      outfitsSaved: data['outfits_saved'] as int,
      favorites: data['favorites'] as int,
    );
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

/// Statistiques réelles (compteurs DB) — menu « Statistiques ».
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: SafeArea(
        child: stats.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorView(
            message: 'Statistiques indisponibles',
            onRetry: () => ref.invalidate(_statsProvider),
          ),
          data: (s) => GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(AppTheme.spacingM),
            mainAxisSpacing: AppTheme.spacingM,
            crossAxisSpacing: AppTheme.spacingM,
            children: [
              _StatCard(
                value: '${s.outfitsWorn}',
                label: 'Tenues portées',
                icon: Icons.checkroom,
              ),
              _StatCard(
                value: '${s.garments}',
                label: 'Vêtements',
                icon: Icons.dry_cleaning,
              ),
              _StatCard(
                value: '${s.outfitsSaved}',
                label: 'Tenues enregistrées',
                icon: Icons.bookmark_outline,
              ),
              _StatCard(
                value: '${s.favorites}',
                label: 'Favoris',
                icon: Icons.favorite_outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              value,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
