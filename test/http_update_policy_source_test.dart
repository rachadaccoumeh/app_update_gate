import 'dart:convert';

import 'package:app_update_gate/src/http_update_policy_source.dart';
import 'package:app_update_gate/src/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uri = Uri.parse('https://api.example.com/app-version');

  UpdatePolicy mapper(Map<String, dynamic> json) => UpdatePolicy(
    minRequiredVersion: json['min_version'] as String?,
    recommendedVersion: json['recommended_version'] as String?,
    message: (json['message'] as String?) ?? '',
  );

  group('HttpUpdatePolicySource.fetchPolicy', () {
    test('GETs the endpoint and maps the JSON response', () async {
      late http.Request seen;
      final source = HttpUpdatePolicySource(
        uri: uri,
        mapper: mapper,
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'min_version': '1.3.0',
              'recommended_version': '1.5.0',
              'message': 'Please update.',
            }),
            200,
          );
        }),
      );

      final policy = await source.fetchPolicy();

      expect(seen.method, 'GET');
      expect(seen.url, uri);
      expect(policy.minRequiredVersion, '1.3.0');
      expect(policy.recommendedVersion, '1.5.0');
      expect(policy.message, 'Please update.');
    });

    test('sends headers from an async headersBuilder (auth tokens)', () async {
      late http.Request seen;
      final source = HttpUpdatePolicySource(
        uri: uri,
        headersBuilder: () async => {'Authorization': 'Bearer token-123'},
        mapper: mapper,
        client: MockClient((request) async {
          seen = request;
          return http.Response('{}', 200);
        }),
      );

      await source.fetchPolicy();

      expect(seen.headers['Authorization'], 'Bearer token-123');
    });

    test('POSTs the body from bodyBuilder', () async {
      late http.Request seen;
      final source = HttpUpdatePolicySource(
        uri: uri,
        method: 'POST',
        bodyBuilder: () => jsonEncode({'platform': 'android'}),
        mapper: mapper,
        client: MockClient((request) async {
          seen = request;
          return http.Response('{}', 200);
        }),
      );

      await source.fetchPolicy();

      expect(seen.method, 'POST');
      expect(seen.body, jsonEncode({'platform': 'android'}));
    });

    test('throws on a non-2xx status (callers fail open)', () async {
      final source = HttpUpdatePolicySource(
        uri: uri,
        mapper: mapper,
        client: MockClient((_) async => http.Response('nope', 500)),
      );

      expect(source.fetchPolicy(), throwsException);
    });

    test('throws when the response is not a JSON object', () async {
      final source = HttpUpdatePolicySource(
        uri: uri,
        mapper: mapper,
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      expect(source.fetchPolicy(), throwsA(anything));
    });
  });

  group('UpdatePolicy defaults', () {
    test('forcing is enabled and store check is respected by default', () {
      const policy = UpdatePolicy();
      expect(policy.forceUpdateEnabled, isTrue);
      expect(policy.ignoreStoreCheck, isFalse);
      expect(policy.minRequiredVersion, isNull);
      expect(policy.recommendedVersion, isNull);
      expect(policy.message, '');
    });
  });
}
