import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

final class ShopCoupon {
  const ShopCoupon({
    required this.id,
    required this.title,
    required this.partnerName,
    required this.costPoints,
    required this.discountPercent,
    required this.category,
    this.description = '',
  });

  final String id;
  final String title;
  final String partnerName;
  final int costPoints;
  final int discountPercent;
  final String category;
  final String description;

  static Result<ShopCoupon, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'title': final String title,
      'partner_name': final String partner,
      'cost_points': final num cost,
      'discount_percent': final num discount,
    }) {
      return Ok(
        ShopCoupon(
          id: id,
          title: title,
          partnerName: partner,
          costPoints: cost.toInt(),
          discountPercent: discount.toInt(),
          category: json['category'] as String? ?? 'Партнеры',
          description: json['description'] as String? ?? '',
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR', 'Неверный формат купона'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'partner_name': partnerName,
    'cost_points': costPoints,
    'discount_percent': discountPercent,
    'category': category,
    'description': description,
  };
}

final class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.couponTitle,
    required this.partnerName,
    required this.promoCode,
    required this.qrPayload,
    required this.purchasedAt,
    this.isUsed = false,
  });

  final String id;
  final String couponTitle;
  final String partnerName;
  final String promoCode;
  final String qrPayload;
  final DateTime purchasedAt;
  final bool isUsed;

  static Result<ShopOrder, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'coupon_title': final String title,
      'partner_name': final String partner,
      'promo_code': final String code,
      'qr_payload': final String qr,
    }) {
      return Ok(
        ShopOrder(
          id: id,
          couponTitle: title,
          partnerName: partner,
          promoCode: code,
          qrPayload: qr,
          purchasedAt:
              DateTime.tryParse(json['purchased_at'] as String? ?? '') ??
              DateTime.now(),
          isUsed: json['is_used'] as bool? ?? false,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR', 'Неверный формат заказа'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'coupon_title': couponTitle,
    'partner_name': partnerName,
    'promo_code': promoCode,
    'qr_payload': qrPayload,
    'purchased_at': purchasedAt.toIso8601String(),
    'is_used': isUsed,
  };
}

abstract interface class ShopRepository {
  Future<Result<List<ShopCoupon>, AppError>> getCatalog();
  Future<Result<List<ShopOrder>, AppError>> getMyOrders();
  Future<Result<ShopOrder, AppError>> purchaseCoupon(ShopCoupon coupon);
}
