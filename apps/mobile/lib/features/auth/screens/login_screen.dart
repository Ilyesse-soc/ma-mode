import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text.trim(), _password.text);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _error = 'Entre ton email pour réinitialiser le mot de passe',
      );
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
          .post('/auth/password-reset/request', data: {'email': email});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Si cet email existe, un lien a été envoyé'),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _error = ApiException.fromDio(e).message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestVerification() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(
        () => _error = 'Entre ton email pour recevoir un lien de validation.',
      );
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
          .post('/auth/verification/request', data: {'email': email});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Si une validation est nécessaire, un email sera envoyé.',
            ),
          ),
        );
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = ApiException.fromDio(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/auth/welcome')),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Se connecter',
                          style: theme.textTheme.displaySmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Retrouve ta garde-robe, tes tenues et ton mannequin.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.secondary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? AppColors.surface
                                : AppColors.lightSurface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: theme.dividerColor),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x18000000),
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _email,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.mail_outline),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 18,
                                    horizontal: 16,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null ||
                                        !RegExp(
                                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                        ).hasMatch(v.trim()))
                                    ? 'Email invalide'
                                    : null,
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _password,
                                enabled: !_busy,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_busy) _submit();
                                },
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: 'Mot de passe',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                    horizontal: 16,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Afficher le mot de passe'
                                        : 'Masquer le mot de passe',
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Mot de passe requis'
                                    : null,
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                child: _error == null
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            _error!,
                                            style: TextStyle(
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  child: _busy
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Se connecter'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Theme(
                          data: theme.copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            title: Text(
                              'Aide à la connexion',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            children: [
                              TextButton(
                                onPressed: _busy ? null : _resetPassword,
                                child: const Text('Mot de passe oublié ?'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => context.push(
                                        '/auth/action?action=reset',
                                      ),
                                child: const Text(
                                  'Utiliser mon code de réinitialisation',
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => context.push(
                                        '/auth/action?action=verify',
                                      ),
                                child: const Text(
                                  'Vérifier mon email avec un code',
                                ),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _requestVerification,
                                child: const Text(
                                  'Renvoyer le lien de validation',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Pas de compte ?',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => context.push('/auth/register'),
                              child: const Text('Créer un compte'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
