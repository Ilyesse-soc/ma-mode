import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// Écran d'accueil auth (après onboarding) — maquette : logo + 2 CTA.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Icon(Icons.checkroom, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: AppTheme.spacingL),
              Text(
                'Dressly',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingM),
              Text(
                'Ta garde-robe, la météo, ta destination.\nLa bonne tenue, chaque jour.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 3),
              FilledButton(
                onPressed: () => context.push('/auth/register'),
                child: const Text('Créer un compte'),
              ),
              const SizedBox(height: AppTheme.spacingM),
              OutlinedButton(
                onPressed: () => context.push('/auth/login'),
                child: const Text('Se connecter'),
              ),
              const SizedBox(height: AppTheme.spacingM),
            ],
          ),
        ),
      ),
    );
  }
}
