import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
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
      padding: const .fromLTRB(12, 6, 12, 12),
      child: SizedBox(
        height: 76,
        child: Stack(
          alignment: .topCenter,
          clipBehavior: .none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 64,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: EcoColors.surfacePrimary,
                  borderRadius: .all(.circular(32)),
                  border: .fromBorderSide(
                    BorderSide(color: EcoColors.borderMuted, width: 1.5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x141E1E1E),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const .symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      _NavBarTab(
                        label: 'Статистика',
                        icon: LucideIcons.chartBar,
                        isSelected: currentIndex == 0,
                        onTap: () => onTap(0),
                      ),
                      _NavBarTab(
                        label: 'Карта',
                        icon: LucideIcons.mapPin,
                        isSelected: currentIndex == 1,
                        onTap: () => onTap(1),
                      ),
                      const SizedBox(width: 72),
                      _NavBarTab(
                        label: 'Магазин',
                        icon: LucideIcons.shoppingBag,
                        isSelected: currentIndex == 3,
                        onTap: () => onTap(3),
                      ),
                      _NavBarTab(
                        label: 'Профиль',
                        icon: LucideIcons.user,
                        isSelected: currentIndex == 4,
                        onTap: () => onTap(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: _HomeDomeTab(
                isSelected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const _NavBarTab({
  required final String label,
  required final IconData icon,
  required final bool isSelected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? EcoColors.inkPrimary
        : EcoColors.inkSecondary;
    return Expanded(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: const .all(.circular(24)),
            child: Padding(
              padding: const .symmetric(horizontal: 2, vertical: 6),
              child: Column(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: .scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: EcoTypography.labelSmall.copyWith(
                        fontSize: 10.5,
                        color: foreground,
                        fontWeight: isSelected ? .w700 : .w500,
                      ),
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

final class const _HomeDomeTab({
  required final bool isSelected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final background = isSelected
        ? EcoColors.inkPrimary
        : EcoColors.surfaceSubtle;
    final foreground = isSelected
        ? EcoColors.surfacePrimary
        : EcoColors.inkPrimary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Главная',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: background,
                shape: .circle,
                border: const .fromBorderSide(
                  BorderSide(color: EcoColors.inkPrimary, width: 1.5),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F1E1E1E),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: .center,
                mainAxisSize: .min,
                children: [
                  Icon(LucideIcons.house, size: 22, color: foreground),
                  const SizedBox(height: 2),
                  Text(
                    'Главная',
                    maxLines: 1,
                    style: EcoTypography.labelSmall.copyWith(
                      fontSize: 10,
                      height: 1.1,
                      color: foreground,
                      fontWeight: .w700,
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
