import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/network/api_client.dart';

class FunctionalOnboardingScreen extends ConsumerStatefulWidget {
  const FunctionalOnboardingScreen({super.key});
  @override
  ConsumerState<FunctionalOnboardingScreen> createState() =>
      _FunctionalOnboardingScreenState();
}

class _FunctionalOnboardingScreenState
    extends ConsumerState<FunctionalOnboardingScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _decide(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .put(
            '/me/consents/ai',
            data: {'enabled': enabled, 'version': 'ai-v1'},
          );
      if (!mounted) return;
      await ref
          .read(authControllerProvider.notifier)
          .completeOnboardingStep('consents');
      if (mounted) context.go('/');
    } on DioException catch (e) {
      if (mounted) setState(() => _error = ApiException.fromDio(e).message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ton choix, tes photos')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Icon(Icons.privacy_tip_outlined, size: 52),
          const SizedBox(height: 28),
          Text(
            'Un styliste, à ta façon.',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 18),
          const Text(
            'La reconnaissance IA peut lire une étiquette et analyser tes vêtements. Si tu l’autorises, les photos nettoyées de leurs métadonnées sont envoyées au fournisseur IA configuré.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Tu peux utiliser la garde-robe, le scan et les recommandations sans envoyer de photo à l’IA. Ce choix reste modifiable dans Confidentialité.',
          ),
          TextButton(
            onPressed: () => context.push('/privacy'),
            child: const Text('Lire les détails de confidentialité'),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _busy ? null : () => _decide(true),
            child: Text(
              _busy ? 'Enregistrement…' : 'Autoriser la reconnaissance IA',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : () => _decide(false),
            child: const Text('Continuer sans reconnaissance IA'),
          ),
        ],
      ),
    ),
  );
}
