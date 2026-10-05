import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'photo_screen.dart';
import 'photo_guide_screen.dart';

import '../../../core/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Écran 11 — Ajouter un vêtement : 4 méthodes réelles + formulaire manuel.
class AddGarmentScreen extends ConsumerStatefulWidget {
  const AddGarmentScreen({
    super.key,
    this.initialCategorySlug,
    this.initialGarment,
  });

  final String? initialCategorySlug;
  final Garment? initialGarment;

  @override
  ConsumerState<AddGarmentScreen> createState() => _AddGarmentScreenState();
}

class _AddGarmentScreenState extends ConsumerState<AddGarmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _color = TextEditingController();
  final _size = TextEditingController();
  final _material = TextEditingController();
  final _reference = TextEditingController();
  String? _categorySlug;
  int _warmth = 3;
  bool _waterproof = false;
  bool _windproof = false;
  bool _busy = false;
  bool _formExpanded = false;
  String? _notice;
  String? _draftId;
  String? _candidateId;
  String _season = 'all';
  CapturedPhoto? _photo;
  final Set<String> _styles = {};

  @override
  void dispose() {
    for (final controller in [
      _name,
      _brand,
      _color,
      _size,
      _material,
      _reference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<GarmentCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _categorySlug = widget.initialCategorySlug;
    _formExpanded = widget.initialCategorySlug != null;
    final garment = widget.initialGarment;
    if (garment != null) {
      _draftId = garment.id;
      _categorySlug = garment.category.slug;
      _name.text = garment.name;
      _brand.text = garment.brand ?? '';
      _color.text = garment.color;
      _size.text = garment.size ?? '';
      _material.text = garment.material ?? '';
      _reference.text = garment.reference ?? '';
      _warmth = garment.warmthLevel;
      _waterproof = garment.waterproof;
      _windproof = garment.windproof;
      _season = garment.season;
      _styles.addAll(garment.styles);
      _formExpanded = true;
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ref
          .read(wardrobeRepositoryProvider)
          .categories();
      if (mounted) setState(() => _categories = categories);
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  Future<void> _scanBarcode() async {
    final barcode = await context.push<String>('/wardrobe/scan');
    if (barcode == null || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .post('/garments/identify/barcode', data: {'barcode': barcode});
      if (!mounted) return;
      _draftId = resp.data['garment_id'] as String?;
      final status = resp.data['status'] as String;
      if (status == 'not_found') {
        setState(() {
          _notice = 'Code-barres inconnu — renseigne le vêtement manuellement.';
          _formExpanded = true;
        });
      } else {
        final candidates = (resp.data['candidates'] as List);
        if (candidates.isNotEmpty) {
          final proposed = (candidates.first['proposed'] as Map)
              .cast<String, dynamic>();
          final confidence =
              (candidates.first['confidence'] as num?)?.toDouble() ?? 0.0;
          final accepted = await _showScanResult(proposed, confidence);
          if (!mounted) return;
          _candidateId = accepted ? candidates.first['id'] as String? : null;
          setState(() {
            _name.text = accepted ? (proposed['name'] as String?) ?? '' : '';
            _brand.text = accepted ? (proposed['brand'] as String?) ?? '' : '';
            _reference.text = accepted
                ? (proposed['reference'] as String?) ?? ''
                : '';
            _formExpanded = true;
            _notice = confidence >= 0.85
                ? 'Article trouvé (${(confidence * 100).round()} % de confiance) — vérifie les champs.'
                : 'Nous pensons avoir trouvé ce produit — confirme les détails.';
          });
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _notice = ApiException.fromDio(e).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndAnalyze({required bool labelMode}) async {
    final guide = await Navigator.of(context).push<PhotoGuideChoice>(
      MaterialPageRoute(builder: (_) => PhotoGuideScreen(labelMode: labelMode)),
    );
    if (!mounted || guide == null) return;
    if (guide == PhotoGuideChoice.manual) {
      setState(() => _formExpanded = true);
      return;
    }
    if (guide == PhotoGuideChoice.garment) {
      return _pickAndAnalyze(labelMode: false);
    }
    final photo = await context.push<CapturedPhoto>(
      '/wardrobe/photo?mode=${labelMode ? 'label' : 'garment'}',
    );
    if (photo == null || !mounted) return;
    labelMode = photo.labelMode;
    _photo = photo;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(photo.bytes, filename: photo.name),
      });
      final upload = await dio.post('/media/upload', data: form);
      if (!mounted) return;
      final objectKey = upload.data['object_key'] as String;

      if (_draftId == null) {
        final draft = await ref.read(wardrobeRepositoryProvider).createGarment({
          'category_slug': 'top_other',
          'name': labelMode ? 'Analyse étiquette…' : 'Analyse photo…',
          'color': 'unknown',
          'is_archived': true,
        });
        _draftId = draft.id;
      }

      final attach = await dio.post(
        '/garments/$_draftId/images',
        data: {
          'object_key': objectKey,
          'content_type': upload.data['content_type'],
          'byte_size': upload.data['byte_size'],
          'width': upload.data['width'],
          'height': upload.data['height'],
        },
      );
      final imageId = attach.data['id'] as String;
      final consent = await dio.get('/me/consents');
      var useAi = consent.data['ai'] == true;
      if (!useAi && mounted) {
        useAi =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Reconnaissance IA optionnelle'),
                content: const Text(
                  'La photo nettoyée de ses métadonnées sera envoyée au fournisseur IA '
                  'configuré pour identifier le vêtement. Tu peux saisir les détails '
                  'manuellement et retirer ce choix dans Confidentialité.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Saisie manuelle'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Autoriser l’analyse'),
                  ),
                ],
              ),
            ) ??
            false;
        if (useAi) {
          await dio.put(
            '/me/consents/ai',
            data: {'enabled': true, 'version': 'ai-v1'},
          );
        }
      }
      if (!mounted) return;
      if (!useAi) {
        setState(() {
          _formExpanded = true;
          _notice = 'Photo ajoutée. Complète les détails sans analyse IA.';
        });
        return;
      }
      final endpoint = labelMode
          ? '/garments/$_draftId/identify/label'
          : '/garments/$_draftId/identify/photo';
      final analysis = await dio.post(
        endpoint,
        data: {'image_id': imageId},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      if (!mounted) return;
      setState(() {
        _formExpanded = true;
        _notice = analysis.data['message'] as String?;
      });

      final candidates = (analysis.data['candidates'] as List);
      if (candidates.isNotEmpty) {
        _candidateId = candidates.first['id'] as String?;
        final proposed = (candidates.first['proposed'] as Map)
            .cast<String, dynamic>();
        setState(() {
          _name.text = (proposed['name'] as String?) ?? _name.text;
          _name.text = (proposed['product_name'] as String?) ?? _name.text;
          _size.text = (proposed['size'] as String?) ?? _size.text;
          _brand.text = (proposed['brand'] as String?) ?? _brand.text;
          _color.text = (proposed['color'] as String?) ?? _color.text;
          _material.text = (proposed['material'] as String?) ?? _material.text;
          _reference.text =
              (proposed['reference'] as String?) ?? _reference.text;
          if (_categories.any((c) => c.slug == proposed['category_slug'])) {
            _categorySlug = proposed['category_slug'] as String;
          }
          _formExpanded = true;
          _notice = analysis.data['message'] as String?;
        });
      }
      if (!mounted) return;
      ref.invalidate(wardrobeProvider);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _notice = ApiException.fromDio(e).message;
          _formExpanded = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _notice = e.message;
          _formExpanded = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _showScanResult(
    Map<String, dynamic> proposed,
    double confidence,
  ) async {
    return await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Résultat du scan')),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text('Article trouvé'),
                  const SizedBox(height: 24),
                  Text(
                    proposed['name'] as String? ?? 'Article scanné',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (proposed['brand'] != null)
                    ListTile(
                      title: const Text('Marque'),
                      subtitle: Text(proposed['brand'].toString()),
                    ),
                  if (proposed['reference'] != null)
                    ListTile(
                      title: const Text('Référence'),
                      subtitle: Text(proposed['reference'].toString()),
                    ),
                  Chip(
                    avatar: const Icon(Icons.verified_outlined),
                    label: Text('${(confidence * 100).round()} % de confiance'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Vérifier et ajouter à ma garde-robe'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Choisir manuellement'),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categorySlug == null) {
      setState(() => _notice = 'Choisis une catégorie');
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'category_slug': _categorySlug,
        'name': _name.text.trim(),
        'brand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'color': _color.text.trim().toLowerCase(),
        'size': _size.text.trim().isEmpty ? null : _size.text.trim(),
        'material': _material.text.trim().isEmpty
            ? null
            : _material.text.trim(),
        'reference': _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim(),
        'warmth_level': _warmth,
        'waterproof': _waterproof,
        'windproof': _windproof,
        'season': _season,
        'styles': _styles.toList(),
        'is_archived': false,
      };
      final Garment saved;
      if (_draftId == null) {
        saved = await ref
            .read(wardrobeRepositoryProvider)
            .createGarment(payload);
      } else {
        if (_candidateId != null) {
          await ref
              .read(apiClientProvider)
              .dio
              .post(
                '/garments/$_draftId/candidates/$_candidateId/confirm',
                data: {'apply_fields': false},
              );
          _candidateId = null;
          if (!mounted) return;
        }
        saved = await ref
            .read(wardrobeRepositoryProvider)
            .updateGarment(_draftId!, payload);
      }
      if (!mounted) return;
      ref.invalidate(wardrobeProvider);
      if (mounted) {
        if (widget.initialGarment != null) {
          context.pop();
        } else {
          context.pushReplacement('/wardrobe/garment/${saved.id}');
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } on DioException catch (e) {
      if (mounted) setState(() => _notice = ApiException.fromDio(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialGarment == null
              ? 'Ajouter un vêtement'
              : 'Modifier le vêtement',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingL),
            children: [
              if (widget.initialGarment == null && !_formExpanded) ...[
                _MethodTile(
                  icon: Icons.qr_code_scanner,
                  title: 'Scanner un code-barres',
                  subtitle:
                      'Scanne le code EAN/UPC de l’étiquette ou de l’emballage.',
                  onTap: _busy ? null : _scanBarcode,
                ),
                const SizedBox(height: AppTheme.spacingS),
                _MethodTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Photographier le vêtement',
                  subtitle:
                      'Vêtement entier, bonne lumière et arrière-plan simple.',
                  onTap: _busy ? null : () => _pickAndAnalyze(labelMode: false),
                ),
                const SizedBox(height: AppTheme.spacingS),
                _MethodTile(
                  icon: Icons.label_outline,
                  title: 'Photographier l’étiquette',
                  subtitle:
                      'Lis la marque, la référence et la composition sur l’étiquette intérieure.',
                  onTap: _busy ? null : () => _pickAndAnalyze(labelMode: true),
                ),
                const SizedBox(height: AppTheme.spacingS),
                _MethodTile(
                  icon: Icons.edit_outlined,
                  title: 'Saisie manuelle',
                  subtitle:
                      'Renseigne la marque, le type, la couleur et les autres informations.',
                  onTap: () => setState(() => _formExpanded = !_formExpanded),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: AppTheme.spacingM),
                const LinearProgressIndicator(),
              ],
              if (_notice != null) ...[
                const SizedBox(height: AppTheme.spacingM),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingM),
                    child: Text(_notice!, style: theme.textTheme.bodySmall),
                  ),
                ),
              ],
              if (_formExpanded) ...[
                if (widget.initialGarment == null)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _formExpanded = false),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Choisir une autre méthode d’ajout'),
                  ),
                if (_photo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      height: 180,
                      child: Image.memory(_photo!.bytes, fit: BoxFit.contain),
                    ),
                  ),
                const SizedBox(height: AppTheme.spacingL),
                Text('Styles', style: theme.textTheme.titleSmall),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final style in const [
                      'Classique',
                      'Streetwear',
                      'Sport',
                      'Élégant',
                      'Minimaliste',
                      'Vintage',
                    ])
                      FilterChip(
                        label: Text(style),
                        selected: _styles.contains(style),
                        onSelected: (selected) => setState(() {
                          selected ? _styles.add(style) : _styles.remove(style);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingM),
                DropdownButtonFormField<String>(
                  key: ValueKey(_categorySlug),
                  initialValue: _categorySlug,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: _categories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.slug,
                          child: Text(c.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categorySlug = v),
                ),
                const SizedBox(height: AppTheme.spacingM),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                ),
                const SizedBox(height: AppTheme.spacingM),
                TextFormField(
                  controller: _brand,
                  decoration: const InputDecoration(
                    labelText: 'Marque (optionnel)',
                  ),
                ),
                const SizedBox(height: AppTheme.spacingM),
                TextFormField(
                  controller: _color,
                  decoration: const InputDecoration(
                    labelText: 'Couleur (ex. navy, black, beige)',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Couleur requise'
                      : null,
                ),
                const SizedBox(height: AppTheme.spacingM),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _size,
                        decoration: const InputDecoration(labelText: 'Taille'),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    Expanded(
                      child: TextFormField(
                        controller: _material,
                        decoration: const InputDecoration(labelText: 'Matière'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingM),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(
                    labelText: 'Référence / SKU (optionnel)',
                  ),
                ),
                const SizedBox(height: AppTheme.spacingL),
                DropdownButtonFormField<String>(
                  initialValue: _season,
                  decoration: const InputDecoration(labelText: 'Saison'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Toutes')),
                    DropdownMenuItem(value: 'summer', child: Text('Été')),
                    DropdownMenuItem(value: 'autumn', child: Text('Automne')),
                    DropdownMenuItem(value: 'winter', child: Text('Hiver')),
                    DropdownMenuItem(value: 'spring', child: Text('Printemps')),
                  ],
                  onChanged: (v) => setState(() => _season = v ?? 'all'),
                ),
                const SizedBox(height: AppTheme.spacingM),
                Text('Chaleur : $_warmth/5', style: theme.textTheme.titleSmall),
                Slider(
                  value: _warmth.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  onChanged: (v) => setState(() => _warmth = v.round()),
                ),
                SwitchListTile(
                  title: const Text('Imperméable'),
                  value: _waterproof,
                  onChanged: (v) => setState(() => _waterproof = v),
                ),
                SwitchListTile(
                  title: const Text('Coupe-vent'),
                  value: _windproof,
                  onChanged: (v) => setState(() => _windproof = v),
                ),
                const SizedBox(height: AppTheme.spacingM),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Enregistrer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
