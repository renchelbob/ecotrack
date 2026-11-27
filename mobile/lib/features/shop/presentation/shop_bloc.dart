import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:ecotrack_mobile/features/shop/domain/shop_models.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class const ShopEvent();

final class const ShopCatalogRequested() extends ShopEvent;

final class const ShopCategoryChanged(final String? category) extends ShopEvent;

final class const ShopSearchChanged(final String query) extends ShopEvent;

final class const ShopItemAddedToCart(final ShopCatalogItem item)
    extends ShopEvent;

final class const ShopCartQuantityChanged(
  final String itemId,
  final int quantity,
) extends ShopEvent;

final class const ShopCartCleared() extends ShopEvent;

final class const ShopCheckoutSubmitted() extends ShopEvent;

final class const ShopOrdersRequested() extends ShopEvent;

final class const ShopLedgerRequested() extends ShopEvent;

final class const ShopStreakFreezeActivated() extends ShopEvent;

final class const ShopFeedbackCleared() extends ShopEvent;

final class const _ShopProfileUpdated(final UserProfile profile)
    extends ShopEvent;

sealed class const ShopState();

final class const ShopLoading() extends ShopState;

final class const ShopLoaded({
  required final ShopCatalogResponse catalog,
  required final List<ShopOrderDetail> orders,
  final PointLedgerListResponse? ledger,
  final List<CartLine> cart = const [],
  final int pointsBalance = 0,
  final String selectedCategory = 'Все',
  final String searchQuery = '',
  final bool isCheckingOut = false,
  final AppError? bannerError,
  final String? feedbackMessage,
}) extends ShopState {
  int get cartItemCount => cart.fold<int>(0, (sum, l) => sum + l.quantity);

  int get cartTotalPoints =>
      cart.fold<int>(0, (sum, l) => sum + (l.item.pricePoints * l.quantity));

  List<ShopCatalogItem> get filteredItems {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    return catalog.items.where((item) {
      final matchesCat =
          selectedCategory == 'Все' ||
          item.partner?.categoryName == selectedCategory ||
          (selectedCategory == 'Виртуальные бонусы' &&
              (item.itemType == .virtualStreakFreeze ||
                  item.itemType == .virtualEcoDonation)) ||
          (selectedCategory == 'Гардероб зверька' &&
              item.itemType == .mascotAccessory);
      final matchesSearch =
          normalizedQuery.isEmpty ||
          item.title.toLowerCase().contains(normalizedQuery) ||
          item.subtitle.toLowerCase().contains(normalizedQuery) ||
          (item.partner?.name.toLowerCase().contains(normalizedQuery) ?? false);
      return matchesCat && matchesSearch;
    }).toList();
  }

  ShopLoaded copyWith({
    ShopCatalogResponse? catalog,
    List<ShopOrderDetail>? orders,
    PointLedgerListResponse? ledger,
    List<CartLine>? cart,
    int? pointsBalance,
    String? selectedCategory,
    String? searchQuery,
    bool? isCheckingOut,
    AppError? bannerError,
    String? feedbackMessage,
    bool clearFeedback = false,
  }) => ShopLoaded(
    catalog: catalog ?? this.catalog,
    orders: orders ?? this.orders,
    ledger: ledger ?? this.ledger,
    cart: cart ?? this.cart,
    pointsBalance: pointsBalance ?? this.pointsBalance,
    selectedCategory: selectedCategory ?? this.selectedCategory,
    searchQuery: searchQuery ?? this.searchQuery,
    isCheckingOut: isCheckingOut ?? this.isCheckingOut,
    bannerError: clearFeedback ? null : (bannerError ?? this.bannerError),
    feedbackMessage: clearFeedback
        ? null
        : (feedbackMessage ?? this.feedbackMessage),
  );
}

final class const ShopFailure(final AppError error) extends ShopState;

