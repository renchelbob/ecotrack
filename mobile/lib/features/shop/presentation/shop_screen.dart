import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/theme/eco_theme.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  void _showOrderQrModal(BuildContext context, ShopOrder order) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EcoColors.surface,
        title: Text(order.couponTitle, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: order.qrPayload, size: 180.0),
            ),
            const SizedBox(height: 16),
            const Text(
              'Покажите этот QR-код на кассе или введите промокод:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: EcoColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: EcoColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EcoColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    order.promoCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontSize: 16,
                      color: EcoColors.primaryGreenLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: order.promoCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Промокод скопирован!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchase(BuildContext context, ShopCoupon coupon) async {
    final result = await context.read<ShopCubit>().buyCoupon(coupon);
    switch (result) {
      case Ok(value: final order):
        if (context.mounted) {
          _showOrderQrModal(context, order);
        }
      case Err(error: final err):
        if (context.mounted) {
          EcoErrorBannerPresenter.show(context, err);
        }
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text(
          'Витрина наград',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          BlocBuilder<ShopCubit, ShopState>(
            builder: (context, state) {
              final balance = switch (state) {
                ShopLoaded(userBalance: final b) => b,
                _ => 120,
              };
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Chip(
                  backgroundColor: EcoColors.surfaceVariant,
                  side: const BorderSide(color: EcoColors.primaryGreen),
                  avatar: const Icon(
                    Icons.eco,
                    color: EcoColors.primaryGreen,
                    size: 16,
                  ),
                  label: Text(
                    '$balance б.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        bottom: const TabBar(
          indicatorColor: EcoColors.primaryGreen,
          tabs: [
            Tab(text: 'Купоны партнеров'),
            Tab(text: 'Мои заказы'),
          ],
        ),
      ),
      body: BlocBuilder<ShopCubit, ShopState>(
        builder: (context, state) => switch (state) {
          ShopLoading() => const Center(
            child: CircularProgressIndicator(color: EcoColors.primaryGreen),
          ),
          ShopFailure(error: final err) => Center(child: Text(err.uiMessageRu)),
          ShopLoaded(:final coupons, :final orders) => TabBarView(
            children: [
              _buildCatalogView(context, coupons),
              _buildOrdersView(context, orders),
            ],
          ),
        },
      ),
    ),
  );

  Widget _buildCatalogView(BuildContext context, List<ShopCoupon> coupons) =>
      ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: coupons.length,
        itemBuilder: (context, index) {
          final coupon = coupons[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: EcoColors.accentOrange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-${coupon.discountPercent}%',
                          style: const TextStyle(
                            color: EcoColors.accentOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        coupon.category,
                        style: const TextStyle(
                          color: EcoColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    coupon.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    coupon.partnerName,
                    style: const TextStyle(
                      color: EcoColors.primaryGreenLight,
                      fontSize: 13,
                    ),
                  ),
                  if (coupon.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      coupon.description,
                      style: const TextStyle(
                        color: EcoColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.eco,
                            color: EcoColors.primaryGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${coupon.costPoints} баллов',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () => _handlePurchase(context, coupon),
                        child: const Text('Обменять'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _buildOrdersView(BuildContext context, List<ShopOrder> orders) {
    if (orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: EcoColors.textSecondary,
            ),
            SizedBox(height: 12),
            Text(
              'У вас пока нет активных купонов',
              style: TextStyle(color: EcoColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: EcoColors.surfaceVariant,
              child: Icon(Icons.qr_code, color: EcoColors.primaryGreenLight),
            ),
            title: Text(
              order.couponTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${order.partnerName} • ${order.promoCode}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showOrderQrModal(context, order),
          ),
        );
      },
    );
  }
}
