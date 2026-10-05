import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/garment_card.dart';

class _HistoryEntry {
  const _HistoryEntry({
    required this.wornAt,
    this.destinationLabel,
    this.activity,
    this.feedback,
    this.garmentCount = 0,
    this.outfitId,
    this.garmentIds = const [],
    this.weather,
  });

  final String wornAt;
  final String? destinationLabel;
  final String? activity;
  final String? feedback;
  final int garmentCount;
  final String? outfitId;
  final List<String> garmentIds;
  final Map<String, dynamic>? weather;
}

final savedOutfitsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final response = await ref.watch(apiClientProvider).dio.get('/outfits');
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

final historyProvider = FutureProvider<List<_HistoryEntry>>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final resp = await ref
        .read(apiClientProvider)
        .dio
        .get('/outfits/history/recent');
    return (resp.data as List)
        .map(
          (e) => _HistoryEntry(
            wornAt: e['worn_at'] as String,
            destinationLabel: e['destination_label'] as String?,
            activity: e['activity'] as String?,
            feedback: e['feedback'] as String?,
            garmentCount: (e['garment_ids'] as List?)?.length ?? 0,
            garmentIds: (e['garment_ids'] as List?)?.cast<String>() ?? const [],
            outfitId: e['outfit_id'] as String?,
            weather: e['weather'] == null
                ? null
                : Map<String, dynamic>.from(e['weather'] as Map),
          ),
        )
        .toList();
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

/// Écran 23 — Historique des tenues portées (données réelles).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final outfits = ref.watch(savedOutfitsProvider);
    final wardrobe = ref.watch(wardrobeProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: SafeArea(
        child: history.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppTheme.spacingM),
            children: const [
              AppSkeleton(height: 72),
              SizedBox(height: 12),
              AppSkeleton(height: 72),
            ],
          ),
          error: (e, _) => AppErrorView(
            message: 'Historique indisponible',
            onRetry: () => ref.invalidate(historyProvider),
          ),
          data: (entries) => entries.isEmpty
              ? const AppEmptyState(
                  icon: Icons.history,
                  title: 'Aucune tenue portée',
                  message:
                      'Les tenues que tu marques comme portées apparaîtront ici.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTheme.spacingS),
                  itemBuilder: (context, i) {
                    final entry = entries[i];
                    final pieces = wardrobe
                        .where((g) => entry.garmentIds.contains(g.id))
                        .take(4)
                        .toList();
                    final favorite =
                        outfits.valueOrNull
                            ?.where((o) => o['id'] == entry.outfitId)
                            .firstOrNull?['is_favorite'] ==
                        true;
                    return Card(
                      child: ListTile(
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheetContext) => SafeArea(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                ListTile(
                                  title: Text(_formatDate(entry.wornAt)),
                                  subtitle: Text(
                                    entry.destinationLabel ??
                                        'Lieu non renseigné',
                                  ),
                                ),
                                ...ref
                                        .read(wardrobeProvider)
                                        .valueOrNull
                                        ?.where(
                                          (g) =>
                                              entry.garmentIds.contains(g.id),
                                        )
                                        .map(
                                          (g) => ListTile(
                                            leading: const Icon(
                                              Icons.checkroom_outlined,
                                            ),
                                            title: Text(g.name),
                                            trailing: const Icon(
                                              Icons.chevron_right,
                                            ),
                                            onTap: () {
                                              Navigator.pop(sheetContext);
                                              context.push(
                                                '/wardrobe/garment/${g.id}',
                                              );
                                            },
                                          ),
                                        ) ??
                                    [],
                              ],
                            ),
                          ),
                        ),
                        trailing: entry.outfitId == null
                            ? null
                            : IconButton(
                                tooltip: favorite
                                    ? 'Retirer des favoris'
                                    : 'Ajouter aux favoris',
                                icon: Icon(
                                  favorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: favorite
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(apiClientProvider)
                                        .dio
                                        .patch(
                                          '/outfits/${entry.outfitId}',
                                          data: {'is_favorite': !favorite},
                                        );
                                    ref.invalidate(savedOutfitsProvider);
                                  } on DioException catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            ApiException.fromDio(e).message,
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                        minTileHeight: 88,
                        leading: SizedBox(
                          width: 64,
                          height: 64,
                          child: pieces.isEmpty
                              ? const Icon(Icons.checkroom_outlined)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: GridView.count(
                                    crossAxisCount: pieces.length == 1 ? 1 : 2,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    children: [
                                      for (final piece in pieces)
                                        GarmentVisual(garment: piece),
                                    ],
                                  ),
                                ),
                        ),
                        title: Text(
                          '${_formatDate(entry.wornAt)}${entry.destinationLabel == null ? '' : ' · ${entry.destinationLabel}'}',
                        ),
                        subtitle: Text(
                          [
                            if (entry.weather != null)
                              '${(entry.weather!['temperature_c'] as num?)?.round() ?? '?'} °C · ${_condition(entry.weather!['condition'] as String?)}',
                            if (entry.activity != null)
                              _activityLabel(entry.activity!),
                            '${entry.garmentCount} pièces',
                          ].join(' · '),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  static String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  static String _condition(String? value) => switch (value) {
    'rain' => 'Pluie',
    'clear' => 'Ciel dégagé',
    'cloudy' => 'Nuageux',
    'snow' => 'Neige',
    'fog' => 'Brouillard',
    _ => 'Météo enregistrée',
  };

  static String _activityLabel(String activity) => switch (activity) {
    'work' => 'Travail',
    'sport' => 'Sport',
    'evening' => 'Soirée',
    'travel' => 'Voyage',
    'school' => 'École',
    'restaurant' => 'Restaurant',
    'date' => 'Rendez-vous',
    'formal_event' => 'Événement chic',
    _ => 'Quotidien',
  };
}
