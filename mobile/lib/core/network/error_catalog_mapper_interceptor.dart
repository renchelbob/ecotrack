import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';

final class ErrorCatalogMapperInterceptor({
  final ErrorCatalogRegistry? catalog,
  final void Function()? onForceLogout,
  final void Function(AppError error)? onGateError,
}) extends Interceptor {
  ErrorCatalogRegistry get _catalog => catalog ?? ErrorCatalogRegistry.instance;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final appError = mapDioException(err);
    switch (appError.clientAction) {
      case ClientErrorAction.forceLogout:
        onForceLogout?.call();
      case ClientErrorAction.openPhoneModal:
      case ClientErrorAction.openConsentScreen:
        onGateError?.call(appError);
      case ClientErrorAction.none:
      case ClientErrorAction.refreshToken:
      case ClientErrorAction.showInline:
      case ClientErrorAction.showBanner:
      case ClientErrorAction.queueRetry:
        break;
    }
    handler.next(err.copyWith(error: appError));
  }

  AppError mapDioException(DioException err) {
    final embedded = err.error;
    if (embedded is AppError) {
      return embedded;
    }

    final isNetworkUnavailable =
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.type == DioExceptionType.unknown && err.response == null);
    if (isNetworkUnavailable) {
      return _catalog.resolve('DATABASE_UNAVAILABLE');
    }

    final responseData = err.response?.data;
    final jsonMap = _normalizeJsonMap(responseData);
    return _catalog.fromResponseMap(
      jsonMap,
      fallbackHttpStatus: err.response?.statusCode,
    );
  }

  static Map<String, Object?> _normalizeJsonMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const <String, Object?>{};
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is String) {
        result[key] = entry.value;
      }
    }
    return result;
  }
}
