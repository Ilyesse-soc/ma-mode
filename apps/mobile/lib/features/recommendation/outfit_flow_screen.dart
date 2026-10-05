import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_screen.dart';
import '../location/location_controller.dart';
import '../mannequin/mannequin_viewer.dart';
import '../location/destination_screen.dart';
import '../history/history_screen.dart';
import '../../core/widgets/app_widgets.dart';
import 'activity_screen.dart';

/// Flow « Choisir mon outfit » — écrans 17 à 22 de la maquette :
/// choix (lieu/destination/activité) → génération → résultat → 3D → feedback.
enum _Step { setup, generating, result, details, feedback }

class OutfitFlowScreen extends ConsumerStatefulWidget {
  const OutfitFlowScreen({super.key, this.initialRecommendation});
  final Recommendation? initialRecommendation;

  @override
  ConsumerState<OutfitFlowScreen> createState() => _OutfitFlowScreenState();
}

class _OutfitFlowScreenState extends ConsumerState<OutfitFlowScreen> {
  _Step _step = _Step.setup;
  bool _wantsDestination = false;
  String? _destinationLabel;
  ({double lat, double lon})? _destination;
  String _activity = 'everyday';
  String? _error;
  Recommendation? _recommendation;
  int _selectedProposal = 0;
  bool _show3D = false;
  bool _saving = false;
  DateTime _date = DateTime.now();
  String? _savedOutfitId;
  bool _worn = false;
  List<String>? _customGarmentIds;

  @override
  void initState() {
    super.initState();
    _recommendation = widget.initialRecommendation;
    if (_recommendation?.proposals.isNotEmpty == true) _step = _Step.result;
  }

