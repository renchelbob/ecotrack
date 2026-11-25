import 'dart:convert';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class ShopRepositoryImpl(final DioClient _dioClient)
    implements ShopRepository {
  static const String _catalogCacheKey = 'ecotrack_shop_catalog_cache';
  static const String _ordersCacheKey = 'ecotrack_shop_orders_cache';

  @override
  Future<Result<ShopCatalogResponse, AppError>> getCatalog({
    String? category,
    ShopItemType? itemType,
    String? search,
  }) async {
    final query = <String, Object?>{
      if (category != null && category.isNotEmpty && category != 'Все')
        'category': category,
      if (itemType != null) 'item_type': itemType.wireName,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };

    final netRes = await _dioClient.get<ShopCatalogResponse>(
      '/api/v1/shop/items',
      queryParameters: query.isEmpty ? null : query,
      parser: (data) => _parseOrThrow(data, ShopCatalogResponse.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        if (query.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_catalogCacheKey, jsonEncode(value.toJson()));
        }
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _readCachedCatalog();
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<ShopOrderDetail, AppError>> createOrder(
    List<({String shopItemId, int quantity})> items,
  ) => _dioClient.post<ShopOrderDetail>(
    '/api/v1/shop/orders',
    data: {
      'items': items
          .map(
            (line) => {
              'shop_item_id': line.shopItemId,
              'quantity': line.quantity,
            },
          )
          .toList(),
    },
    headers: {'Idempotency-Key': UuidV7.generate()},
    parser: (data) => _parseOrThrow(data, ShopOrderDetail.fromJson),
  );

  @override
  Future<Result<ShopOrderListResponse, AppError>> getMyOrders({
    int limit = 20,
    int offset = 0,
  }) async {
    final netRes = await _dioClient.get<ShopOrderListResponse>(
      '/api/v1/shop/orders',
      queryParameters: {'limit': limit, 'offset': offset},
      parser: (data) => _parseOrThrow(data, ShopOrderListResponse.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        if (offset == 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_ordersCacheKey, jsonEncode(value.toJson()));
        }
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _readCachedOrders();
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<PointLedgerListResponse, AppError>> getPointLedger({
    int limit = 20,
    int offset = 0,
  }) => _dioClient.get<PointLedgerListResponse>(
    '/api/v1/ledger',
    queryParameters: {'limit': limit, 'offset': offset},
    parser: (data) => _parseOrThrow(data, PointLedgerListResponse.fromJson),
  );

  @override
  Future<Result<UserProfile, AppError>> activateStreakFreeze() =>
      _dioClient.post<UserProfile>(
        '/api/v1/shop/virtual-items/streak-freeze:activate',
        headers: {'Idempotency-Key': UuidV7.generate()},
        parser: (data) => _parseOrThrow(data, UserProfile.fromJson),
      );

  Future<ShopCatalogResponse?> _readCachedCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_catalogCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return ShopCatalogResponse.fromJson(decoded).valueOrNull;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<ShopOrderListResponse?> _readCachedOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ordersCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return ShopOrderListResponse.fromJson(decoded).valueOrNull;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  bool _isOfflineError(AppError error) =>
      error.clientAction == ClientErrorAction.queueRetry ||
      error.httpStatus == 0 ||
      error.httpStatus == 503;

  T _parseOrThrow<T>(
    Object? data,
    Result<T, AppError> Function(Map<String, Object?>) parser,
  ) {
    if (data is Map<String, Object?>) {
      return switch (parser(data)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    }
    throw AppError.fromCode('VALIDATION_ERROR');
  }
}
