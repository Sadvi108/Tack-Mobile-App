import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tack/core/crash_reporting.dart';

/// Sentry is the one place anything about a student leaves the Supabase
/// project, so what it is allowed to carry is tested rather than trusted to a
/// remote default that could change under us.
void main() {
  group('breadcrumbs', () {
    test('a long one is treated as something the student wrote', () {
      // A pasted job description or a typed interview answer.
      final crumb = Breadcrumb(
        message:
            'We are looking for a junior frontend developer with strong '
            'JavaScript and React skills to join our Dhaka office and help '
            'build customer-facing features.',
      );
      expect(CrashReportingTestAccess.looksPersonal(crumb), isTrue);
    });

    test('console output is dropped, because it echoes anything', () {
      expect(
        CrashReportingTestAccess.looksPersonal(
          Breadcrumb(message: 'tapped', category: 'console'),
        ),
        isTrue,
      );
    });

    test('typed input is dropped', () {
      expect(
        CrashReportingTestAccess.looksPersonal(
          Breadcrumb(message: 'field changed', category: 'ui.input'),
        ),
        isTrue,
      );
    });

    test('an email address anywhere in the message is caught', () {
      expect(
        CrashReportingTestAccess.looksPersonal(
          Breadcrumb(message: 'sign in failed for rafiq@example.com'),
        ),
        isTrue,
      );
    });

    test('a Bangladeshi phone number is caught however it is written', () {
      for (final number in [
        '+8801712345678',
        '01712345678',
        '+880 1712 345 678',
      ]) {
        expect(
          CrashReportingTestAccess.looksPersonal(
            Breadcrumb(message: 'lookup for $number'),
          ),
          isTrue,
          reason: '$number survived',
        );
      }
    });

    test('an ordinary navigation crumb is kept', () {
      // Without these a stack trace has no story around it.
      expect(
        CrashReportingTestAccess.looksPersonal(
          Breadcrumb(message: 'navigated to /roadmap', category: 'navigation'),
        ),
        isFalse,
      );
    });
  });

  group('the event that actually leaves', () {
    test('keeps the account id and drops everything identifying', () {
      final event = SentryEvent(
        user: SentryUser(
          id: 'cfc2536d-f27c-4b16-885a-30bcfd0fbff3',
          email: 'rafiq@example.com',
          name: 'Rafiq Hossain',
          username: 'rafiq',
          ipAddress: '203.0.113.9',
        ),
      );

      final scrubbed = CrashReportingTestAccess.scrub(event)!;

      expect(scrubbed.user!.id, 'cfc2536d-f27c-4b16-885a-30bcfd0fbff3');
      expect(scrubbed.user!.email, isNull);
      expect(scrubbed.user!.name, isNull);
      expect(scrubbed.user!.username, isNull);
      expect(scrubbed.user!.ipAddress, isNull);
    });

    test('a signed-out crash carries no user at all', () {
      final scrubbed = CrashReportingTestAccess.scrub(SentryEvent())!;
      expect(scrubbed.user, isNull);
    });

    test('personal breadcrumbs are stripped from the event', () {
      final event = SentryEvent(
        breadcrumbs: [
          Breadcrumb(message: 'navigated to /vault', category: 'navigation'),
          Breadcrumb(message: 'contacted rafiq@example.com'),
        ],
      );

      final scrubbed = CrashReportingTestAccess.scrub(event)!;
      expect(scrubbed.breadcrumbs, hasLength(1));
      expect(scrubbed.breadcrumbs!.single.message, 'navigated to /vault');
    });
  });
}
