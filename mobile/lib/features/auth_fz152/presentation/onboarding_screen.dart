import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/fz152_consent_modal.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<({String title, String subtitle, IconData icon})> _pages = const [
    (
      title: '🌱 EcoTrack — Эко-след под контролем',
      subtitle:
          'Отслеживай свой углеродный след, формируй зеленые привычки и помогай планете каждый день.',
      icon: Icons.eco_outlined,
    ),
    (
      title: '🚶‍♂️ Шаги и умный учет транспорта',
      subtitle:
          'Приложение автоматически считает пройденные пешком шаги и сэкономленный CO₂ вместо поездок на авто.',
      icon: Icons.directions_walk,
    ),
    (
      title: '🎁 Награды, подарки и 152-ФЗ',
      subtitle:
          'Обменивай эко-баллы на скидки у партнеров. Ваши персональные данные защищены законом 152-ФЗ.',
      icon: Icons.card_giftcard_outlined,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Show 152-FZ Consent Modal before proceeding to Login / Home
      Fz152ConsentModal.show(
        context,
        onConfirmed: (pdn, telemetry) {
          context.go('/login');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: () => context.go('/login'),
              child: const Text(
                'Пропустить',
                style: TextStyle(color: EcoColors.textSecondary),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: EcoColors.surfaceVariant,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: EcoColors.primaryGreen,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          page.icon,
                          size: 64,
                          color: EcoColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        page.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: EcoColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        page.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: EcoColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? EcoColors.primaryGreen
                      : EcoColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onNext,
                child: Text(
                  _currentPage == _pages.length - 1 ? 'Начать' : 'Далее',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
