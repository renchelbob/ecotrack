import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';

final class AuthHeaderInterceptor(final TokenStore _tokenStore)
    extends Interceptor {
  static const Set<String> _unauthenticatedPaths = {
    '/api/v1/auth/oauth/exchange',
    '/api/v1/auth/refresh',
    '/healthz',
    '/readyz',
  };

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final normalizedPath = Uri.tryParse(options.path)?.path ?? options.path;
    if (_unauthenticatedPaths.contains(normalizedPath)) {
      handler.next(options);
      return;
    }

    final token = await _tokenStore.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
