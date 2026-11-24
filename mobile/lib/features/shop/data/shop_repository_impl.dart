import 'dart:convert';
import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';

final class ShopRepositoryImpl implements ShopRepository {
  ShopRepositoryImpl({ApiClient? apiClient, OutboxDispatcher? outboxDispatcher})
    : _apiClient = apiClient ?? ApiClient(),
      _outboxDispatcher = outboxDispatcher ?? OutboxDispatcher();

  final ApiClient _apiClient;
  final OutboxDispatcher _outboxDispatcher;
  final List<ShopOrder> _localOrders = [];

  @override
  Future<Result<List<ShopCoupon>, AppError>> getCatalog() async {
    final netResult = await _apiClient.get<List<ShopCoupon>>(
      path: '/v1/shop/catalog',
      fromJson: (data) {
        if (data case final List<dynamic> list) {
          return list
              .whereType<Map<String, Object?>>()
              .map((m) => ShopCoupon.fromJson(m).okOrNull)
              .whereType<ShopCoupon>()
              .toList();
        }
        return [];
      },
    );

    return netResult.fold(Ok.new, (err) {
      // Fallback partner catalog for offline showcase
      const defaultCoupons = [
        ShopCoupon(
          id: 'c-1',
          title: 'Скидка 20% на весь эко-кофе',
          partnerName: 'ЭкоКофе Вятка',
          costPoints: 50,
          discountPercent: 20,
          category: 'Кафе и напитки',
          description: 'Покажите QR-код бариста при заказе в свою термокружку.',
        ),
        ShopCoupon(
          id: 'c-2',
          title: 'Бесплатная замена фильтра для воды',
          partnerName: 'АкваЧист',
          costPoints: 120,
          discountPercent: 100,
          category: 'Дом и уют',
          description: 'Купон на картридж доочистки водопроводной воды.',
        ),
        ShopCoupon(
          id: 'c-3',
          title: 'Скидка 15% на аренду электросамоката',
          partnerName: 'GreenRide',
          costPoints: 40,
          discountPercent: 15,
          category: 'Транспорт',
          description: 'Промокод на поездку в сервисе кикшеринга.',
        ),
        ShopCoupon(
          id: 'c-4',
          title: 'Эко-сумка шопер из переработанного хлопка',
          partnerName: 'ВяткаРесайкл',
          costPoints: 80,
          discountPercent: 50,
          category: 'Мерч',
          description: 'Стильный шопер ручной работы со скидкой 50%.',
        ),
      ];
      return const Ok(defaultCoupons);
    });
  }

  @override
  Future<Result<List<ShopOrder>, AppError>> getMyOrders() async =>
      Ok(List.unmodifiable(_localOrders));

  @override
  Future<Result<ShopOrder, AppError>> purchaseCoupon(ShopCoupon coupon) async {
    // Record outbox mutation to ensure server ledger immutability and idempotency
    final idempotencyKey = await _outboxDispatcher.enqueueMutation(
      mutationType: 'SHOP_PURCHASE',
      endpointPath: '/v1/shop/orders',
      payloadJson: jsonEncode({
        'coupon_id': coupon.id,
        'cost_points': coupon.costPoints,
      }),
    );

    // Create client order representation with deterministic promo code
    final code =
        'ECO-${coupon.partnerName.substring(0, 3).toUpperCase()}-${idempotencyKey.substring(0, 4).toUpperCase()}';
    final order = ShopOrder(
      id: UuidV7.generate(),
      couponTitle: coupon.title,
      partnerName: coupon.partnerName,
      promoCode: code,
      qrPayload: 'ecotrack://order/${coupon.id}/$code',
      purchasedAt: DateTime.now(),
    );

    _localOrders.insert(0, order);
    return Ok(order);
  }
}
