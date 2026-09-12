// new_flutter_app/lib/services/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'token_storage.dart';

/// Custom exception representing API errors with user-friendly messages.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic detail;

  const ApiException({
    required this.message,
    this.statusCode,
    this.detail,
  });

  @override
  String toString() => message;
}

/// Centralized HTTP client managing requests, token injection, and error extraction.
class ApiClient {
  final http.Client _client;
  final TokenStorage _tokenStorage;
  final String _baseUrl;
  final void Function()? onSessionExpired;

  ApiClient({
    http.Client? client,
    TokenStorage? tokenStorage,
    String? baseUrl,
    this.onSessionExpired,
  })  : _client = client ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorage(),
        _baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  /// Releases sockets owned by this client when its application scope ends.
  void close() => _client.close();

  /// Builds the full URI for the given endpoint or path.
  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$cleanPath').replace(
      queryParameters:
          queryParameters?.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  /// Builds request headers including JSON content type and authorization token if required.
  Future<Map<String, String>> _buildHeaders({
    bool requiresAuth = false,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      final token = await _tokenStorage.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }

    return headers;
  }

  /// Sends a GET request.
  Future<dynamic> get(
    String path, {
    bool requiresAuth = true,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? extraHeaders,
  }) async {
    return _sendRequest(
      () async {
        final uri = _buildUri(path, queryParameters);
        final headers = await _buildHeaders(
            requiresAuth: requiresAuth, extraHeaders: extraHeaders);
        return await _client
            .get(uri, headers: headers)
            .timeout(AppConstants.requestTimeout);
      },
      requiresAuth: requiresAuth,
    );
  }

  /// Sends a POST request.
  Future<dynamic> post(
    String path, {
    dynamic body,
    bool requiresAuth = false,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? extraHeaders,
  }) async {
    return _sendRequest(
      () async {
        final uri = _buildUri(path, queryParameters);
        final headers = await _buildHeaders(
            requiresAuth: requiresAuth, extraHeaders: extraHeaders);
        final encodedBody = body != null ? jsonEncode(body) : null;
        return await _client
            .post(uri, headers: headers, body: encodedBody)
            .timeout(AppConstants.requestTimeout);
      },
      requiresAuth: requiresAuth,
    );
  }

