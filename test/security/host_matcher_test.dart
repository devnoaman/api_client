import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HostMatcher', () {
    test('normalizeHost cleans up URLs, schemes, ports, and paths', () {
      expect(HostMatcher.normalizeHost('api.example.com'), 'api.example.com');
      expect(
        HostMatcher.normalizeHost('https://api.example.com:443/v1/auth'),
        'api.example.com',
      );
      expect(
        HostMatcher.normalizeHost('HTTP://API.EXAMPLE.COM:8080/'),
        'api.example.com',
      );
      expect(HostMatcher.normalizeHost('  api.example.com  '), 'api.example.com');
    });

    test('matches exact hostnames', () {
      expect(
        HostMatcher.matches('api.example.com', 'api.example.com'),
        isTrue,
      );
      expect(
        HostMatcher.matches('api.example.com', 'auth.example.com'),
        isFalse,
      );
    });

    test('matches wildcard patterns (*.example.com)', () {
      expect(
        HostMatcher.matches('api.example.com', '*.example.com'),
        isTrue,
      );
      expect(
        HostMatcher.matches('auth.example.com', '*.example.com'),
        isTrue,
      );
      expect(
        HostMatcher.matches('v1.api.example.com', '*.example.com'),
        isTrue,
      );
      expect(
        HostMatcher.matches('example.com', '*.example.com'),
        isTrue,
      );
      expect(
        HostMatcher.matches('notexample.com', '*.example.com'),
        isFalse,
      );
      expect(
        HostMatcher.matches('api.other.com', '*.example.com'),
        isFalse,
      );
    });

    test('matches catch-all wildcard (*)', () {
      expect(HostMatcher.matches('api.example.com', '*'), isTrue);
      expect(HostMatcher.matches('any.domain.org', '*'), isTrue);
    });

    test('findMatchingPins aggregates pins from exact, wildcard, and catch-all rules', () {
      final allowedPins = {
        'api.example.com': ['pin_exact_1', 'pin_exact_2'],
        '*.example.com': ['pin_wildcard_1'],
        '*': ['pin_global'],
        'auth.example.com': ['pin_auth'],
      };

      final apiPins =
          HostMatcher.findMatchingPins('api.example.com', allowedPins);
      expect(apiPins, containsAll(['pin_exact_1', 'pin_exact_2', 'pin_wildcard_1', 'pin_global']));
      expect(apiPins, isNot(contains('pin_auth')));

      final otherSubPins =
          HostMatcher.findMatchingPins('other.example.com', allowedPins);
      expect(otherSubPins, containsAll(['pin_wildcard_1', 'pin_global']));
      expect(otherSubPins, isNot(contains('pin_exact_1')));

      final randomPins =
          HostMatcher.findMatchingPins('unrelated.io', allowedPins);
      expect(randomPins, contains('pin_global'));
      expect(randomPins.length, 1);
    });
  });
}
