import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/network/api_client.dart';
import 'package:dio/dio.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

/// Écran 24 — Profil & paramètres : profil, préférences, stats, destinations,
/// notifications, thème, langue, confidentialité, export RGPD, suppression.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeControllerProvider);
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          children: [
            if (user != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      user.firstName.isEmpty
                          ? '?'
                          : user.firstName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(user.firstName),
                  subtitle: Text(
                    user.emailVerified
                        ? user.email
                        : '${user.email} · email non vérifié',
                  ),
                ),
              ),
            const SizedBox(height: AppTheme.spacingM),
            _tile(
              context,
              Icons.tune,
              'Mes préférences',
              'Styles, couleurs, températures',
              () => context.push('/preferences'),
            ),
            _tile(
              context,
              Icons.bar_chart_outlined,
              'Mes statistiques',
              null,
              () => context.push('/statistics'),
            ),
            _tile(
              context,
              Icons.history,
              'Historique',
              null,
              () => context.push('/history'),
            ),
            _tile(
              context,
              Icons.notifications_outlined,
              'Notifications',
              'Alertes pluie, tenue du jour',
              () => _editNotifications(context, ref),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Mode sombre'),
              value: themeMode == ThemeMode.dark,
              onChanged: (v) =>
                  ref.read(themeControllerProvider.notifier).setDark(v),
            ),
            const ListTile(
              leading: Icon(Icons.language),
              title: Text('Langue'),
              subtitle: Text('Français'),
            ),
            _tile(
              context,
              Icons.place_outlined,
              'Mes destinations',
              null,
              () => context.push('/destinations'),
            ),
            _tile(
              context,
              Icons.privacy_tip_outlined,
              'Confidentialité',
              'Données, documents légaux',
              () => context.push('/privacy'),
            ),
            _tile(
              context,
              Icons.download_outlined,
              'Exporter mes données',
              'RGPD',
              () => context.push('/privacy/export'),
            ),
            const Divider(height: AppTheme.spacingXl),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Se déconnecter'),
              onTap: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go('/auth/welcome');
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Supprimer mon compte',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => context.push('/account/delete'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Future<void> _editNotifications(BuildContext context, WidgetRef ref) async {
    bool rain = true, daily = true, temp = true, saving = false;
    String? error;
    String? pushToken;
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .get('/notifications/preferences');
      rain = resp.data['rain_alerts'] as bool? ?? true;
      daily = resp.data['daily_outfit'] as bool? ?? true;
      temp = resp.data['temperature_alerts'] as bool? ?? true;
      pushToken = resp.data['push_token'] as String?;
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiException.fromDio(e).message)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Alertes pluie'),
                subtitle: const Text('« Il pleuvra à partir de 18h… »'),
                value: rain,
                onChanged: (v) => setState(() => rain = v),
              ),
              SwitchListTile(
                title: const Text('Tenue du jour'),
                value: daily,
                onChanged: (v) => setState(() => daily = v),
              ),
              SwitchListTile(
                title: const Text('Alertes température'),
                value: temp,
                onChanged: (v) => setState(() => temp = v),
              ),
              if (error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(apiClientProvider)
                                .dio
                                .put(
                                  '/notifications/preferences',
                                  data: {
                                    'rain_alerts': rain,
                                    'daily_outfit': daily,
                                    'temperature_alerts': temp,
                                    'push_token': pushToken,
                                  },
                                );
                            if (context.mounted) Navigator.of(context).pop();
                          } on DioException catch (e) {
                            if (context.mounted) {
                              setState(() {
                                error = ApiException.fromDio(e).message;
                                saving = false;
                              });
                            }
                          }
                        },
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
