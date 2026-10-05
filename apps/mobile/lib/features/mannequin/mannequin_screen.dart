import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/widgets/app_widgets.dart';
import '../history/history_screen.dart';
import 'mannequin_viewer.dart';

enum MannequinPose { neutral }

/// One selection per clothing slot; changing one piece preserves the others.
class DressingSelection {
  DressingSelection(Iterable<Garment> initial) {
    for (final garment in initial) {
      select(garment);
    }
  }
  final Map<String, Garment> _items = {};
  List<Garment> get items => _items.values.toList();
  static const outerSlugs = {'jacket', 'blazer', 'coat', 'puffer', 'cardigan'};
  static String slot(Garment garment) {
    if (outerSlugs.contains(garment.category.slug)) return 'outer';
    if (garment.category.group == 'head') {
      if ({'glasses', 'sunglasses'}.contains(garment.category.slug)) {
        return 'face';
      }
      if (garment.category.slug == 'earrings') return 'ears';
      return 'head';
    }
    if (garment.category.group == 'other') return garment.category.slug;
    return garment.category.group;
  }

  void select(Garment garment) {
    if (garment.category.slug == 'dress') {
      _items.remove('top');
      _items.remove('bottom');
    }
    if (garment.category.group == 'top' &&
        !outerSlugs.contains(garment.category.slug) &&
        _items['bottom']?.category.slug == 'dress') {
      _items.remove('bottom');
    }
    _items[slot(garment)] = garment;
  }

  void remove(String id) =>
      _items.removeWhere((_, garment) => garment.id == id);
  bool contains(String id) => _items.values.any((garment) => garment.id == id);
}

class MannequinScreen extends ConsumerStatefulWidget {
  const MannequinScreen({super.key, this.initialGarmentIds = const []});
  final List<String> initialGarmentIds;
  @override
  ConsumerState<MannequinScreen> createState() => _MannequinScreenState();
}

