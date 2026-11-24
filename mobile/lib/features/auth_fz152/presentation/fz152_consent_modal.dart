import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:flutter/material.dart';

class Fz152ConsentModal extends StatefulWidget {
  const Fz152ConsentModal({super.key, required this.onConsentConfirmed});

  final void Function(bool pdn, bool telemetry) onConsentConfirmed;

  static Future<void> show(
    BuildContext context, {
    required void Function(bool pdn, bool telemetry) onConfirmed,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: EcoColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Fz152ConsentModal(onConsentConfirmed: onConfirmed),
  );

  @override
  State<Fz152ConsentModal> createState() => _Fz152ConsentModalState();
}

class _Fz152ConsentModalState extends State<Fz152ConsentModal> {
  bool _pdnConsent = true;
  bool _telemetryConsent = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 24,
      right: 24,
      top: 24,
      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.shield_outlined,
                color: EcoColors.primaryGreen,
                size: 28,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Согласие на обработку данных (152-ФЗ)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: EcoColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'В соответствии с Федеральным законом № 152-ФЗ «О персональных данных», EcoTrack обеспечивает локализацию баз данных на территории РФ и дает вам полный контроль над вашими данными.',
            style: TextStyle(
              fontSize: 13,
              color: EcoColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: EcoColors.primaryGreen,
            title: const Text(
              'Обработка данных аккаунта и эко-активности (Обязательно)',
              style: TextStyle(fontSize: 13, color: EcoColors.textPrimary),
            ),
            subtitle: const Text(
              'Необходимо для подсчета шагов, расчета CO₂ и начисления баллов',
              style: TextStyle(fontSize: 11, color: EcoColors.textSecondary),
            ),
            value: _pdnConsent,
            onChanged: (val) {
              setState(() => _pdnConsent = val ?? false);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: EcoColors.primaryGreen,
            title: const Text(
              'Обезличенная телеметрия и аналитика (Опционально)',
              style: TextStyle(fontSize: 13, color: EcoColors.textPrimary),
            ),
            subtitle: const Text(
              'Помогает нам улучшать точность классификатора транспорта',
              style: TextStyle(fontSize: 11, color: EcoColors.textSecondary),
            ),
            value: _telemetryConsent,
            onChanged: (val) {
              setState(() => _telemetryConsent = val ?? false);
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _pdnConsent
                ? () {
                    Navigator.of(context).pop();
                    widget.onConsentConfirmed(_pdnConsent, _telemetryConsent);
                  }
                : null,
            child: const Text('Принять и продолжить'),
          ),
        ],
      ),
    ),
  );
}
