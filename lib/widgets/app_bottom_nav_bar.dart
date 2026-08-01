import 'dart:ui';

import 'package:flutter/material.dart';

/// A single destination in [AppBottomNavBar].
class AppNavItem {
  const AppNavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// A floating, pill-style bottom navigation bar.
///
/// Replaces the stock [BottomNavigationBar] with a rounded, elevated
/// island that sits above the screen edge. The selected item's icon
/// sits centered inside a colored circular pill; unselected items
/// stay as plain, muted icons. Each item's [AppNavItem.label] is
/// exposed via a [Tooltip] and [Semantics] for accessibility rather
/// than being laid out inline, since there isn't enough width per
/// column to reveal it without pushing the icon off-center.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final navTheme = Theme.of(context).bottomNavigationBarTheme;
    final barColor = navTheme.backgroundColor ?? Theme.of(context).cardColor;
    final accent = scheme.secondary;
    final unselected = navTheme.unselectedItemColor ?? scheme.onSurface.withOpacity(0.4);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.mirror),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: barColor.withOpacity(0.32)),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavItemButton(
                        item: items[i],
                        selected: i == currentIndex,
                        accent: accent,
                        unselectedColor: unselected,
                        onTap: () => onTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemButton extends StatelessWidget {
  const _NavItemButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.unselectedColor,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final Color accent;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Semantics(
              label: item.label,
              selected: selected,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  size: 24,
                  color: selected ? accent : unselectedColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
