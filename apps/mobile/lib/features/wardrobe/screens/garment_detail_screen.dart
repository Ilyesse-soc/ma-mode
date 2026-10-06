import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/garment_card.dart';
import '../../../core/network/api_client.dart';

final garmentProvider = FutureProvider.autoDispose.family<Garment, String>(
  (ref, id) => ref.watch(wardrobeRepositoryProvider).getGarment(id),
);

/// Écran 15 — Détail vêtement : image, attributs, saison, actions.
class GarmentDetailScreen extends ConsumerStatefulWidget {
  const GarmentDetailScreen({super.key, required this.garmentId});

  final String garmentId;

  @override
  ConsumerState<GarmentDetailScreen> createState() =>
      _GarmentDetailScreenState();
}

class _GarmentDetailScreenState extends ConsumerState<GarmentDetailScreen> {
  final Map<String, dynamic> _changes = {};
  bool _saving = false;
  String? _error, _categoryLabel;
  String get garmentId => widget.garmentId;

  Future<void> _edit(
    String label,
    String field,
    String value,
    int length,
  ) async {
    final controller = TextEditingController(
      text: _changes[field] as String? ?? value,
    );
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: length,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (field == 'color' && text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    // The dialog's closing animation still uses its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && answer != null) setState(() => _changes[field] = answer);
  }

  Future<void> _category() async {
    setState(() => _saving = true);
    try {
      final categories = await ref
          .read(wardrobeRepositoryProvider)
          .categories();
      if (!mounted) return;
      final selected = await showModalBottomSheet<GarmentCategory>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            children: [
              for (final category in categories)
                ListTile(
                  title: Text(category.label),
                  onTap: () => Navigator.pop(context, category),
                ),
            ],
          ),
        ),
      );
      if (mounted && selected != null) {
        setState(() {
          _changes['category_slug'] = selected.slug;
          _categoryLabel = selected.label;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(wardrobeRepositoryProvider)
          .updateGarment(garmentId, Map.from(_changes));
      if (!mounted) return;
      _changes.clear();
      _categoryLabel = null;
      ref.invalidate(garmentProvider(garmentId));
      ref.invalidate(wardrobeProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vêtement enregistré')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ref
        .watch(garmentProvider(garmentId))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: AppBar(),
            body: AppErrorView(
              message: e is ApiException
                  ? e.message
                  : 'Impossible de charger ce vêtement.',
              onRetry: () => ref.invalidate(garmentProvider(garmentId)),
            ),
          ),
          data: (garment) => Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Supprimer',
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final router = GoRouter.of(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Supprimer ce vêtement ?'),
                        content: Text(garment.name),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Annuler'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    try {
                      await ref
                          .read(wardrobeRepositoryProvider)
                          .deleteGarment(garment.id);
                      if (!context.mounted) return;
                      ref.invalidate(wardrobeProvider);
                      messenger.showSnackBar(
                        SnackBar(content: Text('${garment.name} supprimé')),
                      );
                      router.pop();
                    } on ApiException catch (e) {
                      if (!context.mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                children: [
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GarmentVisual(garment: garment),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  if (garment.importMetadata != null) ...[
                    Text(
                      garment.importMetadata!['exact_match'] == true
                          ? 'Produit confirmé par son identifiant catalogue'
                          : garment.importMetadata!['save_mode'] == 'custom'
                          ? 'Vêtement personnalisé · photo importée'
                          : 'Identification approchée · produit exact non vérifié',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    garment.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (garment.brand != null)
                    Text(
                      garment.importMetadata?['brand_status'] == 'unverified'
                          ? '${garment.brand} · marque supposée'
                          : garment.brand!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  const SizedBox(height: AppTheme.spacingL),
                  _row(
                    theme,
                    'Catégorie',
                    _categoryLabel ?? garment.category.label,
                    onEdit: _category,
                  ),
                  _row(
                    theme,
                    'Couleur',
                    _changes['color'] as String? ?? garment.color,
                    onEdit: () => _edit('Couleur', 'color', garment.color, 60),
                  ),
                  _row(
                    theme,
                    'Marque',
                    _changes['brand'] as String? ??
                        garment.brand ??
                        'Non renseignée',
                    onEdit: () =>
                        _edit('Marque', 'brand', garment.brand ?? '', 120),
                  ),
                  if (garment.size != null)
                    _row(theme, 'Taille', garment.size!),
                  if (garment.material != null)
                    _row(theme, 'Matière', garment.material!),
                  _row(
                    theme,
                    'Référence',
                    _changes['reference'] as String? ??
                        garment.reference ??
                        'Non renseignée',
                    onEdit: () => _edit(
                      'Référence',
                      'reference',
                      garment.reference ?? '',
                      160,
                    ),
                  ),
                  _row(theme, 'Chaleur', '${garment.warmthLevel}/5'),
                  const SizedBox(height: 10),
                  Text('Saison', style: theme.textTheme.bodyMedium),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final season in [
                        'summer',
                        'autumn',
                        'winter',
                        'spring',
                        'all',
                      ])
                        ChoiceChip(
                          label: Text(_seasonLabel(season)),
                          selected:
                              (_changes['season'] ?? garment.season) == season,
                          onSelected: _saving
                              ? null
                              : (_) =>
                                    setState(() => _changes['season'] = season),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    children: [
                      if (garment.waterproof)
                        const Chip(
                          label: Text('Imperméable'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (garment.windproof)
                        const Chip(
                          label: Text('Coupe-vent'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ...garment.styles.map(
                        (s) => Chip(
                          label: Text(s),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingM),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  FilledButton(
                    onPressed: _saving || _changes.isEmpty ? null : _save,
                    child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await context.push(
                        '/wardrobe/add',
                        extra: {'garment': garment},
                      );
                      if (mounted) ref.invalidate(garmentProvider(garmentId));
                    },
                    child: const Text('Modifier le vêtement'),
                  ),
                  Text(
                    'Prévisualisation : mannequin de présentation et image de ta pièce. L’essayage 3D exact est indisponible.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    VoidCallback? onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
          Flexible(
            child: onEdit == null
                ? Text(
                    value,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.end,
                  )
                : OutlinedButton(
                    onPressed: _saving ? null : onEdit,
                    child: Text(value, overflow: TextOverflow.ellipsis),
                  ),
          ),
        ],
      ),
    );
  }

  static String _seasonLabel(String season) => switch (season) {
    'winter' => 'Hiver',
    'summer' => 'Été',
    'spring' => 'Printemps',
    'autumn' => 'Automne',
    _ => 'Toutes',
  };
}
