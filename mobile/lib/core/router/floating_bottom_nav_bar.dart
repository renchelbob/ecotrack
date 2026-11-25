import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

final class const FloatingBottomNavBar({
  required final int currentIndex,
  required final ValueChanged<int> onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const .fromLTRB(24, 6, 24, 16),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SizedBox(
            height: 58,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFFDCDCDC),
                borderRadius: .all(.circular(999)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x141E1E1E),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const .symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: .spaceBetween,
                  children: [
                    _NavBarIconTab(
                      label: 'Статистика',
                      icon: LucideIcons.chartColumnBig,
                      isSelected: currentIndex == 0,
                      onTap: () => onTap(0),
                    ),
                    _NavBarIconTab(
                      label: 'Калькулятор',
                      icon: LucideIcons.calculator,
                      isSelected: currentIndex == 1,
                      onTap: () => onTap(1),
                    ),
                    _NavBarIconTab(
                      label: 'Главная',
                      icon: LucideIcons.house,
                      isSelected: currentIndex == 2,
                      onTap: () => onTap(2),
                    ),
                    _NavBarIconTab(
                      label: 'Магазин',
                      icon: LucideIcons.store,
                      isSelected: currentIndex == 3,
                      onTap: () => onTap(3),
                    ),
                    _NavBarIconTab(
                      label: 'Профиль',
                      icon: LucideIcons.settings,
                      isSelected: currentIndex == 4,
                      onTap: () => onTap(4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final class const _NavBarIconTab({
  required final String label,
  required final IconData icon,
  required final bool isSelected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: label,
    child: Tooltip(
      message: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFBDBDBD)
                      : Colors.transparent,
                  shape: .circle,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? EcoColors.inkPrimary
                      : const Color(0xFF2B2B2B),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
