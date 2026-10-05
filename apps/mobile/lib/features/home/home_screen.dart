import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/garment_card.dart';
import '../location/location_controller.dart';
import '../location/destination_screen.dart';

final currentWeatherProvider = FutureProvider<WeatherReport?>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  final location = ref.watch(locationControllerProvider);
  if (!location.hasCoordinates) return null;
  try {
    final resp = await ref
        .read(apiClientProvider)
        .dio
        .get(
          '/weather/current',
          queryParameters: {
            'latitude': location.latitude,
            'longitude': location.longitude,
            'location_label': location.label,
          },
        );
    return WeatherReport.fromJson(resp.data as Map<String, dynamic>);
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

final lastRecommendationProvider = FutureProvider<Recommendation?>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final resp = await ref
        .read(apiClientProvider)
        .dio
        .get('/recommendations/last');
    if (resp.data == null) return null;
    return Recommendation.fromJson(resp.data as Map<String, dynamic>);
  } on DioException {
    rethrow;
  }
});

/// Écran 7 — Home : greeting, météo, CTA principal, dernière suggestion.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(locationControllerProvider.notifier).detect(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final location = ref.watch(locationControllerProvider);
    final weather = ref.watch(currentWeatherProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Bonjour ${auth.user?.firstName ?? ''} 👋',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(locationControllerProvider.notifier).detect();
            ref.invalidate(currentWeatherProvider);
            ref.invalidate(lastRecommendationProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: [
              _LocationLine(location: location),
              const SizedBox(height: AppTheme.spacingM),
              weather.when(
                data: (report) => report == null
                    ? const _WeatherCard.placeholder()
                    : _WeatherCard(report: report),
                loading: () => const AppSkeleton(height: 120),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Text(
                      'Météo indisponible — ${e is ApiException ? e.message : 'erreur réseau'}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              FilledButton.icon(
                icon: const Icon(Icons.dry_cleaning_outlined),
                label: const Text('Choisir mon outfit  →'),
                onPressed: () => context.push('/outfit-flow'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/mannequin'),
                      icon: const Icon(Icons.accessibility_new),
                      label: const Text('Mon mannequin'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/?tab=wardrobe'),
                      icon: const Icon(Icons.checkroom_outlined),
                      label: const Text('Ma garde-robe'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingXl),
              SectionTitle(
                'Dernière suggestion',
                trailing: TextButton(
                  onPressed: () => context.push('/history'),
                  child: const Text('Voir tout'),
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              const _LastRecommendationCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationLine extends ConsumerWidget {
  const _LocationLine({required this.location});

  final LocationState location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final description = switch (location.permission) {
      LocationPermissionState.denied => 'Localisation refusée',
      LocationPermissionState.disabled => 'GPS désactivé',
      LocationPermissionState.error => 'Position indisponible',
      LocationPermissionState.unknown ||
      LocationPermissionState.locating => 'Détection de la position…',
      _ => location.label ?? 'Position GPS',
    };
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(description, style: theme.textTheme.titleMedium),
              if (location.administrativeArea != null)
                Text(
                  location.administrativeArea!,
                  style: theme.textTheme.bodySmall,
                ),
              if (location.permission == LocationPermissionState.approximate)
                const Text('Position approximative'),
              if (location.geocodingFailed)
                const Text(
                  'Commune non disponible — météo sur les coordonnées GPS',
                ),
              if (location.hasCoordinates)
                Text(
                  'Source commune : IGN / BAN',
                  style: theme.textTheme.labelSmall,
                ),
              TextButton(
                onPressed: () => _showManualCitySheet(context, ref),
                child: const Text('Choisir ma ville'),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualiser ma position',
          onPressed: location.permission == LocationPermissionState.locating
              ? null
              : () => ref
                    .read(locationControllerProvider.notifier)
                    .detect(force: true),
          icon: const Icon(Icons.my_location),
        ),
      ],
    );
  }

  Future<void> _showManualCitySheet(BuildContext context, WidgetRef ref) async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(builder: (_) => const DestinationScreen(select: true)),
    );
    if (place != null) {
      ref
          .read(locationControllerProvider.notifier)
          .setManualCity(place.label, place.latitude, place.longitude);
    }
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.report});

  const _WeatherCard.placeholder() : report = null;

  final WeatherReport? report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: Text(
            'Renseigne ta ville pour voir la météo',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final current = report!.current;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF555E79), Color(0xFF292E40)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${current.temperatureC.round()}°C',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Ressenti ${current.feelsLikeC.round()}°C · ${_labelFor(current.condition)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Pluie ${(current.precipProbability * 100).round()} % · Vent ${current.windKmh.round()} km/h',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingM),
            Icon(
              _iconFor(current.condition),
              size: 48,
              color: current.condition == 'clear'
                  ? const Color(0xFFFFD76D)
                  : Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String condition) => switch (condition) {
    'clear' => Icons.wb_sunny_outlined,
    'rain' => Icons.umbrella_outlined,
    'snow' => Icons.ac_unit,
    'storm' => Icons.thunderstorm_outlined,
    'fog' => Icons.foggy,
    _ => Icons.cloud_outlined,
  };

  static String _labelFor(String condition) => switch (condition) {
    'clear' => 'Ciel dégagé',
    'rain' => 'Pluie',
    'snow' => 'Neige',
    'storm' => 'Orage',
    'fog' => 'Brouillard',
    _ => 'Nuageux',
  };
}

class _LastRecommendationCard extends ConsumerWidget {
  const _LastRecommendationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastRecommendationProvider);
    final wardrobe = ref.watch(wardrobeProvider);
    return last.when(
      loading: () => const AppSkeleton(height: 100),
      error: (_, _) => AppErrorView(
        message: 'Suggestion indisponible',
        onRetry: () => ref.invalidate(lastRecommendationProvider),
      ),
      data: (reco) {
        if (reco == null || reco.proposals.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Text(
                'Pas encore de suggestion. Ajoute quelques vêtements puis lance « Choisir mon outfit ».',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        final top = reco.proposals.first;
        final garments = wardrobe.valueOrNull ?? const <Garment>[];
        final byId = {for (final g in garments) g.id: g};
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${top.garmentIds.length} pièces · score ${(top.score * 100).round()} %',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (reco.destinationLabel != null)
                      Chip(
                        label: Text(reco.destinationLabel!),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingS),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: top.garmentIds.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppTheme.spacingS),
                    itemBuilder: (context, i) {
                      final garment = byId[top.garmentIds[i]];
                      return InkWell(
                        onTap: garment == null
                            ? null
                            : () => context.push(
                                '/wardrobe/garment/${garment.id}',
                              ),
                        child: Container(
                          width: 84,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusM,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: garment == null
                              ? const Center(
                                  child: Icon(Icons.checkroom_outlined),
                                )
                              : GarmentVisual(garment: garment),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                TextButton(
                  onPressed: () => context.push('/outfit-flow', extra: reco),
                  child: const Text('Voir cette tenue'),
                ),
                ...top.explanations
                    .take(2)
                    .map(
                      (e) => Text(
                        '• $e',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}
