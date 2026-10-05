import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../mannequin/mannequin_viewer.dart';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';

/// Écran 16 — Silhouette interactive : mannequin + zones tactiles.
class SilhouetteScreen extends ConsumerStatefulWidget {
  const SilhouetteScreen({super.key});

  @override
  ConsumerState<SilhouetteScreen> createState() => _SilhouetteScreenState();
}

class _SilhouetteScreenState extends ConsumerState<SilhouetteScreen> {
  String? _selected;
  bool _saving = false;

  static const _zones = [
    ('head', 'Tête', Icons.face_outlined),
    ('face', 'Visage', Icons.visibility_outlined),
    ('torso', 'Torse', Icons.checkroom_outlined),
    ('arms', 'Bras', Icons.front_hand_outlined),
    ('wrists', 'Poignets', Icons.watch_outlined),
    ('waist', 'Taille', Icons.stacked_line_chart),
    ('legs', 'Jambes', Icons.directions_walk),
    ('feet', 'Pieds', Icons.ice_skating_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation =
        ref.watch(authControllerProvider).user?.mannequinPresentation ??
        'female';
    return Scaffold(
      appBar: AppBar(title: const Text('Choisis une zone')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          child: Column(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'female', label: Text('Femme')),
                  ButtonSegment(value: 'male', label: Text('Homme')),
                ],
                selected: {presentation},
                onSelectionChanged: _saving
                    ? null
                    : (values) async {
                        setState(() => _saving = true);
                        try {
                          await ref
                              .read(apiClientProvider)
                              .dio
                              .patch(
                                '/me',
                                data: {'mannequin_presentation': values.first},
                              );
                          await ref
                              .read(authControllerProvider.notifier)
                              .refreshProfile();
                        } on DioException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ApiException.fromDio(e).message),
                              ),
                            );
                          }
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(e.message)));
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ListView(
                        children: [
                          Text(
                            'Pour voir les catégories disponibles',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingM),
                          for (final zone in _zones)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppTheme.spacingS,
                              ),
                              child: OutlinedButton.icon(
                                icon: Icon(zone.$3, size: 18),
                                label: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(zone.$2),
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _selected == zone.$1
                                      ? theme.colorScheme.primary
                                      : null,
                                  foregroundColor: _selected == zone.$1
                                      ? theme.colorScheme.onPrimary
                                      : null,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                onPressed: () {
                                  setState(() => _selected = zone.$1);
                                  _openZone(context, ref, zone.$1, zone.$2);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      flex: 3,
                      child: MannequinViewer(
                        presentation: presentation,
                        height: 480,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openZone(
    BuildContext context,
    WidgetRef ref,
    String zone,
    String label,
  ) async {
    final repo = ref.read(wardrobeRepositoryProvider);
    final router = GoRouter.of(context);
    Map<String, List<String>> map;
    try {
      map = await repo.silhouetteMap();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    final slugs = map[zone] ?? const <String>[];
    List<dynamic> categories = [];
    try {
      categories = await repo.categories();
    } catch (_) {
      /* offline */
    }
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final category in categories)
              if (slugs.contains(category.slug))
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(category.label as String),
                  onTap: () {
                    Navigator.of(context).pop();
                    router.push(
                      '/wardrobe/add',
                      extra: {'category_slug': category.slug},
                    );
                  },
                ),
            if (categories.isEmpty)
              const ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Catégories indisponibles hors ligne'),
              ),
          ],
        ),
      ),
    );
  }
}
