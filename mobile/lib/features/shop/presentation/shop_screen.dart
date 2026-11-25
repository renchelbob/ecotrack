import 'dart:async';

import 'package:ecotrack_mobile/core/error/eco_error_banner_presenter.dart';
import 'package:ecotrack_mobile/core/theme/eco_colors.dart';
import 'package:ecotrack_mobile/core/theme/eco_typography.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:ecotrack_mobile/features/shop/presentation/shop_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

final class const ShopScreen({super.key}) extends StatefulWidget {
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

final class _ShopScreenState() extends State<ShopScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final bloc = context.read<ShopBloc>();
    if (bloc.state is ShopLoading) {
      bloc.add(const ShopCatalogRequested());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openItemDetail(ShopCatalogItem item) async {
    final bloc = context.read<ShopBloc>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EcoColors.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: .vertical(top: .circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const .fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text(item.title, style: EcoTypography.titleMedium),
              const SizedBox(height: 4),
              if (item.partner case final partner?)
                Text(
                  '${partner.name} · ${partner.isFictionalDisclaimer}',
                  style: EcoTypography.labelSmall,
                ),
              const SizedBox(height: 10),
              Text(item.description, style: EcoTypography.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'Лимит: до ${item.maxPerUserPerDay} шт. в день',
                style: EcoTypography.labelSmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  bloc.add(ShopItemAddedToCart(item));
                  Navigator.of(ctx).pop();
                },
                child: Text('Добавить в корзину за ${item.pricePoints} ★'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<ShopBloc, ShopState>(
    listenWhen: (prev, curr) {
      if (curr is! ShopLoaded) return false;
      if (prev is! ShopLoaded) {
        return curr.bannerError != null || curr.feedbackMessage != null;
      }
      return prev.bannerError != curr.bannerError ||
          prev.feedbackMessage != curr.feedbackMessage;
    },
    listener: (context, state) {
      if (state case final ShopLoaded loaded) {
        if (loaded.bannerError case final err?) {
          EcoErrorBannerPresenter.show(context, err);
          context.read<ShopBloc>().add(const ShopFeedbackCleared());
        } else if (loaded.feedbackMessage case final msg?) {
          EcoTopBannerOverlay.instance.showMessage(msg);
          context.read<ShopBloc>().add(const ShopFeedbackCleared());
        }
      }
    },
    builder: (context, state) => Scaffold(
      backgroundColor: EcoColors.surfacePrimary,
      body: SafeArea(
        child: switch (state) {
          ShopLoading() => const Center(
            child: CircularProgressIndicator(color: EcoColors.inkPrimary),
          ),
          ShopFailure(:final error) => Center(
            child: Padding(
              padding: const .all(24),
              child: Column(
                mainAxisSize: .min,
                children: [
                  Text(error.uiMessageRu, textAlign: .center),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () => context.read<ShopBloc>().add(
                      const ShopCatalogRequested(),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
          ShopLoaded() => _ShopLoadedBody(
            loaded: state,
            searchController: _searchController,
            onItemTap: (item) => unawaited(_openItemDetail(item)),
          ),
        },
      ),
    ),
  );
}

final class const _ShopLoadedBody({
  required final ShopLoaded loaded,
  required final TextEditingController searchController,
  required final ValueChanged<ShopCatalogItem> onItemTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ShopBloc>();
    final categories = ['Все', ...loaded.catalog.categories];
    final items = loaded.filteredItems;

    return RefreshIndicator(
      color: EcoColors.inkPrimary,
      onRefresh: () async => bloc.add(const ShopCatalogRequested()),
      child: ListView(
        padding: const .fromLTRB(16, 12, 16, 112),
        children: [
          const Center(
            child: Text('Магазин', style: EcoTypography.titleMedium),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              ActionChip(
                avatar: const Icon(LucideIcons.star, size: 16),
                label: Text('${loaded.pointsBalance} ★'),
                onPressed: () => context.push('/ledger'),
              ),
              ActionChip(
                avatar: const Icon(LucideIcons.shoppingBasket, size: 16),
                label: Text('Корзина (${loaded.cartItemCount})'),
                onPressed: () => context.push('/shop/cart'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: EcoColors.surfaceSubtle,
              borderRadius: .all(.circular(16)),
              border: .fromBorderSide(
                BorderSide(color: EcoColors.borderMuted, width: 1),
              ),
            ),
            child: Padding(
              padding: const .all(10),
              child: Text(
                loaded.catalog.fictionalShopBannerRu,
                style: EcoTypography.labelSmall,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchController,
            onChanged: (q) => bloc.add(ShopSearchChanged(q)),
            decoration: const InputDecoration(
              hintText: 'Поиск купонов и эко-товаров...',
              prefixIcon: Icon(LucideIcons.search),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickOrdersTile(
                  icon: LucideIcons.qrCode,
                  label: 'QR-купоны',
                  onTap: () => context.push('/shop/orders/qr'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickOrdersTile(
                  icon: LucideIcons.tag,
                  label: 'Промокоды',
                  onTap: () => context.push('/shop/orders/promo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: .horizontal,
              children: categories
                  .map(
                    (cat) => Padding(
                      padding: const .only(right: 6),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: loaded.selectedCategory == cat,
                        onSelected: (_) => bloc.add(ShopCategoryChanged(cat)),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Column(
              children: [
                const SizedBox(height: 16),
                const Text(
                  'По вашему запросу товары не найдены',
                  style: EcoTypography.bodyMedium,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    searchController.clear();
                    bloc
                      ..add(const ShopSearchChanged(''))
                      ..add(const ShopCategoryChanged('Все'));
                  },
                  child: const Text('Показать все категории'),
                ),
              ],
            )
          else
            for (final item in items) ...[
              _CatalogItemCard(
                item: item,
                onTap: () => onItemTap(item),
                onAdd: () => bloc.add(ShopItemAddedToCart(item)),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

final class const _QuickOrdersTile({
  required final IconData icon,
  required final String label,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const .all(.circular(20)),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Row(
          children: [
            Icon(icon, size: 28, color: EcoColors.inkPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: EcoTypography.bodyMedium)),
            const Icon(LucideIcons.arrowRight, size: 18),
          ],
        ),
      ),
    ),
  );
}

final class const _CatalogItemCard({
  required final ShopCatalogItem item,
  required final VoidCallback onTap,
  required final VoidCallback onAdd,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: const .all(.circular(20)),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: EcoColors.surfaceCard,
        borderRadius: .all(.circular(20)),
        border: .fromBorderSide(
          BorderSide(color: EcoColors.borderMuted, width: 1.5),
        ),
      ),
      child: Padding(
        padding: const .all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(item.title, style: EcoTypography.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    item.partner?.name ?? item.subtitle,
                    style: EcoTypography.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.stockQuantity == null
                        ? 'Виртуальный товар'
                        : 'Осталось: ${item.stockQuantity} шт.',
                    style: EcoTypography.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: EcoColors.surfaceSubtle,
                    borderRadius: .all(.circular(12)),
                  ),
                  child: Padding(
                    padding: const .symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${item.pricePoints} ★',
                      style: EcoTypography.tabularMetric,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: onAdd,
                  child: const Icon(LucideIcons.plus, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class const CartScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<ShopBloc, ShopState>(
    builder: (context, state) {
      final loaded = state is ShopLoaded ? state : null;
      final bloc = context.read<ShopBloc>();
      final cart = loaded?.cart ?? const <CartLine>[];
      final balance = loaded?.pointsBalance ?? 0;
      final total = loaded?.cartTotalPoints ?? 0;
      final deficit = total - balance;

      return Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(
          title: const Text('Корзина'),
          actions: [
            if (cart.isNotEmpty)
              IconButton(
                onPressed: () => bloc.add(const ShopCartCleared()),
                tooltip: 'Очистить корзину',
                icon: const Icon(LucideIcons.trash2),
              ),
          ],
        ),
        body: cart.isEmpty
            ? const Center(
                child: Text('Корзина пуста', style: EcoTypography.bodyMedium),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const .all(16),
                      itemCount: cart.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final line = cart[idx];
                        return DecoratedBox(
                          decoration: const BoxDecoration(
                            color: EcoColors.surfaceCard,
                            borderRadius: .all(.circular(18)),
                          ),
                          child: Padding(
                            padding: const .all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .start,
                                    children: [
                                      Text(
                                        line.item.title,
                                        style: EcoTypography.bodyLarge,
                                      ),
                                      Text(
                                        '${line.item.pricePoints} ★ × ${line.quantity} = ${line.item.pricePoints * line.quantity} ★',
                                        style: EcoTypography.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => bloc.add(
                                    ShopCartQuantityChanged(
                                      line.item.id,
                                      line.quantity - 1,
                                    ),
                                  ),
                                  icon: const Icon(LucideIcons.minus),
                                ),
                                Text(
                                  '${line.quantity}',
                                  style: EcoTypography.tabularMetric,
                                ),
                                IconButton(
                                  onPressed: () => bloc.add(
                                    ShopCartQuantityChanged(
                                      line.item.id,
                                      line.quantity + 1,
                                    ),
                                  ),
                                  icon: const Icon(LucideIcons.plus),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const .all(16),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          Text(
                            'Ваш баланс: $balance ★',
                            style: EcoTypography.bodyMedium,
                          ),
                          Text(
                            'Итого к списанию: $total ★',
                            style: EcoTypography.titleMedium,
                          ),
                          if (deficit > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Нехватка $deficit ★ для оформления заказа',
                              style: EcoTypography.labelSmall,
                            ),
                          ],
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed:
                                deficit <= 0 &&
                                    !(loaded?.isCheckingOut ?? false)
                                ? () => bloc.add(const ShopCheckoutSubmitted())
                                : null,
                            child: Text('Оформить заказ за $total ★'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

final class const OrdersQrScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const _OrdersScreenScaffold(isQrTab: true);
}

final class const OrdersPromoScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const _OrdersScreenScaffold(isQrTab: false);
}

final class const _OrdersScreenScaffold({required final bool isQrTab})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => BlocBuilder<ShopBloc, ShopState>(
    builder: (context, state) {
      final orders = state is ShopLoaded
          ? state.orders
          : const <ShopOrderDetail>[];
      final lines =
          [
                for (final order in orders)
                  for (final line in order.lineItems)
                    (order: order, line: line),
              ]
              .where(
                (pair) => isQrTab
                    ? pair.line.itemType == .partnerQr
                    : pair.line.itemType != .partnerQr,
              )
              .toList();

      return Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(title: const Text('Мои заказы и купоны')),
        body: Column(
          children: [
            Padding(
              padding: const .symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('QR-купоны'),
                      selected: isQrTab,
                      onSelected: (_) {
                        if (!isQrTab) {
                          context.pushReplacement('/shop/orders/qr');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Промокоды'),
                      selected: !isQrTab,
                      onSelected: (_) {
                        if (isQrTab) {
                          context.pushReplacement('/shop/orders/promo');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const Center(
                      child: Text(
                        'Купленных купонов пока нет.',
                        style: EcoTypography.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      padding: const .all(16),
                      itemCount: lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, idx) {
                        final entry = lines[idx];
                        return DecoratedBox(
                          decoration: const BoxDecoration(
                            color: EcoColors.surfaceCard,
                            borderRadius: .all(.circular(20)),
                          ),
                          child: Padding(
                            padding: const .all(14),
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.line.title,
                                        style: EcoTypography.titleMedium,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(entry.order.status.labelRu),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (isQrTab)
                                  ElevatedButton.icon(
                                    onPressed: () => unawaited(
                                      _showQrModal(
                                        context,
                                        entry.line.title,
                                        entry.line.qrPayload,
                                      ),
                                    ),
                                    icon: const Icon(
                                      LucideIcons.qrCode,
                                      size: 18,
                                    ),
                                    label: const Text('Показать QR-код'),
                                  )
                                else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SelectableText(
                                          entry.line.couponCode,
                                          style: EcoTypography.tabularMetric,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: entry.line.couponCode,
                                            ),
                                          );
                                          EcoTopBannerOverlay.instance.showMessage(
                                            'Промокод ${entry.line.couponCode} скопирован',
                                          );
                                        },
                                        icon: const Icon(
                                          LucideIcons.copy,
                                          size: 16,
                                        ),
                                        label: const Text('Скопировать код'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _showQrModal(
    BuildContext context,
    String title,
    String payload,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: EcoColors.surfacePrimary,
    shape: const RoundedRectangleBorder(
      borderRadius: .vertical(top: .circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          children: [
            Text(title, style: EcoTypography.titleMedium),
            const SizedBox(height: 12),
            QrImageView(data: payload, size: 200),
            const SizedBox(height: 8),
            const Text(
              'Демонстрационный QR-код',
              style: EcoTypography.labelSmall,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    ),
  );
}

final class const PointLedgerScreen({super.key}) extends StatefulWidget {
  @override
  State<PointLedgerScreen> createState() => _PointLedgerScreenState();
}

final class _PointLedgerScreenState() extends State<PointLedgerScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ShopBloc>().add(const ShopLedgerRequested());
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ShopBloc, ShopState>(
    builder: (context, state) {
      final ledger = state is ShopLoaded ? state.ledger : null;
      return Scaffold(
        backgroundColor: EcoColors.surfacePrimary,
        appBar: AppBar(title: const Text('История эко-баллов')),
        body: ledger == null
            ? const Center(
                child: CircularProgressIndicator(color: EcoColors.inkPrimary),
              )
            : ListView.separated(
                padding: const .all(16),
                itemCount: ledger.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, idx) {
                  final item = ledger.items[idx];
                  final sign = item.pointsDelta >= 0 ? '+' : '';
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      color: EcoColors.surfaceCard,
                      borderRadius: .all(.circular(16)),
                    ),
                    child: ListTile(
                      title: Text(item.description),
                      subtitle: Text(item.operationType.labelRu),
                      trailing: Text(
                        '$sign${item.pointsDelta} ★',
                        style: EcoTypography.tabularMetric,
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}