  Stream<String> postSse(
    String path, {
    dynamic body,
    bool requiresAuth = true,
  }) async* {
    try {
      final request = http.Request('POST', _buildUri(path));
      request.headers.addAll(await _buildHeaders(
        requiresAuth: requiresAuth,
        extraHeaders: const {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        },
      ));
      if (body != null) request.body = jsonEncode(body);
      final response =
          await _client.send(request).timeout(AppConstants.requestTimeout);
      if (response.statusCode == 401 && requiresAuth) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          yield* postSse(path, body: body, requiresAuth: requiresAuth);
          return;
        }
        await _tokenStorage.deleteToken();
        onSessionExpired?.call();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bodyText = await response.stream.bytesToString();
        throw ApiException(
          message:
              _extractErrorMessage(bodyText) ?? 'The streaming request failed.',
          statusCode: response.statusCode,
        );
      }
      yield* response.stream.transform(utf8.decoder).transform(
            const LineSplitter(),
          );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
          message: 'The request took too long. Please try again.');
    } on SocketException {
      throw const ApiException(message: 'Unable to connect to the server.');
    } on http.ClientException {
      throw const ApiException(message: 'Unable to connect to the server.');
    }
  }

  /// Sends a PATCH request.
  Future<dynamic> patch(
    String path, {
    dynamic body,
    bool requiresAuth = true,
    Map<String, String>? extraHeaders,
  }) async {
    return _sendRequest(
      () async {
        final uri = _buildUri(path);
        final headers = await _buildHeaders(
            requiresAuth: requiresAuth, extraHeaders: extraHeaders);
        final encodedBody = body != null ? jsonEncode(body) : null;
        return await _client
            .patch(uri, headers: headers, body: encodedBody)
            .timeout(AppConstants.requestTimeout);
      },
      requiresAuth: requiresAuth,
    );
  }

  /// Sends a PUT request.
  Future<dynamic> put(
    String path, {
    dynamic body,
    bool requiresAuth = true,
    Map<String, String>? extraHeaders,
  }) async {
    return _sendRequest(
      () async {
        final uri = _buildUri(path);
        final headers = await _buildHeaders(
            requiresAuth: requiresAuth, extraHeaders: extraHeaders);
        final encodedBody = body != null ? jsonEncode(body) : null;
        return await _client
            .put(uri, headers: headers, body: encodedBody)
            .timeout(AppConstants.requestTimeout);
      },
      requiresAuth: requiresAuth,
    );
  }

  /// Sends a DELETE request.
  Future<dynamic> delete(
    String path, {
    bool requiresAuth = true,
    Map<String, String>? extraHeaders,
  }) async {
    return _sendRequest(
      () async {
        final uri = _buildUri(path);
        final headers = await _buildHeaders(
            requiresAuth: requiresAuth, extraHeaders: extraHeaders);
        return await _client
            .delete(uri, headers: headers)
            .timeout(AppConstants.requestTimeout);
      },
      requiresAuth: requiresAuth,
    );
  }

  /// Executes request with comprehensive timeout, network, and status error handling.
  Future<dynamic> _sendRequest(
    Future<http.Response> Function() requestFn, {
    required bool requiresAuth,
    bool retried = false,
  }) async {
    try {
      final response = await requestFn();
      if (response.statusCode == 401 && requiresAuth && !retried) {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          return await _sendRequest(
            requestFn,
            requiresAuth: true,
            retried: true,
          );
        }
      }
      return await _handleResponse(response, requiresAuth: requiresAuth);
    } on TimeoutException {
      throw const ApiException(
        message: 'The request took too long. Please try again.',
      );
    } on SocketException {
      throw const ApiException(
        message:
            'Unable to connect to the server. Check your internet connection and try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        message:
            'Unable to connect to the server. Check your internet connection and try again.',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw const ApiException(
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  /// Handles HTTP responses, status codes, and JSON parsing.
  Future<dynamic> _handleResponse(
    http.Response response, {
    required bool requiresAuth,
  }) async {
    final statusCode = response.statusCode;

    // Successful responses
    if (statusCode >= 200 && statusCode < 300) {
      if (statusCode == 204 || response.body.trim().isEmpty) {
        return null;
      }
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return response.body;
      }
    }

    // 401 Unauthorized handling
    if (statusCode == 401) {
      if (requiresAuth) {
        await _tokenStorage.deleteToken();
        onSessionExpired?.call();
      }
      final errorMsg = _extractErrorMessage(response.body) ??
          'Invalid or expired session. Please log in again.';
      throw ApiException(
        message: errorMsg,
        statusCode: 401,
      );
    }

    if (statusCode == 429) {
      throw const ApiException(
        message: 'Too many requests. Please wait a moment and try again.',
        statusCode: 429,
      );
    }

    // 500 Internal Server Error handling
    if (statusCode >= 500) {
      throw const ApiException(
        message: 'Something went wrong on the server. Please try again later.',
        statusCode: 500,
      );
    }

    // Client errors (400, 404, 422, etc.)
    final extractedError = _extractErrorMessage(response.body);
    final fallbackMessage = statusCode == 404
        ? 'Requested resource not found.'
        : 'Request failed. Please check your input and try again.';

    throw ApiException(
      message: extractedError ?? fallbackMessage,
      statusCode: statusCode,
    );
  }

  /// Safely extracts error details from FastAPI {"detail": ...} or {"message": ...} formats.
  String? _extractErrorMessage(String responseBody) {
    if (responseBody.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('detail')) {
          final detail = decoded['detail'];
          if (detail is String && detail.trim().isNotEmpty) {
            return detail.trim();
          }
          if (detail is List && detail.isNotEmpty) {
            final first = detail.first;
            if (first is Map && first.containsKey('msg')) {
              return first['msg'].toString();
            }
            return detail.map((e) => e.toString()).join('\n');
          }
        }
        if (decoded.containsKey('message')) {
          final msg = decoded['message'];
          if (msg is String && msg.trim().isNotEmpty) {
            return msg.trim();
          }
        }
        if (decoded.containsKey('error') && decoded['error'] is Map) {
          final errorObj = decoded['error'];
          if (errorObj.containsKey('message') && errorObj['message'] is String) {
            return errorObj['message'].toString().trim();
          }
        }
      }
    } catch (_) {
      // Body is not JSON
    }
    return null;
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await _client
          .post(
            _buildUri(AppConstants.refreshEndpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(AppConstants.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final access =
          (decoded['access_token'] ?? decoded['accessToken'])?.toString();
      if (access == null || access.trim().isEmpty) return false;
      await _tokenStorage.saveToken(access.trim());
      final nextRefresh =
          (decoded['refresh_token'] ?? decoded['refreshToken'])?.toString();
      if (nextRefresh != null && nextRefresh.trim().isNotEmpty) {
        await _tokenStorage.saveRefreshToken(nextRefresh.trim());
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}