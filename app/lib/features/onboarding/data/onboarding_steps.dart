import '../../profile/data/education_stage.dart';

/// The onboarding path, which is not the same for everyone.
///
/// Everybody answers who they are and where they are in their education. What
/// comes after that depends entirely on the answer: a school student is asked
/// about subjects and what they want to study, an undergraduate about their
/// degree and year, a graduate about the degree they finished and the job they
/// want. Asking one set of questions of all three would mean most of them were
/// wrong for most people.
enum OnboardingStep {
  /// Name, country, city, phone.
  basics,

  /// The fork: primary, high school, bachelor's, graduated.
  stage,

  /// School, class and grades — or university, degree and year.
  study,

  /// Favourite subjects and hobbies — or courses and skills.
  interests,

  /// What they want to study next — or the job they are aiming at.
  direction;

  String titleFor(EducationStage? stage) => switch (this) {
    OnboardingStep.basics => 'About you',
    OnboardingStep.stage => 'Where you are',
    OnboardingStep.study =>
      stage?.isAtSchool ?? false ? 'Your school' : 'Your degree',
    OnboardingStep.interests =>
      stage?.isAtSchool ?? false ? 'What you enjoy' : 'What you can do',
    OnboardingStep.direction =>
      stage?.isAtSchool ?? false ? 'What you want next' : 'What you want',
  };

  String blurbFor(EducationStage? stage) => switch (this) {
    OnboardingStep.basics => 'So the app can address you properly.',
    OnboardingStep.stage =>
      'This decides everything the app shows you. You can change it later.',
    OnboardingStep.study =>
      stage?.isAtSchool ?? false
          ? 'Your grades are never shown to anyone. They only feed your own score.'
          : stage == EducationStage.graduated
          ? 'What you finished, and where.'
          : 'Your CGPA is optional and is never shown to anyone.',
    OnboardingStep.interests =>
      stage?.isAtSchool ?? false
          ? 'Subjects you like and things you do outside class. Both count.'
          : 'Pick anything you have done, even at a beginner level.',
    OnboardingStep.direction =>
      stage?.isAtSchool ?? false
          ? 'No pressure — a rough idea is enough, and it can change.'
          : 'A rough idea is enough. Nothing here is locked in.',
  };
}

/// How many steps a student will actually see, and where they are.
///
/// Every supported stage happens to take five steps, but the count is derived
/// rather than assumed so the progress bar stays honest if that changes.
class OnboardingPath {
  const OnboardingPath(this.stage);

  final EducationStage? stage;

  List<OnboardingStep> get steps => OnboardingStep.values;

  int get length => steps.length;

  int numberOf(OnboardingStep step) => steps.indexOf(step) + 1;

  OnboardingStep? after(OnboardingStep step) {
    final next = steps.indexOf(step) + 1;
    return next >= steps.length ? null : steps[next];
  }

  OnboardingStep? before(OnboardingStep step) {
    final previous = steps.indexOf(step) - 1;
    return previous < 0 ? null : steps[previous];
  }
}
