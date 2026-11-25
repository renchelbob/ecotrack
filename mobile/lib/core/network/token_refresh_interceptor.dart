import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';

final class TokenRefreshInterceptor({
  required final TokenStore tokenStore,
  required final Dio retryDio,
  required final Dio bareRefreshDio,
  final void Function()? onForceLogout,
}) extends QueuedInterceptorsWrapper {
  static const String forceLogoutNotifiedKey = '_forceLogoutNotified';
  static const String _retriedFlag = '_retriedAfterRefresh';
  static const String _refreshPath = '/api/v1/auth/refresh';
  static const String _exchangePath = '/api/v1/auth/oauth/exchange';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final requestPath =
        Uri.tryParse(err.requestOptions.path)?.path ?? err.requestOptions.path;

    if (statusCode != 401 ||
        requestPath == _refreshPath ||
        requestPath == _exchangePath ||
        err.requestOptions.extra[_retriedFlag] == true) {
      handler.next(err);
      return;
    }

    final errorCode = _extractErrorCode(err.response?.data);
    if (errorCode != 'AUTH_TOKEN_EXPIRED') {
      handler.next(await _forceLogoutAndTag(err));
      return;
    }

    final currentAccess = await tokenStore.getAccessToken();
    final sentBearer = _extractBearerToken(
      err.requestOptions.headers['Authorization'],
    );
    if (currentAccess != null &&
        currentAccess.isNotEmpty &&
        sentBearer != null &&
        currentAccess != sentBearer) {
      await _retryOriginalRequest(
        err: err,
        newAccessToken: currentAccess,
        handler: handler,
      );
      return;
    }

    final refreshToken = await tokenStore.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      handler.next(await _forceLogoutAndTag(err));
      return;
    }

    final fingerprint = await tokenStore.getOrCreateDeviceFingerprint();
    try {
      final refreshResponse = await bareRefreshDio.post<Object?>(
        _refreshPath,
        data: <String, Object?>{
          'refresh_token': refreshToken,
          'device_fingerprint': fingerprint,
        },
      );
      final tokens = _parseTokenPair(refreshResponse.data);
      if (tokens == null) {
        handler.next(await _forceLogoutAndTag(err));
        return;
      }

      await tokenStore.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      await _retryOriginalRequest(
        err: err,
        newAccessToken: tokens.accessToken,
        handler: handler,
      );
    } on DioException catch (refreshErr) {
      handler.next(
        await _forceLogoutAndTag(err, overrideResponse: refreshErr.response),
      );
    }
  }

  Future<void> _retryOriginalRequest({
    required DioException err,
    required String newAccessToken,
    required ErrorInterceptorHandler handler,
  }) async {
    final original = err.requestOptions;
    final retryHeaders = Map<String, Object?>.of(original.headers);
    retryHeaders['Authorization'] = 'Bearer $newAccessToken';
    final retryExtra = Map<String, Object?>.of(original.extra);
    retryExtra[_retriedFlag] = true;

    final retryOptions = original.copyWith(
      headers: retryHeaders,
      extra: retryExtra,
    );
    try {
      final response = await retryDio.fetch<Object?>(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  Future<DioException> _forceLogoutAndTag(
    DioException err, {
    Response<Object?>? overrideResponse,
  }) async {
    await tokenStore.clearTokens();
    if (err.requestOptions.extra[forceLogoutNotifiedKey] != true) {
      onForceLogout?.call();
    }
    final nextExtra = Map<String, Object?>.of(err.requestOptions.extra);
    nextExtra[forceLogoutNotifiedKey] = true;
    return err.copyWith(
      requestOptions: err.requestOptions.copyWith(extra: nextExtra),
      response: overrideResponse ?? err.response,
    );
  }

  static String? _extractErrorCode(Object? data) {
    if (data is Map<Object?, Object?>) {
      final raw = data['error_code'];
      if (raw is String && raw.isNotEmpty) {
        return raw;
      }
    }
    return null;
  }

  static String? _extractBearerToken(Object? header) {
    if (header is! String) {
      return null;
    }
    const prefix = 'Bearer ';
    return header.startsWith(prefix) ? header.substring(prefix.length) : null;
  }

  static ({String accessToken, String refreshToken})? _parseTokenPair(
    Object? data,
  ) {
    if (data is! Map<Object?, Object?>) {
      return null;
    }
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    if (access is String &&
        access.isNotEmpty &&
        refresh is String &&
        refresh.isNotEmpty) {
      return (accessToken: access, refreshToken: refresh);
    }
    return null;
  }
}