  Future<void> _choosePlace({required bool destination}) async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(builder: (_) => const DestinationScreen(select: true)),
    );
    if (place == null || !mounted) return;
    if (destination) {
      setState(() {
        _destinationLabel = place.label;
        _destination = (lat: place.latitude, lon: place.longitude);
        _wantsDestination = true;
      });
    } else {
      ref
          .read(locationControllerProvider.notifier)
          .setManualCity(place.label, place.latitude, place.longitude);
    }
  }

  static const _activities = [
    ('everyday', 'Tous les jours'),
    ('work', 'Travail'),
    ('sport', 'Sport'),
    ('evening', 'Soirée'),
    ('travel', 'Voyage'),
  ];

  Future<void> _generate() async {
    if (_step == _Step.generating) return;
    if (_wantsDestination && _destination == null) {
      setState(() => _error = 'Choisis une destination avant de continuer.');
      return;
    }
    final location = ref.read(locationControllerProvider);
    if (!location.hasCoordinates) {
      await ref.read(locationControllerProvider.notifier).detect();
    }
    final loc = ref.read(locationControllerProvider);
    if (!loc.hasCoordinates) {
      setState(
        () => _error =
            'Localisation indisponible — choisis ta ville depuis l\'accueil.',
      );
      return;
    }
    setState(() {
      _step = _Step.generating;
      _error = null;
    });
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/recommendations/generate',
            data: {
              'origin_latitude': loc.latitude,
              'origin_longitude': loc.longitude,
              'origin_label': loc.label,
              if (_wantsDestination && _destination != null) ...{
                'destination_latitude': _destination!.lat,
                'destination_longitude': _destination!.lon,
                'destination_label': _destinationLabel,
              },
              'activity': _activity,
              'arrival_timestamp':
                  DateTime(
                    _date.year,
                    _date.month,
                    _date.day,
                    12,
                  ).millisecondsSinceEpoch ~/
                  1000,
            },
          );
      if (!mounted) return;
      final recommendation = Recommendation.fromJson(
        resp.data as Map<String, dynamic>,
      );
      if (recommendation.proposals.isEmpty) {
        setState(() {
          _error =
              'Aucune tenue disponible. Ajoute des vêtements pour compléter ta garde-robe.';
          _step = _Step.setup;
        });
        return;
      }
      setState(() {
        _recommendation = recommendation;
        _show3D = false;
        _selectedProposal = 0;
        _savedOutfitId = null;
        _customGarmentIds = null;
        _worn = false;
        _step = _Step.result;
      });
      ref.invalidate(lastRecommendationProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiException.fromDio(e).message;
        _step = _Step.setup;
      });
    }
  }

  Future<void> _sendFeedback(String action) async {
    final reco = _recommendation;
    if (reco == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/recommendations/${reco.id}/feedback',
            data: {'action': action},
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Merci pour ton retour')));
      }
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> _wearIt() async {
    final reco = _recommendation;
    if (reco == null || reco.proposals.isEmpty) return;
    if (_worn) {
      setState(() => _step = _Step.feedback);
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final proposal = reco.proposals[_selectedProposal];
    try {
      if (_savedOutfitId == null) {
        final saved = await ref
            .read(apiClientProvider)
            .dio
            .post(
              '/outfits',
              data: {
                'name':
                    'Tenue ${reco.destinationLabel ?? reco.originLabel ?? ''}',
                'garment_ids': _customGarmentIds ?? proposal.garmentIds,
              },
            );
        _savedOutfitId = saved.data['id'] as String;
        if (!mounted) return;
        if (mounted) {
          ref.invalidate(savedOutfitsProvider);
        }
      }
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/outfits/wear',
            data: {
              'outfit_id': _savedOutfitId,
              'garment_ids': _customGarmentIds ?? proposal.garmentIds,
              'destination_label': reco.destinationLabel,
              'activity': reco.activity,
            },
          );
      _worn = true;
      if (!mounted) return;
      ref.invalidate(historyProvider);
      ref.invalidate(wardrobeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bonne journée dans ta tenue !')),
        );
        setState(() => _step = _Step.feedback);
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_show3D) {
              setState(() => _show3D = false);
            } else if (_step == _Step.details || _step == _Step.feedback) {
              setState(() => _step = _Step.result);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(switch (_step) {
          _Step.setup => 'Choisir une tenue',
          _Step.generating => 'Génération',
          _Step.result => _show3D ? 'Vue 3D' : 'Ta tenue est prête',
          _Step.details => 'Détails outfit',
          _Step.feedback => 'Qu’en penses-tu ?',
        }),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null && _step != _Step.setup)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: switch (_step) {
                _Step.setup => _buildSetup(),
                _Step.generating => _buildGenerating(),
                _Step.result => _show3D ? _build3D() : _buildResult(),
                _Step.details => _buildResult(details: true),
                _Step.feedback => _FeedbackPanel(
                  onFeedback: _sendFeedback,
                  onDone: () => context.go('/'),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- Écran 17 : choix -----------------------------------------------------

  Widget _buildSetup() {
    final theme = Theme.of(context);
    final location = ref.watch(locationControllerProvider);
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      children: [
        Text(
          'Indique ton contexte pour une recommandation personnalisée.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.place_outlined,
              color: theme.colorScheme.primary,
            ),
            title: Text(location.label ?? 'Lieu actuel'),
            subtitle: Text(
              location.hasCoordinates
                  ? 'Position détectée'
                  : 'Détection en cours ou ville manuelle',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _choosePlace(destination: false),
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        Card(
          child: ListTile(
            title: const Text('Destination (optionnel)'),
            subtitle: Text(_destinationLabel ?? 'Choisir une destination'),
            leading: const Icon(Icons.place_outlined),
            trailing: _wantsDestination
                ? IconButton(
                    tooltip: 'Retirer la destination',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _wantsDestination = false;
                      _destination = null;
                      _destinationLabel = null;
                    }),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _choosePlace(destination: true),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Date'),
            subtitle: Text('${_date.day}/${_date.month}/${_date.year}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: now.add(const Duration(days: 6)),
              );
              if (date != null && mounted) setState(() => _date = date);
            },
          ),
        ),
        const SizedBox(height: AppTheme.spacingL),
        Text('Activité', style: theme.textTheme.titleSmall),
        TextButton.icon(
          icon: const Icon(Icons.tune),
          label: const Text('Toutes les activités'),
          onPressed: () async {
            final activity = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => ActivityScreen(selected: _activity),
              ),
            );
            if (activity != null && mounted) {
              setState(() => _activity = activity);
            }
          },
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingS,
          children: _activities
              .map(
                (a) => ChoiceChip(
                  label: Text(a.$2),
                  selected: _activity == a.$1,
                  onSelected: (_) => setState(() => _activity = a.$1),
                ),
              )
              .toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppTheme.spacingM),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppTheme.spacingXl),
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Générer ma tenue ✨'),
          onPressed: _generate,
        ),
      ],
    );
  }

  // ---- Écran 18 : génération -------------------------------------------------

  Widget _buildGenerating() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            Text('On te crée une tenue…', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppTheme.spacingL),
            _checkline(theme, 'Analyse de la météo'),
            _checkline(theme, 'Analyse de ta garde-robe'),
            _checkline(theme, 'Sélection des vêtements'),
            _checkline(theme, 'Optimisation du style'),
          ],
        ),
      ),
    );
  }

  Widget _checkline(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 16,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  // ---- Écran 19/20 : résultat -------------------------------------------------

  Widget _buildResult({bool details = false}) {
    final theme = Theme.of(context);
    final reco = _recommendation!;
    final proposal = reco.proposals[_selectedProposal];
    final summary = reco.weatherSummary;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      children: [
        if (reco.destinationLabel != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text('Basée sur la météo à ${reco.destinationLabel}'),
              subtitle: Text(
                '${(summary['min_feels_like_c'] as num?)?.round() ?? '?'}°C – '
                '${(summary['max_feels_like_c'] as num?)?.round() ?? '?'}°C · '
                'pluie ${(((summary['max_precip_probability'] as num?) ?? 0) * 100).round()} %',
              ),
            ),
          ),
        const SizedBox(height: AppTheme.spacingM),
        if (!details)
          _GarmentPreview(garmentIds: _customGarmentIds ?? proposal.garmentIds),
        const SizedBox(height: AppTheme.spacingM),
        if (!details && reco.proposals.length > 1)
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < reco.proposals.length; i++)
                ButtonSegment(
                  value: i,
                  label: Text('Tenue ${reco.proposals[i].rank}'),
                ),
            ],
            selected: {_selectedProposal},
            onSelectionChanged: _saving
                ? null
                : (s) => setState(() {
                    _selectedProposal = s.first;
                    _savedOutfitId = null;
                    _customGarmentIds = null;
                    _worn = false;
                  }),
          ),
        const SizedBox(height: AppTheme.spacingM),
        if (!details)
          OutlinedButton.icon(
            icon: const Icon(Icons.info_outline),
            onPressed: () => setState(() => _step = _Step.details),
            label: const Text('Pourquoi cette tenue ?'),
          ),
        if (details)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pourquoi cette tenue ?',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  ...proposal.explanations.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(e, style: theme.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (details)
          _GarmentDetails(garmentIds: _customGarmentIds ?? proposal.garmentIds),
        const SizedBox(height: AppTheme.spacingM),
        OutlinedButton.icon(
          icon: const Icon(Icons.view_in_ar),
          label: const Text('Voir sur le mannequin 3D'),
          onPressed: () => setState(() {
            _show3D = true;
            _step = _Step.result;
          }),
        ),
        const SizedBox(height: AppTheme.spacingS),
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Je porte cette tenue'),
          onPressed: _saving ? null : _wearIt,
        ),
        const SizedBox(height: AppTheme.spacingM),
        TextButton(
          onPressed: () => setState(() => _step = _Step.feedback),
          child: const Text('Donner mon avis'),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Center(
          child: TextButton(
            onPressed: _saving ? null : _generate,
            child: const Text('Régénérer'),
          ),
        ),
      ],
    );
  }

  // ---- Écran 21 : mannequin 3D -----------------------------------------------

  Widget _build3D() {
    final theme = Theme.of(context);
    final reco = _recommendation!;
    final proposal = reco.proposals[_selectedProposal];
    final presentation =
        ref.read(authControllerProvider).user?.mannequinPresentation ??
        'female';

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      children: [
        MannequinViewer(
          presentation: presentation,
          garments: (ref.watch(wardrobeProvider).asData?.value ?? <Garment>[])
              .where(
                (g) =>
                    (_customGarmentIds ?? proposal.garmentIds).contains(g.id),
              )
              .toList(),
          height: 440,
        ),
        const SizedBox(height: 12),
        const Text('Représentation générique par catégorie et couleur.'),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Changer une pièce'),
          onPressed: () async {
            final changed = await context.push<List<String>>(
              '/mannequin',
              extra: _customGarmentIds ?? proposal.garmentIds,
            );
            if (!mounted || changed == null) return;
            setState(() {
              _customGarmentIds = changed;
              _savedOutfitId = null;
              _worn = false;
            });
          },
        ),
        if (_customGarmentIds != null)
          const Text(
            'Tenue adaptée : les explications concernent la proposition initiale.',
          ),
        const SizedBox(height: AppTheme.spacingS),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rotate_right,
              size: 16,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: 4),
            Text('360°', style: theme.textTheme.bodySmall),
            const SizedBox(width: AppTheme.spacingM),
            Icon(Icons.zoom_in, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: 4),
            Text('Zoom', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        _GarmentChips(garmentIds: _customGarmentIds ?? proposal.garmentIds),
        const SizedBox(height: AppTheme.spacingL),
        FilledButton.icon(
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Je porte cette tenue'),
          onPressed: _saving ? null : _wearIt,
        ),
        TextButton(
          onPressed: () => setState(() => _show3D = false),
          child: const Text('Retour aux détails'),
        ),
      ],
    );
  }
}

