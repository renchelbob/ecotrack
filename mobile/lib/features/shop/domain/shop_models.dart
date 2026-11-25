import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

enum ShopItemType(final String wireName, final String labelRu) {
  partnerCoupon('partner_coupon', 'Промокод партнёра'),
  partnerQr('partner_qr', 'QR-купон'),
  virtualStreakFreeze('virtual_streak_freeze', 'Заморозка стрика'),
  virtualEcoDonation('virtual_eco_donation', 'Эко-донат'),
  mascotAccessory('mascot_accessory', 'Гардероб зверька');

  static ShopItemType fromWire(String? raw) => switch (raw) {
    'partner_coupon' => .partnerCoupon,
    'partner_qr' => .partnerQr,
    'virtual_streak_freeze' => .virtualStreakFreeze,
    'virtual_eco_donation' => .virtualEcoDonation,
    'mascot_accessory' => .mascotAccessory,
    _ => .partnerCoupon,
  };
}

enum OrderStatus(final String wireName, final String labelRu) {
  completed('completed', 'Активен'),
  redeemed('redeemed', 'Использован'),
  refunded('refunded', 'Возврат'),
  expired('expired', 'Истёк');

  static OrderStatus fromWire(String? raw) => switch (raw) {
    'completed' => .completed,
    'redeemed' => .redeemed,
    'refunded' => .refunded,
    'expired' => .expired,
    _ => .completed,
  };
}

enum LedgerOperationType(final String wireName, final String labelRu) {
  dailyStepsReward('daily_steps_reward', 'Награда за шаги'),
  segmentAnnotationDelta('segment_annotation_delta', 'Уточнение маршрута'),
  streakBonus('streak_bonus', 'Бонус за серию дней'),
  challengeReward('challenge_reward', 'Челлендж «Общий лес»'),
  badgeReward('badge_reward', 'Достижение'),
  shopPurchase('shop_purchase', 'Покупка в магазине'),
  shopRefund('shop_refund', 'Возврат баллов'),
  adminAdjustment('admin_adjustment', 'Корректировка');

  static LedgerOperationType fromWire(String? raw) => switch (raw) {
    'daily_steps_reward' => .dailyStepsReward,
    'segment_annotation_delta' => .segmentAnnotationDelta,
    'streak_bonus' => .streakBonus,
    'challenge_reward' => .challengeReward,
    'badge_reward' => .badgeReward,
    'shop_purchase' => .shopPurchase,
    'shop_refund' => .shopRefund,
    'admin_adjustment' => .adminAdjustment,
    _ => .dailyStepsReward,
  };
}

int _readInt(Object? raw, [int fallback = 0]) => switch (raw) {
  final int v => v,
  final num v => v.toInt(),
  _ => fallback,
};

