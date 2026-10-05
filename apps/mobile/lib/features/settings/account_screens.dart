import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/widgets/app_widgets.dart';

final exportProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  try {
    final response = await ref
        .watch(apiClientProvider)
        .dio
        .get('/privacy/export');
    return Map<String, dynamic>.from(response.data as Map);
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
});

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Exporter mes données')),
    body: ref
        .watch(exportProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AppErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(exportProvider),
          ),
          data: (data) {
            final json = const JsonEncoder.withIndent('  ').convert(data);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Ton compte, tes préférences, tes vêtements et ton historique sont réunis dans cet export JSON.',
                ),
                const SizedBox(height: 20),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    icon: const Icon(Icons.ios_share),
                    label: const Text(
                      'Enregistrer ou partager le fichier JSON',
                    ),
                    onPressed: () async {
                      final box = buttonContext.findRenderObject() as RenderBox;
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                Uint8List.fromList(utf8.encode(json)),
                                mimeType: 'application/json',
                              ),
                            ],
                            fileNameOverrides: ['dressly-donnees.json'],
                            sharePositionOrigin:
                                box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Partage indisponible. Tu peux copier l’export ci-dessous.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Enregistrer ou partager l’archive ZIP'),
                    onPressed: () async {
                      final box = buttonContext.findRenderObject() as RenderBox;
                      try {
                        final response = await ref
                            .read(apiClientProvider)
                            .dio
                            .get<List<int>>(
                              '/account/export',
                              options: Options(
                                responseType: ResponseType.bytes,
                              ),
                            );
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                Uint8List.fromList(response.data!),
                                mimeType: 'application/zip',
                              ),
                            ],
                            fileNameOverrides: ['dressly-donnees.zip'],
                            sharePositionOrigin:
                                box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Export ZIP indisponible. Réessaie ou utilise le JSON.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copier mon export JSON'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: json));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Export copié')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                SelectableText(
                  json,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            );
          },
        ),
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  Future<void> _document(
    BuildContext context,
    String name,
    String asset,
  ) async {
    final content = await rootBundle.loadString('assets/legal/$asset.md');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(name)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(content),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Confidentialité')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tu peux consulter les informations sur tes données, les exporter et supprimer ton compte.',
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Reconnaissance IA optionnelle'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AiConsentScreen()),
          ),
        ),
        for (final doc in const [
          ('Politique de confidentialité', 'privacy-policy'),
          ('Conditions d’utilisation', 'cgu'),
          ('Mentions légales', 'mentions-legales'),
        ])
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(doc.$1),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _document(context, doc.$1, doc.$2),
          ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Exporter mes données'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/privacy/export'),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Supprimer mon compte'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/account/delete'),
        ),
      ],
    ),
  );
}

final aiConsentProvider = FutureProvider<bool>((ref) async {
  ref.watch(authControllerProvider.select((state) => state.user?.id));
  final response = await ref.watch(apiClientProvider).dio.get('/me/consents');
  return response.data['ai'] == true;
});

class AiConsentScreen extends ConsumerWidget {
  const AiConsentScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Reconnaissance IA')),
    body: ref
        .watch(aiConsentProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => AppErrorView(
            message: 'Impossible de charger ton choix.',
            onRetry: () => ref.invalidate(aiConsentProvider),
          ),
          data: (enabled) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Les photos utilisées pour la reconnaissance sont transmises au fournisseur IA configuré, sans métadonnées EXIF/GPS. La saisie manuelle reste disponible. Ce choix peut être retiré ici.',
              ),
              SwitchListTile(
                title: const Text('Autoriser l’analyse de mes photos'),
                value: enabled,
                onChanged: (value) async {
                  try {
                    await ref
                        .read(apiClientProvider)
                        .dio
                        .put(
                          '/me/consents/ai',
                          data: {'enabled': value, 'version': 'ai-v1'},
                        );
                    ref.invalidate(aiConsentProvider);
                  } on DioException {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Modification non enregistrée. Réessaie.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
  );
}

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _confirmed = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed || _password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(_password.text);
      if (mounted) context.go('/auth/welcome');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Supprimer mon compte')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'La suppression est définitive. Tes sessions seront révoquées et tes données supprimées ou anonymisées.',
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: _busy ? null : () => context.push('/privacy/export'),
          child: const Text('Exporter mes données avant de continuer'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirme ton mot de passe',
          ),
          onChanged: (_) => setState(() {}),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Je comprends que cette action est irréversible'),
          value: _confirmed,
          onChanged: _busy
              ? null
              : (v) => setState(() => _confirmed = v ?? false),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _confirmed && _password.text.isNotEmpty && !_busy
              ? _delete
              : null,
          child: Text(_busy ? 'Suppression…' : 'Supprimer définitivement'),
        ),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aide')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        ExpansionTile(
          title: Text('Comment ajouter un vêtement ?'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Dans Garde-robe, appuie sur Ajouter un vêtement. Tu peux scanner un code-barres, photographier le vêtement ou son étiquette, ou saisir ses caractéristiques. Vérifie les informations avant de les enregistrer.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Comment choisir une tenue ?'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ajoute des hauts, des bas et des chaussures. Ouvre Outfit, choisis ton lieu et ton activité puis génère une tenue. Les explications utilisent les caractéristiques de tes vêtements et la météo.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Sans géolocalisation ?'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Tu peux choisir une ville ou saisir ses coordonnées depuis le lieu actuel. Aucune autorisation GPS n’est nécessaire pour cette option.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Comment gérer mes données ?'),
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Depuis Profil, ouvre Confidentialité pour consulter les documents, copier ton export JSON ou supprimer ton compte avec ton mot de passe.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
