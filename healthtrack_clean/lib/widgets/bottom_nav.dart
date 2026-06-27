import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const _routes = [
    '/dashboard', '/meals', '/exercise', '/analytics', '/profile'
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selColor   = isDark ? AppColors.mint  : AppColors.navy;
    final unselColor = isDark ? const Color(0xFF4A6580) : const Color(0xFFADB8C6);
    final bgColor    = isDark ? AppColors.navDark : AppColors.navLight;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_rounded,          label: 'Home',     idx: 0, current: currentIndex, sel: selColor, unsel: unselColor, routes: _routes),
              _NavItem(icon: Icons.restaurant_rounded,    label: 'Meals',    idx: 1, current: currentIndex, sel: selColor, unsel: unselColor, routes: _routes),
              _NavItem(icon: Icons.directions_run_rounded,label: 'Exercise', idx: 2, current: currentIndex, sel: selColor, unsel: unselColor, routes: _routes),
              _NavItem(icon: Icons.bar_chart_rounded,     label: 'Charts',   idx: 3, current: currentIndex, sel: selColor, unsel: unselColor, routes: _routes),
              _NavItem(icon: Icons.person_rounded,        label: 'Profile',  idx: 4, current: currentIndex, sel: selColor, unsel: unselColor, routes: _routes),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int idx, current;
  final Color sel, unsel;
  final List<String> routes;
  const _NavItem({required this.icon, required this.label, required this.idx,
      required this.current, required this.sel, required this.unsel, required this.routes});

  @override
  Widget build(BuildContext context) {
    final active = idx == current;
    return GestureDetector(
      onTap: () {
        if (!active) Navigator.of(context).pushReplacementNamed(routes[idx]);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: active ? sel.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Icon(icon, color: active ? sel : unsel,
                  size: active ? 26 : 22),
            ),
            const SizedBox(height: 2),
            Text(label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? sel : unsel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}