Result<List<T>, AppError> _parseList<T>(
  Object? raw,
  Result<T, AppError> Function(Map<String, Object?>) parser,
) {
  if (raw is! List<Object?>) {
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }
  final out = <T>[];
  for (final element in raw) {
    if (element is! Map<String, Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    switch (parser(element)) {
      case Ok(:final value):
        out.add(value);
      case Err(:final error):
        return Err(error);
    }
  }
  return Ok(out);
}

final class const ShopPartnerSummary({
  required final String id,
  required final String slug,
  required final String name,
  required final String categoryName,
  required final String logoAssetKey,
  required final String isFictionalDisclaimer,
}) {
  static Result<ShopPartnerSummary, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'id': final String id,
      'slug': final String slug,
      'name': final String name,
      'category_name': final String categoryName,
      'logo_asset_key': final String logoAssetKey,
      'is_fictional_disclaimer': final String disclaimer,
    }) {
      return Ok(
        ShopPartnerSummary(
          id: id,
          slug: slug,
          name: name,
          categoryName: categoryName,
          logoAssetKey: logoAssetKey,
          isFictionalDisclaimer: disclaimer,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'slug': slug,
    'name': name,
    'category_name': categoryName,
    'logo_asset_key': logoAssetKey,
    'is_fictional_disclaimer': isFictionalDisclaimer,
  };
}

final class const ShopCatalogItem({
  required final String id,
  required final String sku,
  required final ShopItemType itemType,
  required final String title,
  required final String subtitle,
  required final String description,
  required final int pricePoints,
  final int? stockQuantity,
  required final int maxPerUserPerDay,
  final String? accessoryCode,
  required final String imageAssetKey,
  final ShopPartnerSummary? partner,
}) {
  static Result<ShopCatalogItem, AppError> fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final sku = json['sku'];
    final title = json['title'];
    if (id is! String || sku is! String || title is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    ShopPartnerSummary? partner;
    final rawPartner = json['partner'];
    if (rawPartner is Map<String, Object?>) {
      partner = ShopPartnerSummary.fromJson(rawPartner).valueOrNull;
    }
    return Ok(
      ShopCatalogItem(
        id: id,
        sku: sku,
        itemType: .fromWire(json['item_type'] as String?),
        title: title,
        subtitle: json['subtitle'] as String? ?? '',
        description: json['description'] as String? ?? '',
        pricePoints: _readInt(json['price_points'], 1),
        stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
        maxPerUserPerDay: _readInt(json['max_per_user_per_day'], 1),
        accessoryCode: json['accessory_code'] as String?,
        imageAssetKey: json['image_asset_key'] as String? ?? '',
        partner: partner,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sku': sku,
    'item_type': itemType.wireName,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'price_points': pricePoints,
    'stock_quantity': stockQuantity,
    'max_per_user_per_day': maxPerUserPerDay,
    'accessory_code': accessoryCode,
    'image_asset_key': imageAssetKey,
    'partner': partner?.toJson(),
  };
}

final class const ShopCatalogResponse({
  required final String fictionalShopBannerRu,
  required final List<String> categories,
  required final List<ShopCatalogItem> items,
}) {
  static const String defaultBannerRu =
      'Демонстрационный магазин: все бренды партнёров, промокоды и QR-купоны являются вымышленными.';

  static Result<ShopCatalogResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final rawItems = json['items'];
    final itemsRes = _parseList(rawItems, ShopCatalogItem.fromJson);
    final rawCats = json['categories'];
    final categories = rawCats is List<Object?>
        ? rawCats.whereType<String>().toList()
        : const <String>[];
    return switch (itemsRes) {
      Ok(:final value) => Ok(
        ShopCatalogResponse(
          fictionalShopBannerRu:
              json['fictional_shop_banner_ru'] as String? ?? defaultBannerRu,
          categories: categories,
          items: value,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  Map<String, Object?> toJson() => {
    'fictional_shop_banner_ru': fictionalShopBannerRu,
    'categories': categories,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

final class const CartLine({
  required final ShopCatalogItem item,
  required final int quantity,
});

final class const ShopOrderLineItem({
  required final String id,
  required final String shopItemId,
  required final String title,
  required final ShopItemType itemType,
  required final int quantity,
  required final int unitPricePoints,
  required final int lineTotalPoints,
  required final String couponCode,
  required final String qrPayload,
  final String? expiresAt,
  final String? redeemedAt,
}) {
  static Result<ShopOrderLineItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final itemId = json['shop_item_id'];
    final title = json['title'];
    if (id is! String || itemId is! String || title is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      ShopOrderLineItem(
        id: id,
        shopItemId: itemId,
        title: title,
        itemType: .fromWire(json['item_type'] as String?),
        quantity: _readInt(json['quantity'], 1),
        unitPricePoints: _readInt(json['unit_price_points']),
        lineTotalPoints: _readInt(json['line_total_points']),
        couponCode: json['coupon_code'] as String? ?? '',
        qrPayload: json['qr_payload'] as String? ?? '',
        expiresAt: json['expires_at'] as String?,
        redeemedAt: json['redeemed_at'] as String?,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'shop_item_id': shopItemId,
    'title': title,
    'item_type': itemType.wireName,
    'quantity': quantity,
    'unit_price_points': unitPricePoints,
    'line_total_points': lineTotalPoints,
    'coupon_code': couponCode,
    'qr_payload': qrPayload,
    'expires_at': expiresAt,
    'redeemed_at': redeemedAt,
  };
}

final class const ShopOrderDetail({
  required final String id,
  required final String idempotencyKey,
  required final OrderStatus status,
  required final int totalPoints,
  required final int remainingPointsBalance,
  required final int itemCount,
  required final List<ShopOrderLineItem> lineItems,
  required final String createdAt,
}) {
  static Result<ShopOrderDetail, AppError> fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final key = json['idempotency_key'];
    final createdAt = json['created_at'];
    if (id is! String || key is! String || createdAt is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final linesRes = _parseList(json['line_items'], ShopOrderLineItem.fromJson);
    return switch (linesRes) {
      Ok(:final value) => Ok(
        ShopOrderDetail(
          id: id,
          idempotencyKey: key,
          status: .fromWire(json['status'] as String?),
          totalPoints: _readInt(json['total_points'], 1),
          remainingPointsBalance: _readInt(json['remaining_points_balance']),
          itemCount: _readInt(json['item_count'], value.length),
          lineItems: value,
          createdAt: createdAt,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'idempotency_key': idempotencyKey,
    'status': status.wireName,
    'total_points': totalPoints,
    'remaining_points_balance': remainingPointsBalance,
    'item_count': itemCount,
    'line_items': lineItems.map((l) => l.toJson()).toList(),
    'created_at': createdAt,
  };
}

final class const ShopOrderListResponse({
  required final int totalCount,
  required final List<ShopOrderDetail> orders,
}) {
  static Result<ShopOrderListResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final ordersRes = _parseList(json['orders'], ShopOrderDetail.fromJson);
    return switch (ordersRes) {
      Ok(:final value) => Ok(
        ShopOrderListResponse(
          totalCount: _readInt(json['total_count'], value.length),
          orders: value,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  Map<String, Object?> toJson() => {
    'total_count': totalCount,
    'orders': orders.map((o) => o.toJson()).toList(),
  };
}

final class const PointLedgerItem({
  required final String id,
  required final String idempotencyKey,
  required final LedgerOperationType operationType,
  required final int pointsDelta,
  required final int co2DeltaGrams,
  final String? referenceEntityType,
  final String? referenceEntityId,
  required final String description,
  required final String createdAt,
}) {
  static Result<PointLedgerItem, AppError> fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final key = json['idempotency_key'];
    final description = json['description'];
    final createdAt = json['created_at'];
    if (id is! String ||
        key is! String ||
        description is! String ||
        createdAt is! String) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      PointLedgerItem(
        id: id,
        idempotencyKey: key,
        operationType: .fromWire(json['operation_type'] as String?),
        pointsDelta: _readInt(json['points_delta']),
        co2DeltaGrams: _readInt(json['co2_delta_grams']),
        referenceEntityType: json['reference_entity_type'] as String?,
        referenceEntityId: json['reference_entity_id'] as String?,
        description: description,
        createdAt: createdAt,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'idempotency_key': idempotencyKey,
    'operation_type': operationType.wireName,
    'points_delta': pointsDelta,
    'co2_delta_grams': co2DeltaGrams,
    'reference_entity_type': referenceEntityType,
    'reference_entity_id': referenceEntityId,
    'description': description,
    'created_at': createdAt,
  };
}

final class const PointLedgerListResponse({
  required final int pointsBalance,
  required final int lifetimePointsEarned,
  required final int totalCount,
  required final List<PointLedgerItem> items,
}) {
  static Result<PointLedgerListResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    final itemsRes = _parseList(json['items'], PointLedgerItem.fromJson);
    return switch (itemsRes) {
      Ok(:final value) => Ok(
        PointLedgerListResponse(
          pointsBalance: _readInt(json['points_balance']),
          lifetimePointsEarned: _readInt(json['lifetime_points_earned']),
          totalCount: _readInt(json['total_count'], value.length),
          items: value,
        ),
      ),
      Err(:final error) => Err(error),
    };
  }

  Map<String, Object?> toJson() => {
    'points_balance': pointsBalance,
    'lifetime_points_earned': lifetimePointsEarned,
    'total_count': totalCount,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

abstract interface class ShopRepository() {
  Future<Result<ShopCatalogResponse, AppError>> getCatalog({
    String? category,
    ShopItemType? itemType,
    String? search,
  });

  Future<Result<ShopOrderDetail, AppError>> createOrder(
    List<({String shopItemId, int quantity})> items,
  );

  Future<Result<ShopOrderListResponse, AppError>> getMyOrders({
    int limit = 20,
    int offset = 0,
  });

  Future<Result<PointLedgerListResponse, AppError>> getPointLedger({
    int limit = 20,
    int offset = 0,
  });

  Future<Result<UserProfile, AppError>> activateStreakFreeze();
}
