import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/auth_fz152/presentation/auth_bloc.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/profile_social/presentation/profile_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  void _showFriendQrModal(BuildContext context, String friendCode) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoColors.surface,
        title: const Text('Пригласить эко-друга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: 'ecotrack://friend/$friendCode',
                size: 180.0,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Друг может отсканировать этот QR-код для добавления в рейтинг:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: EcoColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Text(
              friendCode,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: EcoColors.primaryGreenLight,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: friendCode));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Код друга скопирован!')),
              );
            },
            child: const Text('Скопировать код'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoColors.surface,
        title: const Text('Удаление аккаунта (152-ФЗ)'),
        content: const Text(
          'В соответствии со ст. 21 Федерального закона № 152-ФЗ «О персональных данных», ваши данные будут безвозвратно удалены из облачных баз данных и локального хранилища устройства.',
          style: TextStyle(fontSize: 13, color: EcoColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: EcoColors.errorRed,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await context.read<ProfileCubit>().deleteAccount();
              if (context.mounted) {
                await context.read<AuthCubit>().logout();
                if (context.mounted) {
                  context.go('/login');
                }
              }
            },
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Профиль и настройки',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    body: BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) => switch (state) {
        ProfileLoading() => const Center(
          child: CircularProgressIndicator(color: EcoColors.primaryGreen),
        ),
        ProfileFailure(error: final err) => Center(
          child: Text(err.uiMessageRu),
        ),
        ProfileLoaded(:final profile) => _buildContent(context, profile),
      },
    ),
  );

  Widget _buildContent(
    BuildContext context,
    UserProfile profile,
  ) => SingleChildScrollView(
    padding: const EdgeInsets.all(20.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // User Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: EcoColors.primaryGreen,
                  child: Icon(Icons.person, size: 36, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.email.isNotEmpty
                            ? profile.email
                            : profile.phoneMasked,
                        style: const TextStyle(
                          color: EcoColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: EcoColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: EcoColors.primaryGreen),
                        ),
                        child: Text(
                          'Баланс: ${profile.pointsBalance} баллов',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: EcoColors.primaryGreenLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Friend Code
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.qr_code,
              color: EcoColors.primaryGreenLight,
            ),
            title: const Text(
              'Мой код эко-друга',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              profile.friendCode,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            trailing: const Icon(Icons.share_outlined),
            onTap: () => _showFriendQrModal(context, profile.friendCode),
          ),
        ),
        const SizedBox(height: 16),

        // Vehicle Card
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.directions_car_outlined,
              color: EcoColors.accentBlue,
            ),
            title: const Text(
              'Мой автомобиль (базовый расход)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${profile.vehicle.name} • ${profile.vehicle.litersPer100Km} л/100 км',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
        const SizedBox(height: 16),

        // Shortcut to Recycling Map
        Card(
          child: ListTile(
            leading: const Icon(Icons.recycling, color: EcoColors.primaryGreen),
            title: const Text(
              'Карта пунктов РСО',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Найти ближайший контейнер раздельного сбора'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/map'),
          ),
        ),
        const SizedBox(height: 24),

        // 152-FZ Privacy & Security
        const Text(
          'Конфиденциальность и 152-ФЗ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.download_outlined,
                  color: EcoColors.textSecondary,
                ),
                title: const Text('Выгрузка моих данных (JSON)'),
                subtitle: const Text('Статья 14 152-ФЗ (Право на доступ)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.read<ProfileCubit>().exportData();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Архив данных успешно сформирован'),
                      ),
                    );
                  }
                },
              ),
              const Divider(height: 1, color: EcoColors.divider),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: EcoColors.errorRed,
                ),
                title: const Text(
                  'Удаление аккаунта (Право на забвение)',
                  style: TextStyle(color: EcoColors.errorRed),
                ),
                subtitle: const Text('Статья 21 152-ФЗ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDeleteAccountDialog(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Logout Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: EcoColors.divider),
          ),
          icon: const Icon(Icons.logout, color: Colors.white70),
          label: const Text(
            'Выйти из аккаунта',
            style: TextStyle(color: Colors.white),
          ),
          onPressed: () async {
            await context.read<AuthCubit>().logout();
            if (context.mounted) {
              context.go('/login');
            }
          },
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}
