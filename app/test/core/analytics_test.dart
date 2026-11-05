import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/analytics.dart';
import 'package:tack/features/onboarding/domain/flow_config.dart';

/// The property filter is the last thing standing between a careless call site
/// and a student's name sitting in a table forever, so it is tested directly.
Map<String, Object?> clean(Map<String, Object?> input) =>
    // ignore: invalid_use_of_visible_for_testing_member
    AnalyticsTestAccess.clean(input);

// ignore: invalid_use_of_visible_for_testing_member
bool knows(String event) => AnalyticsTestAccess.knows(event);

/// Every value under [key] passes the filter on its own.
void allows(String key, Iterable<String> values) {
  for (final value in values) {
    expect(clean({key: value}), {key: value}, reason: '$key: $value');
  }
}

/// The 40 interview roles (contract C1.2), mirrored from `MANIFEST` in
/// `supabase/seed/interview_bank/validate.py`.
const _roles = [
  'management-trainee',
  'banking-officer',
  'credit-analyst',
  'accountant',
  'audit-associate',
  'business-analyst',
  'supply-chain-analyst',
  'operations-executive',
  'hr-executive',
  'sales-executive',
  'digital-marketer',
  'brand-executive',
  'market-research-analyst',
  'pharmaceutical-quality-analyst',
  'medical-promotion-officer',
  'development-programme-associate',
  'monitoring-and-evaluation-assistant',
  'civil-site-engineer',
  'electrical-engineer',
  'mechanical-engineer',
  'apparel-merchandiser',
  'industrial-engineer',
  'textile-production-associate',
  'textile-quality-inspector',
  'graphic-designer',
  'ui-and-ux-designer',
  'content-writer',
  'school-teacher',
  'civil-service-officer',
  'legal-associate',
  'software-engineer',
  'frontend-developer',
  'backend-developer',
  'full-stack-developer',
  'mobile-app-developer',
  'qa-engineer',
  'data-analyst',
  'it-support-specialist',
  'network-engineer',
  'telecommunications-engineer',
];

/// The coach's route ids (contract C7.2).
const _coachRoutes = [
  'interview',
  'practice',
  'analyser',
  'cv_check',
  'cv_builder',
  'roadmap',
  'radar',
  'score',
  'paths',
  'path',
  'applications',
  'profile',
];