class _MannequinScreenState extends ConsumerState<MannequinScreen> {
  DressingSelection? _selection;
  String _filter = 'all';
  bool _saving = false;
  String? _error, _savedId;
  final _name = TextEditingController(text: 'Ma tenue');
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static const filters = [
    ('all', 'Tout'),
    ('top', 'Hauts'),
    ('bottom', 'Bas'),
    ('outer', 'Vestes'),
    ('shoes', 'Chaussures'),
    ('accessories', 'Accessoires'),
  ];
  static const addCategories = {
    'top': 'top_other',
    'bottom': 'bottom_other',
    'outer': 'jacket',
    'shoes': 'shoes_other',
    'head': 'head_accessory',
    'wrist': 'wrist_other',
    'accessories': 'misc_accessory',
  };
  bool matches(Garment garment) => switch (_filter) {
    'all' => true,
    'outer' => DressingSelection.outerSlugs.contains(garment.category.slug),
    'top' =>
      garment.category.group == 'top' &&
          !DressingSelection.outerSlugs.contains(garment.category.slug),
    'accessories' => {
      'head',
      'wrist',
      'other',
    }.contains(garment.category.group),
    _ => garment.category.group == _filter,
  };
  Future<bool> _save({bool wear = false}) async {
    final ids = _selection!.items.map((garment) => garment.id).toList();
    if (ids.isEmpty || _saving) return false;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      if (_savedId == null) {
        final response = await dio.post(
          '/outfits',
          data: {
            'name': _name.text.trim().isEmpty ? 'Ma tenue' : _name.text.trim(),
            'garment_ids': ids,
          },
        );
        _savedId = response.data['id'] as String;
      }
      ref.invalidate(savedOutfitsProvider);
      if (wear) {
        await dio.post(
          '/outfits/wear',
          data: {
            'outfit_id': _savedId,
            'garment_ids': ids,
            'activity': 'everyday',
          },
        );
        ref.invalidate(historyProvider);
        ref.invalidate(wardrobeProvider);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wear ? 'Tenue ajoutée à ton historique' : 'Tenue sauvegardée',
            ),
          ),
        );
      }
      return true;
    } on DioException catch (error) {
      if (mounted) setState(() => _error = ApiException.fromDio(error).message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = ref.watch(wardrobeProvider);
    final presentation =
        ref.watch(authControllerProvider).user?.mannequinPresentation ??
        'female';
    return Scaffold(
      appBar: AppBar(title: const Text('Mon mannequin')),
      body: wardrobe.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => AppErrorView(
          message: 'Impossible de charger ta garde-robe',
          onRetry: () => ref.invalidate(wardrobeProvider),
        ),
        data: (items) {
          _selection ??= DressingSelection(
            items.where((g) => widget.initialGarmentIds.contains(g.id)),
          );
          // Deleted wardrobe entries must not remain in the visualization/save payload.
          for (final garment in _selection!.items) {
            if (!items.any((g) => g.id == garment.id)) {
              _selection!.remove(garment.id);
            }
          }
          final choices = items.where(matches).toList();
          final selected = _selection!.items;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Ton dressing personnel',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Stack(
                children: [
                  MannequinViewer(
                    presentation: presentation,
                    garments: selected,
                    height: 400,
                  ),
                  Positioned(
                    right: 8,
                    top: 46,
                    child: Column(
                      children: [
                        for (final zone in const [
                          ('head', 'Tête'),
                          ('top', 'Hauts'),
                          ('wrist', 'Poignets'),
                          ('bottom', 'Bas'),
                          ('shoes', 'Pieds'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: 0.88),
                              ),
                              onPressed: () =>
                                  setState(() => _filter = zone.$1),
                              child: Text(zone.$2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Fais glisser pour tourner · Pince pour zoomer · Double-tap pour recentrer',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Vue générique : catégorie et couleur de tes pièces, sans reproduction exacte de la coupe ou des motifs.',
                textAlign: TextAlign.center,
              ),
              if (selected.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Choisis une pièce de ta garde-robe pour commencer.',
                  ),
                ),
              Wrap(
                spacing: 8,
                children: selected
                    .map(
                      (g) => InputChip(
                        label: Text(g.name),
                        onDeleted: _saving
                            ? null
                            : () => setState(() {
                                _selection!.remove(g.id);
                                _savedId = null;
                              }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filters
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.$2),
                            selected: _filter == f.$1,
                            onSelected: (_) => setState(() => _filter = f.$1),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              if (choices.isEmpty) ...[
                Text(
                  'Aucun vêtement dans cette catégorie.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/wardrobe/add${addCategories.containsKey(_filter) ? '?category=${addCategories[_filter]}' : ''}',
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une pièce'),
                ),
              ] else
                SizedBox(
                  height: 155,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final garment = choices[index];
                      final active = _selection!.contains(garment.id);
                      return Semantics(
                        button: true,
                        selected: active,
                        label: 'Choisir ${garment.name}',
                        child: InkWell(
                          onTap: _saving
                              ? null
                              : () => setState(() {
                                  _selection!.select(garment);
                                  _savedId = null;
                                }),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 126,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              border: Border.all(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline,
                                width: active ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child:
                                      garment.images.isNotEmpty &&
                                          garment.images.first.downloadUrl !=
                                              null
                                      ? Image.network(
                                          garment.images.first.downloadUrl!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.checkroom_outlined,
                                            size: 42,
                                          ),
                                        )
                                      : Icon(
                                          garment.category.group == 'shoes'
                                              ? Icons.ice_skating_outlined
                                              : Icons.checkroom_outlined,
                                          size: 42,
                                        ),
                                ),
                                Text(
                                  garment.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                Text(
                                  '${garment.color}${active ? ' · Choisi' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (selected.isNotEmpty) ...[
                TextField(
                  controller: _name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la tenue',
                  ),
                  onChanged: (_) => _savedId = null,
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(),
                  icon: const Icon(Icons.bookmark_border),
                  label: Text(
                    _saving ? 'Enregistrement…' : 'Sauvegarder la tenue',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _save(wear: true),
                  child: const Text('Je porte cette tenue'),
                ),
                if (widget.initialGarmentIds.isNotEmpty)
                  OutlinedButton(
                    onPressed: () =>
                        context.pop(selected.map((g) => g.id).toList()),
                    child: const Text('Utiliser cette tenue'),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
