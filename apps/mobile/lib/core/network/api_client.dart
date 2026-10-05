import 'package:dio/dio.dart';

import '../config.dart';
import 'token_storage.dart';

/// Central error type surfaced to the UI with a stable [code].
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>;
      return ApiException(
        err['code'] as String? ?? 'unknown',
        err['message'] as String? ?? 'Erreur inattendue',
        statusCode: e.response?.statusCode,
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException('offline', 'Pas de connexion Internet');
    }
    return ApiException(
      'network_error',
      'Le serveur est injoignable',
      statusCode: e.response?.statusCode,
    );
  }

  @override
  String toString() => message;
}

/// Dio client with bearer auth + transparent access-token refresh on 401.
class ApiClient {
  ApiClient(this._tokens, {this.onSessionExpired, Dio? refreshClient})
    : _refreshClient =
          refreshClient ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              followRedirects: false,
            ),
          ),
      dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          followRedirects: false,
        ),
      ) {
    AppConfig.validate();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final base = Uri.parse(AppConfig.apiBaseUrl);
          if (options.uri.origin != base.origin) {
            return handler.reject(
              DioException(
                requestOptions: options,
                error: 'Foreign API origin',
              ),
            );
          }
          if (!options.path.contains('/auth/login') &&
              !options.path.contains('/auth/register') &&
              !options.path.contains('/auth/refresh')) {
            final access = await _tokens.readAccess();
            if (access != null) {
              options.headers['Authorization'] = 'Bearer $access';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthCall = error.requestOptions.path.contains('/auth/');
          if (error.response?.statusCode == 401 &&
              !isAuthCall &&
              error.requestOptions.extra['auth_retried'] != true) {
            final current = await _tokens.readAccess();
            final alreadyRefreshed =
                current != null &&
                error.requestOptions.headers['Authorization'] !=
                    'Bearer $current';
            final refreshed = alreadyRefreshed || await _tryRefresh();
            if (refreshed) {
              final request = error.requestOptions;
              request.extra['auth_retried'] = true;
              request.headers['Authorization'] =
                  'Bearer ${await _tokens.readAccess()}';
              try {
                final response = await dio.fetch(request);
                return handler.resolve(response);
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
          }
          if (error.response?.statusCode == 401 && !isAuthCall) {
            await _tokens.clear();
            await onSessionExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final Dio _refreshClient;
  int sessionGeneration = 0;
  void invalidateSession() => sessionGeneration++;
  final TokenStorage _tokens;
  final Future<void> Function()? onSessionExpired;
  Future<bool>? _refreshing;

  Future<bool> _tryRefresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final generation = sessionGeneration;
    final refresh = await _tokens.readRefresh();
    if (refresh == null) return false;
    try {
      final response = await _refreshClient.post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      return _tokens.saveIfCurrent(
        access: response.data['access_token'] as String,
        refresh: response.data['refresh_token'] as String,
        isCurrent: () => generation == sessionGeneration,
      );
    } on DioException catch (error) {
      if ([400, 401, 403].contains(error.response?.statusCode)) {
        await _tokens.clear();
      }
      return false;
    }
  }
}
