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
import 'dressing_controller.dart';
export 'dressing_controller.dart' show DressingSelection;
import '../../core/widgets/garment_card.dart';
import 'package:flutter/services.dart';

enum MannequinPose { neutral, relaxed, confident }

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
  Garment? _dragging;
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              Text(
                'Ton dressing personnel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    MannequinViewer(
                      presentation: presentation,
                      garments: selected,
                      height: 400,
                    ),
                    if (selected.isNotEmpty && _dragging == null)
                      Positioned(
                        left: 8,
                        top: 12,
                        bottom: 48,
                        width: 48,
                        child: ListView.separated(
                          itemCount: selected.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) => SizedBox(
                            height: 60,
                            child: Semantics(
                              button: true,
                              label: 'Détail ${selected[index].name}',
                              child: Material(
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => context.push(
                                    '/wardrobe/garment/${selected[index].id}',
                                  ),
                                  child: GarmentVisual(
                                    garment: selected[index],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_dragging != null)
                      for (final zone in DressingDropZone.values)
                        Positioned.fromRect(
                          rect: _zoneRect(zone, constraints.maxWidth, 400),
                          child: DragTarget<Garment>(
                            key: ValueKey('drop-${zone.name}'),
                            onWillAcceptWithDetails: (details) =>
                                !_saving && dropZoneFor(details.data) == zone,
                            onAcceptWithDetails: (details) =>
                                _apply(details.data, zone: zone),
                            builder: (context, accepted, rejected) =>
                                IgnorePointer(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: dropZoneFor(_dragging!) == zone
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary.withValues(
                                              alpha: accepted.isEmpty
                                                  ? .12
                                                  : .3,
                                            )
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: dropZoneFor(_dragging!) == zone
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Appuie longuement sur une pièce et glisse-la sur le mannequin.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              Text(
                'Fais glisser pour tourner · Pince pour zoomer · Double-tap pour recentrer',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (selected.isNotEmpty) ...[
                Text(
                  'Tenue actuelle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
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
                const SizedBox(height: 18),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Choisis ta première pièce pour composer ta tenue.',
                  ),
                ),
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
              const SizedBox(height: 14),
              if (choices.isEmpty) ...[
                Text(
                  'Aucune pièce dans cette catégorie.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/wardrobe/add${addCategories.containsKey(_filter) ? '?category=${addCategories[_filter]}' : ''}',
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter une pièce'),
                ),
              ] else
                SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: choices.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, index) {
                      final garment = choices[index];
                      final card = SizedBox(
                        width: 125,
                        child: GarmentCard(
                          garment: garment,
                          selected: _selection!.contains(garment.id),
                          compact: true,
                          onTap: _saving ? null : () => _choose(garment),
                        ),
                      );
                      return LongPressDraggable<Garment>(
                        data: garment,
                        maxSimultaneousDrags: _saving ? 0 : 1,
                        onDragStarted: () {
                          HapticFeedback.selectionClick();
                          setState(() => _dragging = garment);
                        },
                        onDragEnd: (_) {
                          if (mounted) setState(() => _dragging = null);
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          elevation: 12,
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 135,
                            height: 195,
                            child: GarmentCard(
                              garment: garment,
                              onTap: null,
                              compact: true,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .35, child: card),
                        child: card,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              const SizedBox(height: 14),
              Text(
                'Prévisualisation stylisée : mannequin de présentation et images de tes pièces. Aucun essayage 3D exact.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 20),
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

  void _apply(Garment garment, {DressingDropZone? zone}) {
    if (_saving || _selection == null) return;
    setState(() {
      if (zone == null) {
        _selection!.select(garment);
      } else {
        _selection!.drop(garment, zone);
      }
      _savedId = null;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _choose(Garment garment) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(garment.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.accessibility_new),
                label: const Text('Porter sur mannequin'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && accepted == true) _apply(garment);
  }

  static Rect _zoneRect(DressingDropZone zone, double width, double height) {
    final bounds = switch (zone) {
      DressingDropZone.head => const Rect.fromLTWH(.38, .05, .24, .20),
      DressingDropZone.torso => const Rect.fromLTWH(.28, .25, .44, .25),
      DressingDropZone.wrists => const Rect.fromLTWH(.18, .50, .64, .08),
      DressingDropZone.waist => const Rect.fromLTWH(.32, .58, .36, .08),
      DressingDropZone.legs => const Rect.fromLTWH(.32, .66, .36, .20),
      DressingDropZone.feet => const Rect.fromLTWH(.29, .86, .42, .12),
    };
    return Rect.fromLTWH(
      bounds.left * width,
      bounds.top * height,
      bounds.width * width,
      bounds.height * height,
    );
  }
}