final class ShopBloc(
  final ShopRepository _shopRepo,
  final ProfileRepository _profileRepo,
) extends Bloc<ShopEvent, ShopState> {
  this : super(const ShopLoading()) {
    on<ShopCatalogRequested>(_onCatalogRequested);
    on<ShopCategoryChanged>(_onCategoryChanged);
    on<ShopSearchChanged>(_onSearchChanged);
    on<ShopItemAddedToCart>(_onItemAdded);
    on<ShopCartQuantityChanged>(_onCartQuantityChanged);
    on<ShopCartCleared>(_onCartCleared);
    on<ShopCheckoutSubmitted>(_onCheckoutSubmitted);
    on<ShopOrdersRequested>(_onOrdersRequested);
    on<ShopLedgerRequested>(_onLedgerRequested);
    on<ShopStreakFreezeActivated>(_onStreakFreezeActivated);
    on<ShopFeedbackCleared>(_onFeedbackCleared);
    on<_ShopProfileUpdated>(_onProfileUpdated);

    _profileSub = _profileRepo.watchUserProfile().listen(
      (profile) => add(_ShopProfileUpdated(profile)),
    );
  }

  StreamSubscription<UserProfile>? _profileSub;

  Future<void> _onCatalogRequested(
    ShopCatalogRequested event,
    Emitter<ShopState> emit,
  ) async {
    final catalogRes = await _shopRepo.getCatalog();
    final ordersRes = await _shopRepo.getMyOrders();
    final profileRes = await _profileRepo.getProfile();
    final ledgerRes = await _shopRepo.getPointLedger();

    switch (catalogRes) {
      case Err(:final error):
        if (state case final ShopLoaded loaded) {
          emit(loaded.copyWith(bannerError: error));
        } else {
          emit(ShopFailure(error));
        }
      case Ok(:final value):
        final prevCart = state is ShopLoaded
            ? (state as ShopLoaded).cart
            : const <CartLine>[];
        final balance =
            profileRes.valueOrNull?.pointsBalance ??
            ledgerRes.valueOrNull?.pointsBalance ??
            0;
        emit(
          ShopLoaded(
            catalog: value,
            orders: ordersRes.valueOrNull?.orders ?? const [],
            ledger: ledgerRes.valueOrNull,
            cart: prevCart,
            pointsBalance: balance,
            bannerError: ordersRes.errorOrNull,
          ),
        );
    }
  }

  void _onCategoryChanged(ShopCategoryChanged event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(selectedCategory: event.category ?? 'Все'));
    }
  }

  void _onSearchChanged(ShopSearchChanged event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(searchQuery: event.query));
    }
  }

  void _onItemAdded(ShopItemAddedToCart event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      final updatedCart = [...loaded.cart];
      final existingIdx = updatedCart.indexWhere(
        (l) => l.item.id == event.item.id,
      );
      if (existingIdx >= 0) {
        final currentLine = updatedCart[existingIdx];
        final maxAllowed = event.item.maxPerUserPerDay;
        final nextQty = (currentLine.quantity + 1).clamp(1, maxAllowed);
        updatedCart[existingIdx] = CartLine(
          item: currentLine.item,
          quantity: nextQty,
        );
      } else {
        updatedCart.add(CartLine(item: event.item, quantity: 1));
      }
      emit(
        loaded.copyWith(
          cart: updatedCart,
          feedbackMessage: '«${event.item.title}» добавлен в корзину',
        ),
      );
    }
  }

  void _onCartQuantityChanged(
    ShopCartQuantityChanged event,
    Emitter<ShopState> emit,
  ) {
    if (state case final ShopLoaded loaded) {
      final updatedCart = <CartLine>[];
      for (final line in loaded.cart) {
        if (line.item.id != event.itemId) {
          updatedCart.add(line);
        } else if (event.quantity > 0) {
          updatedCart.add(
            CartLine(
              item: line.item,
              quantity: event.quantity.clamp(1, line.item.maxPerUserPerDay),
            ),
          );
        }
      }
      emit(loaded.copyWith(cart: updatedCart));
    }
  }

  void _onCartCleared(ShopCartCleared event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(cart: const []));
    }
  }

  Future<void> _onCheckoutSubmitted(
    ShopCheckoutSubmitted event,
    Emitter<ShopState> emit,
  ) async {
    if (state case final ShopLoaded loaded) {
      if (loaded.cart.isEmpty) return;
      if (loaded.cartTotalPoints > loaded.pointsBalance) {
        emit(
          loaded.copyWith(
            bannerError: AppError.fromCode('INSUFFICIENT_POINTS_BALANCE'),
          ),
        );
        return;
      }

      emit(loaded.copyWith(isCheckingOut: true, clearFeedback: true));
      final orderLines = loaded.cart
          .map((l) => (shopItemId: l.item.id, quantity: l.quantity))
          .toList();
      final res = await _shopRepo.createOrder(orderLines);

      if (state case final ShopLoaded current) {
        switch (res) {
          case Ok(:final value):
            unawaited(_profileRepo.getProfile(forceRefresh: true));
            emit(
              current.copyWith(
                isCheckingOut: false,
                cart: const [],
                orders: [value, ...current.orders],
                pointsBalance: value.remainingPointsBalance,
                feedbackMessage:
                    'Заказ оформлен! Списано ${value.totalPoints} ★',
              ),
            );
          case Err(:final error):
            emit(current.copyWith(isCheckingOut: false, bannerError: error));
        }
      }
    }
  }

  Future<void> _onOrdersRequested(
    ShopOrdersRequested event,
    Emitter<ShopState> emit,
  ) async {
    final ordersRes = await _shopRepo.getMyOrders();
    if (state case final ShopLoaded loaded) {
      switch (ordersRes) {
        case Ok(:final value):
          emit(loaded.copyWith(orders: value.orders));
        case Err(:final error):
          emit(loaded.copyWith(bannerError: error));
      }
    }
  }

  Future<void> _onLedgerRequested(
    ShopLedgerRequested event,
    Emitter<ShopState> emit,
  ) async {
    final ledgerRes = await _shopRepo.getPointLedger();
    if (state case final ShopLoaded loaded) {
      switch (ledgerRes) {
        case Ok(:final value):
          emit(
            loaded.copyWith(ledger: value, pointsBalance: value.pointsBalance),
          );
        case Err(:final error):
          emit(loaded.copyWith(bannerError: error));
      }
    }
  }

  Future<void> _onStreakFreezeActivated(
    ShopStreakFreezeActivated event,
    Emitter<ShopState> emit,
  ) async {
    final res = await _shopRepo.activateStreakFreeze();
    if (state case final ShopLoaded loaded) {
      switch (res) {
        case Ok(:final value):
          await _profileRepo.cacheProfile(value);
          emit(
            loaded.copyWith(
              pointsBalance: value.pointsBalance,
              feedbackMessage: 'Заморозка стрика активирована',
            ),
          );
        case Err(:final error):
          emit(loaded.copyWith(bannerError: error));
      }
    }
  }

  void _onFeedbackCleared(ShopFeedbackCleared event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(clearFeedback: true));
    }
  }

  void _onProfileUpdated(_ShopProfileUpdated event, Emitter<ShopState> emit) {
    if (state case final ShopLoaded loaded) {
      emit(loaded.copyWith(pointsBalance: event.profile.pointsBalance));
    }
  }

  @override
  Future<void> close() async {
    await _profileSub?.cancel();
    await super.close();
  }
}
