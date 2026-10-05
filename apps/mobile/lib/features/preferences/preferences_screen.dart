import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';

/// Écran 6 — Tes préférences : styles, températures, couleurs. Skippable.
class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key, this.fromRegister = false});

  final bool fromRegister;

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  static const _styleOptions = [
    'Classique',
    'Streetwear',
    'Sport',
    'Élégant',
    'Minimaliste',
    'Vintage',
  ];
  static const _colorOptions = [
    ('Noir', 'black'),
    ('Blanc', 'white'),
    ('Gris', 'grey'),
    ('Beige', 'beige'),
    ('Bleu', 'navy'),
    ('Marron', 'brown'),
  ];

  final Set<String> _styles = {};
  final Set<String> _likedColors = {};
  double _coldThreshold = 12;
  double _hotThreshold = 24;
  bool _busy = false;
  bool _loaded = false;
  bool _loadSucceeded = false;
  double _temperatureOffset = 0;
  String? _error;
  List<String> _avoidedColors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loaded = false;
      _loadSucceeded = false;
    });
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/me/preferences');
      final data = resp.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _styles.clear();
        _likedColors.clear();
        _temperatureOffset = 0;
        _styles.addAll((data['preferred_styles'] as List).cast<String>());
        _likedColors.addAll((data['liked_colors'] as List).cast<String>());
        _avoidedColors = (data['avoided_colors'] as List).cast<String>();
        _coldThreshold =
            (data['cold_threshold_celsius'] as num?)?.toDouble() ?? 12;
        _hotThreshold =
            (data['hot_threshold_celsius'] as num?)?.toDouble() ?? 24;
        _loaded = true;
        _loadSucceeded = true;
      });
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiException.fromDio(e).message;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_coldThreshold >= _hotThreshold) {
      setState(
        () => _error =
            'Le seuil de froid doit être inférieur au seuil de chaleur.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .put(
            '/me/preferences',
            data: {
              'preferred_styles': _styles.toList(),
              'liked_colors': _likedColors.toList(),
              'avoided_colors': _avoidedColors,
              'cold_threshold_celsius': _coldThreshold,
              'hot_threshold_celsius': _hotThreshold,
            },
          );
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiException.fromDio(e).message;
          _busy = false;
        });
      }
      return;
    }
    if (!await _completeStep()) return;
    if (mounted) {
      if (widget.fromRegister ||
          GoRouterState.of(context).uri.queryParameters['from'] == 'register') {
        context.go('/');
      } else {
        context.pop();
      }
    }
  }

  Future<bool> _completeStep() async {
    if (ref
            .read(authControllerProvider)
            .user
            ?.onboardingSteps
            .contains('preferences') ==
        true) {
      return true;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeOnboardingStep('preferences');
      return mounted;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return false;
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    if (!await _completeStep() || !mounted) return;
    final fromRegister =
        widget.fromRegister ||
        GoRouterState.of(context).uri.queryParameters['from'] == 'register';
    if (fromRegister) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tes préférences')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                children: [
                  if (!_loadSucceeded) ...[
                    Text(
                      _error ?? 'Préférences indisponibles',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                  Text(
                    'Personnalise ton expérience (optionnel).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text('Styles', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppTheme.spacingS),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    runSpacing: AppTheme.spacingS,
                    children: _styleOptions
                        .map(
                          (s) => FilterChip(
                            label: Text(s),
                            selected: _styles.contains(s),
                            onSelected: (sel) => setState(
                              () => sel ? _styles.add(s) : _styles.remove(s),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text('Température', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppTheme.spacingS),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'J\'ai plutôt froid',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'J\'ai plutôt chaud',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Slider(
                    value: _temperatureOffset,
                    min: -10,
                    max: 10,
                    divisions: 20,
                    onChanged: !_loadSucceeded
                        ? null
                        : (value) => setState(() {
                            final delta = value - _temperatureOffset;
                            _coldThreshold = (_coldThreshold - delta)
                                .clamp(-40, 40)
                                .toDouble();
                            _hotThreshold = (_hotThreshold - delta)
                                .clamp(-10, 60)
                                .toDouble();
                            _temperatureOffset = value;
                          }),
                  ),
                  Center(
                    child: Text(
                      'Froid sous ${_coldThreshold.round()} °C · '
                      'Chaud au-dessus de ${_hotThreshold.round()} °C',
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text('Couleurs préférées', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppTheme.spacingS),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    runSpacing: AppTheme.spacingS,
                    children: _colorOptions
                        .map(
                          (c) => Semantics(
                            button: true,
                            selected: _likedColors.contains(c.$2),
                            label: c.$1,
                            child: Tooltip(
                              message: c.$1,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: !_loadSucceeded || _busy
                                    ? null
                                    : () => setState(() {
                                        _likedColors.contains(c.$2)
                                            ? _likedColors.remove(c.$2)
                                            : _likedColors.add(c.$2);
                                      }),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      width: _likedColors.contains(c.$2)
                                          ? 3
                                          : 1,
                                      color: _likedColors.contains(c.$2)
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outline,
                                    ),
                                    color: switch (c.$2) {
                                      'black' => Colors.black,
                                      'white' => Colors.white,
                                      'grey' => Colors.grey,
                                      'beige' => const Color(0xFFCDB79E),
                                      'navy' => const Color(0xFF4A567A),
                                      _ => Colors.brown,
                                    },
                                  ),
                                  child: _likedColors.contains(c.$2)
                                      ? Icon(
                                          Icons.check,
                                          size: 18,
                                          color:
                                              c.$2 == 'white' || c.$2 == 'beige'
                                              ? Colors.black
                                              : Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppTheme.spacingXl),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy || !_loadSucceeded ? null : _save,
                    child: const Text('Sauvegarder'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _skip,
                    child: const Text('Passer'),
                  ),
                ],
              ),
      ),
    );
  }
}
