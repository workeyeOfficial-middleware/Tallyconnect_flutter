// HTTP client for the TallyConnect backend. One place that adds the Bearer
// token, applies timeouts, decodes JSON and turns every failure into an
// [ApiException] with a kind the UI can act on.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiConfig {
  const ApiConfig._();

  /// Override at build time with `--dart-define=TC_API_BASE=https://…`.
  static const String baseUrl = String.fromEnvironment(
    'TC_API_BASE',
    defaultValue: 'https://tallyconnect-wlup.onrender.com',
  );

  /// The host sleeps when idle; the first call after a pause can take close
  /// to a minute, so the timeout is generous.
  static const Duration timeout = Duration(seconds: 75);
}

enum ApiErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  badRequest,
  server,
  parse,
}

class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.status, this.body});
  final ApiErrorKind kind;
  final String message;
  final int? status;
  final Object? body;

  /// Short sentence for a toast / error row.
  String get userMessage => switch (kind) {
    ApiErrorKind.network => 'No internet connection. Check your network.',
    ApiErrorKind.timeout => 'The server took too long to answer. Try again.',
    ApiErrorKind.unauthorized =>
      message.isNotEmpty && message != 'Unauthorized' && message != 'Invalid token'
          ? message
          : 'Your session has ended. Please log in again.',
    ApiErrorKind.server =>
      message.isNotEmpty ? message : 'Server error. Try again later.',
    _ => message.isNotEmpty ? message : 'Something went wrong.',
  };

  @override
  String toString() => 'ApiException($kind, $status, $message)';
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.timeout = ApiConfig.timeout})
    : _http = client ?? http.Client(),
      _base = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _http;
  final String _base;
  final Duration timeout;

  /// Current JWT; null when logged out.
  String? token;

  Uri uri(String path, [Map<String, Object?>? query]) {
    final Map<String, String> q = <String, String>{
      for (final MapEntry<String, Object?> e
          in (query ?? const <String, Object?>{}).entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
    };
    return Uri.parse('$_base$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> _headers({bool json = false, bool auth = true}) =>
      <String, String>{
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (auth && token != null) 'Authorization': 'Bearer $token',
      };

  Future<Object?> get(String path, {Map<String, Object?>? query, bool auth = true}) =>
      _send(() => _http.get(uri(path, query), headers: _headers(auth: auth)));

  Future<Object?> post(String path, {Object? body, bool auth = true}) => _send(
    () => _http.post(
      uri(path),
      headers: _headers(json: true, auth: auth),
      body: jsonEncode(body ?? const <String, Object?>{}),
    ),
  );

  Future<Object?> put(String path, {Object? body}) => _send(
    () => _http.put(
      uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body ?? const <String, Object?>{}),
    ),
  );

  Future<Object?> delete(String path) =>
      _send(() => _http.delete(uri(path), headers: _headers()));

  Future<Object?> _send(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout, 'Request timed out');
    } on SocketException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    } on HandshakeException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    } on http.ClientException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message);
    }
    Object? body;
    final String text = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (text.trim().isNotEmpty) {
      try {
        body = jsonDecode(text);
      } catch (_) {
        body = text; // Express default error pages are HTML / text.
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (body is Map && body['success'] == false) {
        // Some routes answer 200 with `{success:false}` on failure.
        throw ApiException(
          ApiErrorKind.server,
          _messageOf(body),
          status: r.statusCode,
          body: body,
        );
      }
      return body;
    }
    final String msg = _messageOf(body);
    final ApiErrorKind kind = switch (r.statusCode) {
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      >= 400 && < 500 => ApiErrorKind.badRequest,
      _ => ApiErrorKind.server,
    };
    throw ApiException(kind, msg, status: r.statusCode, body: body);
  }

  static String _messageOf(Object? body) {
    if (body is Map) {
      for (final String k in <String>['message', 'error']) {
        final Object? v = body[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }
    if (body is String) {
      final String t = body.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
      return t.length > 160 ? '' : t;
    }
    return '';
  }

  void close() => _http.close();
}
