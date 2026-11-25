import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/auth_header_interceptor.dart';
import 'package:ecotrack_mobile/core/network/error_catalog_mapper_interceptor.dart';
import 'package:ecotrack_mobile/core/network/idempotency_key_interceptor.dart';
import 'package:ecotrack_mobile/core/network/local_preview_interceptor.dart';
import 'package:ecotrack_mobile/core/network/token_refresh_interceptor.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';

final class const RawHttpOutcome({
  required final bool isSuccess,
  final int? statusCode,
  final Object? data,
  final String? retryAfterHeader,
  final AppError? error,
});

final class DioClient({
  required final TokenStore tokenStore,
  final String? baseUrl,
  Dio? dio,
  final void Function()? onForceLogout,
  final void Function(AppError error)? onGateError,
}) {
  this {
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final baseOptions = BaseOptions(
      baseUrl: resolvedBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      headers: const <String, Object?>{'Accept': 'application/json'},
    );

    _dio = dio ?? Dio(baseOptions);
    if (_dio.options.baseUrl.isEmpty) {
      _dio.options.baseUrl = resolvedBaseUrl;
    }

    _bareRefreshDio = Dio(
      BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        sendTimeout: _dio.options.sendTimeout,
        headers: const <String, Object?>{'Accept': 'application/json'},
      ),
    );
    if (dio != null) {
      _bareRefreshDio.httpClientAdapter = dio.httpClientAdapter;
    }

    _errorMapper = ErrorCatalogMapperInterceptor(
      onForceLogout: onForceLogout,
      onGateError: onGateError,
    );

    _dio.interceptors.addAll([
      if (dio == null) LocalPreviewInterceptor(tokenStore),
      AuthHeaderInterceptor(tokenStore),
      const IdempotencyKeyInterceptor(),
      TokenRefreshInterceptor(
        tokenStore: tokenStore,
        retryDio: _dio,
        bareRefreshDio: _bareRefreshDio,
        onForceLogout: onForceLogout,
      ),
      _errorMapper,
    ]);
  }

  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  late final Dio _dio;
  late final Dio _bareRefreshDio;
  late final ErrorCatalogMapperInterceptor _errorMapper;

  Dio get dio => _dio;

  Future<Result<T, AppError>> get<T>(
    String path, {
    Map<String, Object?>? queryParameters,
    required T Function(Object? data) parser,
  }) => _request<T>(
    method: 'GET',
    path: path,
    queryParameters: queryParameters,
    parser: parser,
  );

  Future<Result<T, AppError>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    required T Function(Object? data) parser,
  }) => _request<T>(
    method: 'POST',
    path: path,
    data: data,
    headers: headers,
    parser: parser,
  );

  Future<Result<T, AppError>> put<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    required T Function(Object? data) parser,
  }) => _request<T>(
    method: 'PUT',
    path: path,
    data: data,
    headers: headers,
    parser: parser,
  );

  Future<Result<T, AppError>> patch<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    required T Function(Object? data) parser,
  }) => _request<T>(
    method: 'PATCH',
    path: path,
    data: data,
    headers: headers,
    parser: parser,
  );

  Future<Result<T, AppError>> delete<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
    required T Function(Object? data) parser,
  }) => _request<T>(
    method: 'DELETE',
    path: path,
    data: data,
    headers: headers,
    parser: parser,
  );

  Future<Result<Object?, AppError>> sendRaw(
    String method,
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) => _request<Object?>(
    method: method,
    path: path,
    data: data,
    headers: headers,
    parser: (raw) => raw,
  );

  Future<RawHttpOutcome> sendWithOutcome(
    String method,
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        options: Options(method: method.toUpperCase(), headers: headers),
      );
      return RawHttpOutcome(
        isSuccess: true,
        statusCode: response.statusCode,
        data: response.data,
      );
    } on DioException catch (err) {
      final appError = _errorMapper.mapDioException(err);
      final retryAfter = err.response?.headers.value('retry-after');
      return RawHttpOutcome(
        isSuccess: false,
        statusCode: err.response?.statusCode,
        data: err.response?.data,
        retryAfterHeader: retryAfter,
        error: appError,
      );
    }
  }

  Future<Result<T, AppError>> _request<T>({
    required String method,
    required String path,
    Map<String, Object?>? queryParameters,
    Object? data,
    Map<String, String>? headers,
    required T Function(Object? data) parser,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: headers),
      );
      return Ok<T, AppError>(parser(response.data));
    } on DioException catch (err) {
      return Err<T, AppError>(_errorMapper.mapDioException(err));
    }
  }
}
