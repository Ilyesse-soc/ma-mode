import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/theme/app_theme.dart';

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

/// Carrousel d'onboarding (3 pages) conforme à la maquette.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.checkroom_outlined,
      title: 'Une garde-robe intelligente',
      subtitle:
          'Tes vêtements et photos sont conservés dans ton compte. La reconnaissance IA des photos reste optionnelle.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_outlined,
      title: 'Des recommandations',
      subtitle:
          'Adaptées à la météo, tes activités et ton style. Tes tenues et retours sont enregistrés pour ton historique.',
    ),
    _OnboardingPage(
      icon: Icons.public_outlined,
      title: 'Partout dans le monde',
      subtitle:
          'Choisis une ville ou autorise ta position à la demande. Le GPS sert à déterminer ta commune et la météo ; seules des coordonnées arrondies sont enregistrées.',
    ),
  ];

  Future<void> _finish() async {
    await Hive.box<String>('settings_cache').put('onboarding_seen', '1');
    if (mounted) context.go('/auth/register');
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _pageController.nextPage(
        duration: AppDurations.medium,
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/image/boarding${_page + 2}.png',
            fit: BoxFit.cover,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x44000000), Color(0xEE000000)],
                stops: [0.35, 0.86],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) {
                        final page = _pages[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            Text(
                              page.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: AppTheme.spacingS),
                            Text(
                              page.subtitle,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: AppTheme.spacingXl),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: const Text('Suivant'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingS),
                  TextButton(onPressed: _finish, child: const Text('Passer')),
                  const SizedBox(height: AppTheme.spacingM),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: AppDurations.fast,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
