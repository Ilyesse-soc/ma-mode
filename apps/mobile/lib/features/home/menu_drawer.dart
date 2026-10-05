import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// Drawer latéral (maquette écran 8) : profil + navigation rapide.
class MenuDrawer extends ConsumerWidget {
  const MenuDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    (user?.firstName.isNotEmpty == true
                            ? user!.firstName[0]
                            : '?')
                        .toUpperCase(),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingM),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go('/?tab=profile');
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.firstName ?? '',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          'Voir mon profil',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer le menu',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingL),
            _item(context, Icons.home_outlined, 'Accueil', '/'),
            _item(
              context,
              Icons.checkroom_outlined,
              'Garde-robe',
              '/?tab=wardrobe',
            ),
            _item(
              context,
              Icons.auto_awesome_outlined,
              'Choisir une tenue',
              '/outfit-flow',
            ),
            _item(context, Icons.history, 'Historique', '/history'),
            _item(
              context,
              Icons.bar_chart_outlined,
              'Statistiques',
              '/statistics',
            ),
            _item(context, Icons.explore_outlined, 'Explorer', '/?tab=explore'),
            _item(context, Icons.tune, 'Paramètres', '/?tab=profile'),
            _item(context, Icons.help_outline, 'Aide', '/help'),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    String? route,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        if (route != null) {
          route.startsWith('/?') || route == '/'
              ? context.go(route)
              : context.push(route);
        }
      },
    );
  }
}