/// Aperçu vertical des pièces de la proposition (maquette écran 19).
class _GarmentPreview extends ConsumerWidget {
  const _GarmentPreview({required this.garmentIds});

  final List<String> garmentIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.watch(wardrobeProvider);
    final theme = Theme.of(context);
    return wardrobe.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => AppErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(wardrobeProvider),
      ),
      data: (garments) {
        final byId = {for (final g in garments) g.id: g};
        return SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: garmentIds.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppTheme.spacingS),
            itemBuilder: (context, i) {
              final garment = byId[garmentIds[i]];
              final imageUrl = garment != null && garment.images.isNotEmpty
                  ? garment.images.first.downloadUrl
                  : null;
              return Container(
                width: 140,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  border: Border.all(
                    color: theme.colorScheme.outline,
                    width: 0.5,
                  ),
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
                                fit: BoxFit.contain,
                                width: double.infinity,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Text('Photo indisponible'),
                                ),
                              )
                            : Center(
                                child: Text(
                                  garment?.name ?? 'Vêtement indisponible',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        garment?.name ?? 'Pièce',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GarmentChips extends ConsumerWidget {
  const _GarmentChips({required this.garmentIds});

  final List<String> garmentIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.watch(wardrobeProvider);
    return wardrobe.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (garments) {
        final byId = {for (final g in garments) g.id: g};
        return Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingS,
          children: [
            for (final id in garmentIds)
              Chip(
                avatar: const Icon(Icons.checkroom, size: 16),
                label: Text(byId[id]?.name ?? 'Pièce'),
              ),
          ],
        );
      },
    );
  }
}

