import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class AuthRefreshInterceptor extends QueuedInterceptorsWrapper {
  AuthRefreshInterceptor({
    required FlutterSecureStorage secureStorage,
    required Dio dio,
  }) : _secureStorage = secureStorage,
       _dio = dio;

  final FlutterSecureStorage _secureStorage;
  final Dio _dio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _secureStorage.read(key: 'jwt_access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.contains('/auth/')) {
      final refreshToken = await _secureStorage.read(key: 'jwt_refresh_token');
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          final refreshResponse = await _dio.post<Map<String, Object?>>(
            '/v1/auth/refresh',
            data: {'refresh_token': refreshToken},
          );

          if (refreshResponse.data case {
            'access_token': final String newAccess,
          }) {
            await _secureStorage.write(
              key: 'jwt_access_token',
              value: newAccess,
            );

            final retryOptions = err.requestOptions;
            retryOptions.headers['Authorization'] = 'Bearer $newAccess';

            final retryResponse = await _dio.fetch<Object?>(retryOptions);
            return handler.resolve(retryResponse);
          }
        } catch (_) {
          // Token refresh failed, continue with original 401 error
        }
      }
    }
    handler.next(err);
  }
}
