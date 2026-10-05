import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

class AccountActionScreen extends ConsumerStatefulWidget {
  const AccountActionScreen({
    super.key,
    this.action = 'verify',
    this.token = '',
  });
  final String action, token;
  @override
  ConsumerState<AccountActionScreen> createState() => _AccountActionState();
}

class _AccountActionState extends ConsumerState<AccountActionScreen> {
  late final TextEditingController _token = TextEditingController(
    text: widget.token,
  );
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _token.text.trim().isEmpty) return;
    final reset = widget.action == 'reset';
    if (reset && _password.text.length < 10) {
      setState(() => _error = 'Utilise au moins 10 caractères.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post(
            reset ? '/auth/password-reset/confirm' : '/auth/verify-email',
            data: {
              'token': _token.text.trim(),
              if (reset) 'new_password': _password.text,
            },
          );
      _token.clear();
      _password.clear();
      if (reset) {
        await ref.read(tokenStorageProvider).clear();
        await ref.read(authControllerProvider.notifier).expireSession();
      }
      if (!mounted) return;
      context.go('/auth/login');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reset
                ? 'Mot de passe modifié. Reconnecte-toi.'
                : 'Email vérifié. Tu peux te connecter.',
          ),
        ),
      );
    } on DioException catch (error) {
      if (mounted) setState(() => _error = ApiException.fromDio(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.action == 'reset'
            ? 'Nouveau mot de passe'
            : 'Vérifier mon email',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Utilise le lien ou le code reçu par email. Le code est limité dans le temps et utilisable une seule fois.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _token,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Code de validation'),
        ),
        if (widget.action == 'reset') ...[
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Nouveau mot de passe',
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Validation…' : 'Valider'),
        ),
      ],
    ),
  );
}