/// Écran 22 — feedback rapide (j'aime / ça va / pas pour moi / trop chaud…).
class _FeedbackPanel extends StatefulWidget {
  const _FeedbackPanel({required this.onFeedback, required this.onDone});
  final Future<void> Function(String) onFeedback;
  final VoidCallback onDone;
  @override
  State<_FeedbackPanel> createState() => _FeedbackPanelState();
}

class _FeedbackPanelState extends State<_FeedbackPanel> {
  String _action = 'like';
  bool _busy = false;
  String? _error;
  static const _actions = [
    ('like', 'J’adore', Icons.favorite_outline),
    ('not_today', 'Pas pour moi', Icons.sentiment_dissatisfied),
    ('too_hot', 'Trop chaud', Icons.wb_sunny_outlined),
    ('too_cold', 'Trop froid', Icons.ac_unit),
    ('dislike_combination', 'Association à revoir', Icons.checkroom_outlined),
    ('change_top', 'Changer le haut', Icons.swap_horiz),
    ('change_bottom', 'Changer le bas', Icons.swap_horiz),
    ('change_shoes', 'Changer les chaussures', Icons.swap_horiz),
  ];
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onFeedback(_action);
      if (mounted) widget.onDone();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Ton avis améliore les prochaines recommandations.'),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in _actions)
            ChoiceChip(
              avatar: Icon(action.$3, size: 18),
              label: Text(action.$2),
              selected: _action == action.$1,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _action = action.$1),
            ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? 'Envoi…' : 'Valider'),
      ),
    ],
  );
}

class _GarmentDetails extends ConsumerWidget {
  const _GarmentDetails({required this.garmentIds});
  final List<String> garmentIds;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(wardrobeProvider)
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => AppErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(wardrobeProvider),
        ),
        data: (garments) => Column(
          children: [
            for (final garment in garments.where(
              (g) => garmentIds.contains(g.id),
            ))
              ListTile(
                leading: const Icon(Icons.checkroom_outlined),
                title: Text(garment.name),
                subtitle: Text(garment.category.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/wardrobe/garment/${garment.id}'),
              ),
          ],
        ),
      );
}
