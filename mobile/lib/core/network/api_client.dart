import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/auth_refresh_interceptor.dart';
import 'package:ecotrack_mobile/core/network/idempotency_interceptor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class ApiClient {
  ApiClient({
    String baseUrl = 'http://127.0.0.1:8000',
    FlutterSecureStorage? secureStorage,
    Dio? customDio,
  }) {
    final storage = secureStorage ?? const FlutterSecureStorage();
    _dio =
        customDio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );

    _dio.interceptors.addAll([
      const IdempotencyInterceptor(),
      AuthRefreshInterceptor(secureStorage: storage, dio: _dio),
    ]);
  }

  late final Dio _dio;
  Dio get dio => _dio;

  Future<Result<T, AppError>> get<T>({
    required String path,
    Map<String, Object?>? queryParameters,
    required T Function(Object? json) fromJson,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return Ok(fromJson(response.data));
    } on DioException catch (e) {
      return Err(_mapDioException(e));
    } catch (e) {
      return Err(AppError.fromCode('VALIDATION_ERROR', e.toString()));
    }
  }

  Future<Result<T, AppError>> post<T>({
    required String path,
    Object? data,
    Map<String, Object?>? queryParameters,
    required T Function(Object? json) fromJson,
  }) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      return Ok(fromJson(response.data));
    } on DioException catch (e) {
      return Err(_mapDioException(e));
    } catch (e) {
      return Err(AppError.fromCode('VALIDATION_ERROR', e.toString()));
    }
  }

  AppError _mapDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return AppError.fromCode('NETWORK_UNAVAILABLE');
    }

    final data = e.response?.data;
    if (data case {'code': final String code}) {
      return AppError.fromCode(code);
    }
    if (data case {'detail': final String detail}) {
      return AppError.fromCode('VALIDATION_ERROR', detail);
    }

    final statusCode = e.response?.statusCode ?? 500;
    return switch (statusCode) {
      401 => AppError.fromCode('AUTH_REQUIRED'),
      403 => AppError.fromCode('FZ152_CONSENT_REQUIRED'),
      404 => AppError.fromCode(
        'VALIDATION_ERROR',
        'Запрашиваемый ресурс не найден.',
      ),
      503 => AppError.fromCode('DATABASE_UNAVAILABLE'),
      _ => AppError.fromCode('INTERNAL_SERVER_ERROR'),
    };
  }
}
