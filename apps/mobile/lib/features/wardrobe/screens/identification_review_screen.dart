import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

/// Review never writes proposed garment fields without the user's decision.
class IdentificationReviewScreen extends ConsumerStatefulWidget {
  const IdentificationReviewScreen({
    super.key,
    required this.garmentId,
    required this.result,
  });
  final String garmentId;
  final Map<String, dynamic> result;
  @override
  ConsumerState<IdentificationReviewScreen> createState() =>
      _IdentificationReviewScreenState();
}

class _IdentificationReviewScreenState
    extends ConsumerState<IdentificationReviewScreen> {
  late Map<String, dynamic> _result = widget.result;
  int _index = 0;
  bool _help = false, _busy = false;
  String? _error;
  String _helpField = 'brand';
  final _answer = TextEditingController();
  List<Map<String, dynamic>> get _candidates =>
      ((_result['candidates'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  static const questions = {
    'brand': 'Quelle est la marque ?',
    'reference': 'Quelle référence lis-tu sur l’étiquette ?',
    'color': 'Quelle est la couleur exacte ?',
    'name': 'Comment décrirais-tu ce vêtement ?',
    'category_slug': 'Catégorie (ex. hoodie, bomber, jeans)',
    'department': 'Rayon homme / femme / mixte',
  };
  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _refine(String field) async {
    if (_answer.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/garments/${widget.garmentId}/identify/refine',
            data: {field: _answer.text.trim()},
            options: Options(receiveTimeout: const Duration(seconds: 45)),
          );
      if (!mounted) return;
      setState(() {
        _result = Map<String, dynamic>.from(response.data as Map);
        _index = 0;
        _answer.clear();
        _help = _candidates.isEmpty;
      });
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decision(bool accept) async {
    if (_candidates.isEmpty) return;
    final candidate = _candidates[_index];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            '/garments/${widget.garmentId}/candidates/${candidate['id']}/${accept ? 'confirm' : 'reject'}',
            data: accept ? {'apply_fields': false} : null,
          );
      if (!mounted) return;
      if (accept) {
        Navigator.pop(context, candidate);
        return;
      }
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/garments/${widget.garmentId}/identification');
      if (mounted) {
        setState(() {
          _result = Map<String, dynamic>.from(response.data as Map);
          _index = 0;
          _help = _candidates.isEmpty;
        });
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rejectAll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      for (final candidate in _candidates) {
        await dio.post(
          '/garments/${widget.garmentId}/candidates/${candidate['id']}/reject',
        );
      }
      final response = await dio.get(
        '/garments/${widget.garmentId}/identification',
      );
      if (mounted) {
        setState(() {
          _result = Map<String, dynamic>.from(response.data as Map);
          _index = 0;
          _help = true;
        });
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    final candidate = candidates.isEmpty
        ? null
        : candidates[_index.clamp(0, candidates.length - 1)];
    final proposed = (candidate?['proposed'] as Map?) ?? {};
    final images =
        (proposed['images'] as List?)?.whereType<String>().toList() ?? [];
    final field = _helpField;
    final matches = (proposed['matched_fields'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Identifier ta pièce')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              candidate == null
                  ? 'Je n’ai pas encore trouvé le vêtement exact. Aide-moi avec quelques détails.'
                  : 'Nous pensons avoir trouvé ton vêtement',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            if (candidates.length > 1 && !_help) ...[
              for (var i = 0; i < candidates.length; i++)
                Card(
                  child: ListTile(
                    selected: i == _index,
                    leading: SizedBox(
                      width: 48,
                      height: 56,
                      child:
                          ((candidates[i]['proposed'] as Map)['images']
                                      as List?)
                                  ?.isNotEmpty ==
                              true
                          ? Image.network(
                              ((candidates[i]['proposed'] as Map)['images']
                                      as List)
                                  .first
                                  .toString(),
                              fit: BoxFit.contain,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.fallback,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.checkroom_outlined),
                            )
                          : const Icon(Icons.checkroom_outlined),
                    ),
                    title: Text(
                      ((candidates[i]['proposed'] as Map)['name'] ??
                              'Informations extraites')
                          .toString(),
                    ),
                    subtitle: Text(
                      '${(candidates[i]['proposed'] as Map)['brand'] ?? 'Marque inconnue'} · ${(candidates[i]['proposed'] as Map)['provider'] ?? candidates[i]['source']} · ${((candidates[i]['confidence'] as num) * 100).round()} %',
                    ),
                    onTap: _busy ? null : () => setState(() => _index = i),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            if (candidate != null && !_help) ...[
              if (images.isNotEmpty)
                SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      images.first,
                      fit: BoxFit.contain,
                      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.checkroom_outlined, size: 64),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (proposed['brand'] != null)
                Text(
                  proposed['brand'].toString(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              Text(
                (proposed['name'] ??
                        proposed['category_slug'] ??
                        'Informations extraites')
                    .toString(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (proposed['color'] != null) Text(proposed['color'].toString()),
              if (proposed['reference'] != null)
                Text('Référence : ${proposed['reference']}'),
              Text('Source : ${proposed['provider'] ?? candidate['source']}'),
              const SizedBox(height: 14),
              Text(
                proposed['confidence_kind'] == 'evidence_match'
                    ? '${matches.length} critère(s) concordant(s) · indice ${((candidate['confidence'] as num) * 100).round()} %'
                    : candidate['source'] == 'manual'
                    ? 'Informations fournies par toi'
                    : 'Estimation de lecture IA : ${((candidate['confidence'] as num) * 100).round()} %',
              ),
              const SizedBox(height: 6),
              Text(
                'Cet indice ne garantit pas l’identité du produit. Vérifie la référence et l’image.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : () => _decision(true),
                child: const Text('Oui, c’est celui-ci'),
              ),
              if (candidates.length > 1)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                          () => _index = (_index + 1) % candidates.length,
                        ),
                  child: Text(
                    'Voir d’autres résultats (${_index + 1}/${candidates.length})',
                  ),
                ),
              TextButton(
                onPressed: _busy ? null : () => _decision(false),
                child: const Text('Ce n’est pas lui'),
              ),
              TextButton(
                onPressed: _busy ? null : _rejectAll,
                child: const Text('Aucun ne correspond'),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!_help)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => setState(() => _help = true),
                icon: const Icon(Icons.help_outline),
                label: const Text('Affiner la recherche'),
              ),
            if (_help || candidate == null) ...[
              const Text(
                'Ajoute seulement l’information qui manque. Tes précédentes photos et réponses sont conservées.',
              ),
              const SizedBox(height: 20),
              ...[
                DropdownButtonFormField<String>(
                  initialValue: _helpField,
                  decoration: const InputDecoration(
                    labelText: 'Détail à compléter',
                  ),
                  items: questions.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  isExpanded: true,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _helpField = v!;
                          _answer.clear();
                        }),
                ),
                const SizedBox(height: 12),
                if (field == 'department')
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Rayon'),
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Homme')),
                      DropdownMenuItem(value: 'female', child: Text('Femme')),
                      DropdownMenuItem(value: 'unisex', child: Text('Mixte')),
                    ],
                    onChanged: _busy ? null : (v) => _answer.text = v ?? '',
                  )
                else
                  TextField(
                    key: ValueKey(field),
                    controller: _answer,
                    maxLength: field == 'category_slug'
                        ? 64
                        : (field == 'reference' || field == 'name')
                        ? 160
                        : field == 'color'
                        ? 60
                        : 120,
                    decoration: InputDecoration(labelText: questions[field]),
                  ),
                FilledButton(
                  onPressed: _busy ? null : () => _refine(field),
                  child: Text(
                    _busy ? 'Recherche du produit…' : 'Compléter et rechercher',
                  ),
                ),
              ],
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, {'action': 'label'}),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Photographier la référence sur l’étiquette'),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, {'action': 'photo'}),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Ajouter une photo du vêtement ou du logo'),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, {'action': 'import'}),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Ajouter une capture supplémentaire'),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, {'action': 'barcode'}),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Compléter avec le code-barres'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, {
                        'action': 'manual',
                        'proposed': _result['evidence'],
                      }),
                child: const Text('Terminer avec mes informations'),
              ),
              if (candidate != null)
                TextButton(
                  onPressed: () => setState(() => _help = false),
                  child: const Text('Revoir les résultats'),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(context, {
                      'action': 'manual',
                      'proposed': _result['evidence'],
                    }),
              child: const Text('Enregistrer comme vêtement personnalisé'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(context, {
                      'action': 'approximate',
                      'proposed': _result['evidence'],
                    }),
              child: const Text('Continuer avec une version approchée'),
            ),
          ],
        ),
      ),
    );
  }
}
