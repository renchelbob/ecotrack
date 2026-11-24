import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ShopState {
  const ShopState();
}

final class ShopLoading extends ShopState {
  const ShopLoading();
}

final class ShopLoaded extends ShopState {
  const ShopLoaded({
    required this.coupons,
    required this.orders,
    this.selectedCategory = 'Все',
    this.userBalance = 120,
  });

  final List<ShopCoupon> coupons;
  final List<ShopOrder> orders;
  final String selectedCategory;
  final int userBalance;

  ShopLoaded copyWith({
    List<ShopCoupon>? coupons,
    List<ShopOrder>? orders,
    String? selectedCategory,
    int? userBalance,
  }) => ShopLoaded(
    coupons: coupons ?? this.coupons,
    orders: orders ?? this.orders,
    selectedCategory: selectedCategory ?? this.selectedCategory,
    userBalance: userBalance ?? this.userBalance,
  );
}

final class ShopFailure extends ShopState {
  const ShopFailure(this.error);
  final AppError error;
}

final class ShopCubit extends Cubit<ShopState> {
  ShopCubit(this._repository) : super(const ShopLoading());

  final ShopRepository _repository;

  Future<void> loadShopData() async {
    emit(const ShopLoading());
    final catRes = await _repository.getCatalog();
    final ordersRes = await _repository.getMyOrders();

    if (catRes is Ok<List<ShopCoupon>, AppError> &&
        ordersRes is Ok<List<ShopOrder>, AppError>) {
      emit(ShopLoaded(coupons: catRes.value, orders: ordersRes.value));
    } else {
      final err =
          catRes.errOrNull ??
          ordersRes.errOrNull ??
          AppError.fromCode('VALIDATION_ERROR');
      emit(ShopFailure(err));
    }
  }

  void filterCategory(String category) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(selectedCategory: category));
    }
  }

  Future<Result<ShopOrder, AppError>> buyCoupon(ShopCoupon coupon) async {
    if (state case final ShopLoaded loaded) {
      if (loaded.userBalance < coupon.costPoints) {
        final err = AppError.fromCode('INSUFFICIENT_POINTS');
        return Err(err);
      }

      final res = await _repository.purchaseCoupon(coupon);
      switch (res) {
        case Ok(value: final order):
          final updatedOrders = [order, ...loaded.orders];
          final updatedBalance = loaded.userBalance - coupon.costPoints;
          emit(
            loaded.copyWith(orders: updatedOrders, userBalance: updatedBalance),
          );
          return Ok(order);
        case Err(error: final appError):
          return Err(appError);
      }
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }
}
