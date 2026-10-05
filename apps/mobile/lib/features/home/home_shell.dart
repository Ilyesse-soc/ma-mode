import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../explore/explore_screen.dart';
import '../settings/settings_screen.dart';
import '../wardrobe/screens/wardrobe_screen.dart';
import 'home_screen.dart';
import 'menu_drawer.dart';

/// Shell principal : bottom bar 5 entrées (Accueil, Garde-robe, Outfit central,
/// Explorer, Profil) + drawer latéral (maquette écran 8).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index = widget.initialIndex;

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex;
    }
  }

  static const _tabs = [
    HomeScreen(),
    WardrobeScreen(embedded: true),
    SizedBox.shrink(), // Outfit = action centrale, push séparé
    ExploreScreen(),
    SettingsScreen(),
  ];

  void _openOutfitFlow() {
    context.push('/outfit-flow');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      endDrawer: const MenuDrawer(),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outline, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingS,
            vertical: 6,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Accueil',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
              _NavItem(
                icon: Icons.checkroom_outlined,
                activeIcon: Icons.checkroom,
                label: 'Garde-robe',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
              _CenterOutfitButton(onTap: _openOutfitFlow),
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore,
                label: 'Explorer',
                selected: _index == 3,
                onTap: () => setState(() => _index = 3),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profil',
                selected: _index == 4,
                onTap: () => setState(() => _index = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 24),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterOutfitButton extends StatelessWidget {
  const _CenterOutfitButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _NavItem(
    icon: Icons.dry_cleaning_outlined,
    activeIcon: Icons.dry_cleaning,
    label: 'Outfit',
    selected: false,
    onTap: onTap,
  );
}