void main() {
  group('what is allowed through', () {
    test('counts and flags are kept', () {
      final out = clean({'count': 3, 'mode': 'launch', 'completed': true});
      expect(out, {'count': 3, 'mode': 'launch', 'completed': true});
    });

    test('unknown identifiers are rejected', () {
      final out = clean({'path_slug': 'frontend-developer', 'step': 2});
      expect(out.containsKey('path_slug'), false);
      expect(out['step'], 2);
    });
  });

  group('what is dropped', () {
    test('short personal text under an unexpected or enum key is rejected', () {
      expect(
        clean({'safe': 'a@b.com', 'screen': 'a@b.com', 'mode': 'Rafiq'}),
        isEmpty,
      );
    });
    test('anything named after personal data', () {
      final out = clean({
        'name': 'Rafiq Hossain',
        'full_name': 'Rafiq Hossain',
        'email': 'rafiq@example.com',
        'phone': '+8801712345678',
        'address': 'Dhanmondi, Dhaka',
      });
      expect(out, isEmpty);
    });

    test('free text a student wrote', () {
      final out = clean({
        'notes': 'Spoke to the recruiter on Tuesday',
        'answer': 'I once fixed a bug in production',
        'cv_text': 'Rafiq Hossain, final year student',
        'description': 'Built an inventory app',
      });
      expect(out, isEmpty);
    });

    test('a long string, whatever it is called', () {
      // A job description pasted into a property named something innocent
      // must not survive on the strength of its key alone.
      final out = clean({
        'blob':
            'We are looking for a junior frontend developer with strong '
            'JavaScript and React skills to join our Dhaka office.',
      });
      expect(out, isEmpty);
    });

    test('structured values, which are where prose hides', () {
      final out = clean({
        'skills': ['Python', 'SQL'],
        'profile': {'name': 'Rafiq'},
      });
      expect(out, isEmpty);
    });

    test('the case of the key does not matter', () {
      expect(clean({'Email': 'a@b.com', 'FULL_NAME': 'Rafiq'}), isEmpty);
    });
  });

  test('a realistic event survives with only the safe parts', () {
    final out = clean({
      'screen': 'dashboard',
      'mode': 'explore',
      'name': 'Rafiq Hossain',
      'notes': 'anything at all',
      'actions_shown': 3,
    });
    expect(out, {'screen': 'dashboard', 'mode': 'explore', 'actions_shown': 3});
  });

  // The Toolkit round adds four events. Each carries fixed ids and counts,
  // never a title, a question, an answer or a name.
  group('tabs, tools, interviews and coach actions', () {
    test('the four new events are known', () {
      for (final event in [
        'tab_selected',
        'tool_opened',
        'interview_started',
        'coach_action_tapped',
      ]) {
        expect(knows(event), isTrue, reason: event);
      }
      expect(knows('anything_else'), isFalse);
    });

    test('every new key and value passes', () {
      allows('tab', ['home', 'roadmap', 'radar', 'toolkit', 'profile']);
      allows('tool', [
        'interview',
        'practise_again',
        'analyser',
        'cv_check',
        'cv_builder',
        'documents',
        'coach',
      ]);
      allows('source', ['toolkit', 'home', 'coach', 'application', 'score']);
      allows('tone', ['urgent', 'opportunity', 'neutral', 'positive']);
      allows('screen', ['toolkit', 'dashboard', 'vault']);
      allows('session_type', ['mixed', 'technical', 'behavioural']);
      allows('difficulty', ['easy', 'medium', 'hard']);
      allows('kind', ['pool', 'pack']);
      allows('role', _roles);
      allows('route', _coachRoutes);
    });

    test('the payloads survive whole', () {
      expect(clean({'tab': 'toolkit', 'mode': 'build'}), {
        'tab': 'toolkit',
        'mode': 'build',
      });
      expect(
        clean({
          'tool': 'practise_again',
          'source': 'toolkit',
          'mode': 'launch',
          'count': 3,
        }),
        {
          'tool': 'practise_again',
          'source': 'toolkit',
          'mode': 'launch',
          'count': 3,
        },
      );
      expect(
        clean({
          'role': 'data-analyst',
          'session_type': 'mixed',
          'difficulty': 'hard',
          'kind': 'pool',
        }),
        {
          'role': 'data-analyst',
          'session_type': 'mixed',
          'difficulty': 'hard',
          'kind': 'pool',
        },
      );
      expect(clean({'route': 'cv_check', 'mode': 'prove'}), {
        'route': 'cv_check',
        'mode': 'prove',
      });
    });

    test('free text under a new key is dropped', () {
      for (final key in [
        'tab',
        'tool',
        'source',
        'role',
        'route',
        'session_type',
        'difficulty',
        'kind',
        'insight',
      ]) {
        expect(clean({key: 'Rafiq'}), isEmpty, reason: key);
      }
      // A company or a job title is not a role id.
      expect(clean({'role': 'bKash'}), isEmpty);
      expect(clean({'role': 'Data analyst'}), isEmpty);
    });

    test('count stays a whole number', () {
      expect(clean({'count': 3}), {'count': 3});
      expect(clean({'count': '3'}), isEmpty);
      expect(clean({'count': 3.5}), isEmpty);
      expect(clean({'count': -1}), isEmpty);
    });

    test('the role list is the 40 roles of the interview manifest', () {
      expect(_roles.toSet(), hasLength(40));
      final manifest = File('../supabase/seed/interview_bank/validate.py');
      if (!manifest.existsSync()) return;
      // Only the MANIFEST dict: the file has other dicts of the same shape.
      final text = manifest.readAsStringSync();
      final start = text.indexOf('MANIFEST = {');
      expect(start, isNot(-1));
      final block = text.substring(start, text.indexOf('\n}', start));
      final slugs = RegExp(
        r'^    "([a-z0-9-]+)": \(',
        multiLine: true,
      ).allMatches(block).map((m) => m[1]!).toSet();
      expect(slugs, _roles.toSet());
    });
  });

  // Report 05 P2-2: the step ids the intake records were not on the list, so
  // every step event reached the table without saying which step it was.
  test('every onboarding step id survives', () {
    final steps = [
      ...OnboardingFlow.shared,
      ...OnboardingFlow.highSchoolSteps,
      ...OnboardingFlow.bachelorsSteps,
      ...OnboardingFlow.graduatedSteps,
      OnboardingFlow.review,
    ];
    expect(steps, isNotEmpty);
    allows('step', steps.map((step) => step.id));
  });

  // Opening a suggestion records its fixed id. None of them was on the list,
  // so insight_opened arrived empty.
  test('every insight id survives', () {
    final source = File(
      'lib/features/dashboard/application/insights.dart',
    ).readAsStringSync();
    final ids = RegExp(
      r"\bid: '([a-z-]+)'",
    ).allMatches(source).map((m) => m[1]!).toSet();
    expect(ids, isNotEmpty);
    allows('insight', ids);
    // Added to Home with the Toolkit round.
    allows('insight', ['interview-stage']);
  });
}
