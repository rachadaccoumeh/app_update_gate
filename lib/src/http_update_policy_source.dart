import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_policy.dart';

/// Fetches the update policy from a user-defined HTTP endpoint.
///
/// The consumer owns the whole contract: endpoint, method, auth headers
/// (via [headersBuilder], sync or async so tokens can come from anywhere),
/// request body, and the [mapper] that turns the JSON response into an
/// [UpdatePolicy] for the current platform.
///
/// Any failure (network, non-2xx, bad JSON, mapper error) throws; the service
/// catches it and fails open.
class HttpUpdatePolicySource implements UpdatePolicySource {
  HttpUpdatePolicySource({
    required this.uri,
    this.method = 'GET',
    this.headersBuilder,
    this.bodyBuilder,
    this.timeout = const Duration(seconds: 8),
    required this.mapper,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The endpoint that serves the update policy.
  final Uri uri;

  /// HTTP method, `GET` by default.
  final String method;

  /// Builds the request headers on every fetch (e.g. a fresh auth token).
  final FutureOr<Map<String, String>> Function()? headersBuilder;

  /// Builds the request body on every fetch (POST/PUT payloads).
  final String Function()? bodyBuilder;

  /// Max time to wait for the response.
  final Duration timeout;

  /// Maps the decoded JSON object to the policy for the current platform.
  final UpdatePolicy Function(Map<String, dynamic> json) mapper;

  final http.Client _client;

  @override
  Future<UpdatePolicy> fetchPolicy() async {
    final request = http.Request(method, uri);
    final headers = await headersBuilder?.call();
    if (headers != null) request.headers.addAll(headers);
    final body = bodyBuilder?.call();
    if (body != null) request.body = body;

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Update policy request failed with HTTP ${response.statusCode}',
        uri,
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Update policy response is not a JSON object');
    }
    return mapper(decoded);
  }
}
