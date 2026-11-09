import '../../profile/application/profile.dart';

/// The questions offered before a student types, by year. Every one is
/// answered from their own numbers, so none of them uses an AI action:
/// `supabase/functions/_shared/coach/starters_test.ts` reads this file and
/// proves it. Keep each starter a single-line string literal.
List<String> startersFor(YearMode mode) => switch (mode) {
  YearMode.discover => const [
    'What should I do next?',
    'How am I doing?',
    'Explain my score',
    'How far through my roadmap am I?',
  ],
  YearMode.explore => const [
    'What should I do next?',
    'Explain my score',
    'What skills am I missing?',
    'How far through my roadmap am I?',
  ],
  YearMode.build => const [
    'What should I do next?',
    'What skills am I missing?',
    'Is my CV ok?',
    'How do I prepare for an interview?',
  ],
  YearMode.prove => const [
    'What should I do next?',
    'Is my CV ok?',
    'How do I prepare for an interview?',
    'What is coming up this week?',
  ],
  YearMode.launch || YearMode.graduate => const [
    'What is coming up this week?',
    'How do I prepare for an interview?',
    'Is my CV ok?',
    'Explain my score',
  ],
};
