import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../profile/data/education_stage.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/onboarding_repository.dart';
import '../data/onboarding_steps.dart';

/// Everything onboarding has collected so far.
///
/// One object covering all three paths rather than three: most of it is shared,
/// and the fields that only apply to one stage are simply left null. Which of
/// them are required is decided by [canContinue], not by the shape.
class OnboardingDraft {
  const OnboardingDraft({
    this.step = OnboardingStep.basics,
    this.fullName = '',
    this.countryId,
    this.dialCode = '+880',
    this.cityId,
    this.phone = '',
    this.stage,
    this.institutionName = '',
    this.universityId,
    this.degree = '',
    this.fieldOfStudy = '',
    this.classLevel,
    this.currentGrade = '',
    this.graduationYear,
    this.cgpa,
    this.yearOfStudy,
    this.yearsTotal = 4,
    this.expectedGraduation,
    this.favourites = const {},
    this.hobbies = const {},
    this.skillIds = const {},
    this.intendedField,
    this.passion = '',
    this.targetRole,
    this.targetIndustry = const {},
    this.busy = false,
    this.failure,
  });

  final OnboardingStep step;

  // ------------------------------------------------------------- who you are
  final String fullName;
  final String? countryId;
  final String dialCode;
  final String? cityId;
  final String phone;

  // ----------------------------------------------------------- where you are
  final EducationStage? stage;

  // --------------------------------------------------------------- study
  final String institutionName;
  final String? universityId;
  final String degree;
  final String fieldOfStudy;

  /// School only: "Class 10", "HSC first year".
  final String? classLevel;

  /// A label rather than a number — grading differs too much between boards
  /// and countries for a single scale to be honest.
  final String currentGrade;

  final int? graduationYear;
  final double? cgpa;
  final int? yearOfStudy;
  final int yearsTotal;
  final DateTime? expectedGraduation;

  // ------------------------------------------------------------ what you like
  /// Favourite subjects at school, favourite courses at university.
  final Set<String> favourites;
  final Set<String> hobbies;
  final Set<String> skillIds;

  // ----------------------------------------------------------- where you want
  /// School only: what they hope to study.
  final String? intendedField;
  final String passion;

  /// University and graduate: the job they are aiming at.
  final String? targetRole;
  final Set<String> targetIndustry;

  final bool busy;
  final Failure? failure;

  OnboardingPath get path => OnboardingPath(stage);
  bool get isAtSchool => stage?.isAtSchool ?? false;
  int get stepNumber => path.numberOf(step);
  int get stepCount => path.length;

  /// The mode this answer would produce, shown back on the stage step so the
  /// consequence of the choice is visible before it is made.
  YearMode get previewMode {
    final s = stage;
    if (s == null) return YearMode.school;
    if (s == EducationStage.primary || s == EducationStage.highSchool) {
      return YearMode.school;
    }
    if (s == EducationStage.graduated) return YearMode.graduate;

    final y = yearOfStudy;
    if (y == null) return YearMode.explore;
    if (y >= yearsTotal) return YearMode.launch;
    return switch (y) {
      1 => YearMode.explore,
      2 => YearMode.build,
      3 => YearMode.prove,
      _ => YearMode.launch,
    };
  }

  /// Continue stays disabled until the current step is answerable.
  ///
  /// What counts as answerable differs by stage, which is the whole point of
  /// branching: a school student has no CGPA and a graduate has no year.
  bool get canContinue => switch (step) {
    OnboardingStep.basics =>
      fullName.trim().length >= 2 && countryId != null && cityId != null,
    // Primary is a valid answer even though it cannot go forward — the screen
    // handles that, not the button.
    OnboardingStep.stage => stage != null,
    OnboardingStep.study => switch (stage) {
      EducationStage.highSchool =>
        institutionName.trim().isNotEmpty && (classLevel ?? '').isNotEmpty,
      EducationStage.bachelors =>
        (universityId != null || institutionName.trim().isNotEmpty) &&
            degree.trim().isNotEmpty &&
            yearOfStudy != null,
      EducationStage.graduated =>
        (universityId != null || institutionName.trim().isNotEmpty) &&
            degree.trim().isNotEmpty &&
            graduationYear != null,
      _ => false,
    },
    // Something they like, whichever kind it is.
    OnboardingStep.interests =>
      favourites.isNotEmpty || hobbies.isNotEmpty || skillIds.isNotEmpty,
    OnboardingStep.direction =>
      isAtSchool ? (intendedField ?? '').isNotEmpty : targetRole != null,
  };

  OnboardingDraft copyWith({
    OnboardingStep? step,
    String? fullName,
    String? countryId,
    String? dialCode,
    String? cityId,
    String? phone,
    EducationStage? stage,
    String? institutionName,
    String? universityId,
    String? degree,
    String? fieldOfStudy,
    String? classLevel,
    String? currentGrade,
    int? graduationYear,
    double? cgpa,
    int? yearOfStudy,
    int? yearsTotal,
    DateTime? expectedGraduation,
    Set<String>? favourites,
    Set<String>? hobbies,
    Set<String>? skillIds,
    String? intendedField,
    String? passion,
    String? targetRole,
    Set<String>? targetIndustry,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    bool clearCgpa = false,
    bool clearUniversity = false,
  }) => OnboardingDraft(
    step: step ?? this.step,
    fullName: fullName ?? this.fullName,
    countryId: countryId ?? this.countryId,
    dialCode: dialCode ?? this.dialCode,
    cityId: cityId ?? this.cityId,
    phone: phone ?? this.phone,
    stage: stage ?? this.stage,
    institutionName: institutionName ?? this.institutionName,
    universityId: clearUniversity ? null : (universityId ?? this.universityId),
    degree: degree ?? this.degree,
    fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
    classLevel: classLevel ?? this.classLevel,
    currentGrade: currentGrade ?? this.currentGrade,
    graduationYear: graduationYear ?? this.graduationYear,
    cgpa: clearCgpa ? null : (cgpa ?? this.cgpa),
    yearOfStudy: yearOfStudy ?? this.yearOfStudy,
    yearsTotal: yearsTotal ?? this.yearsTotal,
    expectedGraduation: expectedGraduation ?? this.expectedGraduation,
    favourites: favourites ?? this.favourites,
    hobbies: hobbies ?? this.hobbies,
    skillIds: skillIds ?? this.skillIds,
    intendedField: intendedField ?? this.intendedField,
    passion: passion ?? this.passion,
    targetRole: targetRole ?? this.targetRole,
    targetIndustry: targetIndustry ?? this.targetIndustry,
    busy: busy ?? this.busy,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

class OnboardingController extends AsyncNotifier<OnboardingDraft> {
  @override
  Future<OnboardingDraft> build() async {
    final profile = await ref.watch(profileProvider.future);
    if (profile == null) return const OnboardingDraft();

    final repo = ref.read(onboardingRepositoryProvider);
    final education = await repo.savedEducation();
    final skills = await repo.savedSkillIds();
    final interests = await repo.savedInterests();

    final stage =
        profile.stage ??
        EducationStage.fromWire(education?['stage'] as String?);

    final index = profile.onboardingStep.clamp(
      0,
      OnboardingStep.values.length - 1,
    );

    return OnboardingDraft(
      step: OnboardingStep.values[index],
      fullName: profile.fullName ?? '',
      countryId: profile.countryId,
      dialCode: profile.dialCode,
      cityId: profile.cityId,
      phone: _localPhone(profile.phone, profile.dialCode),
      stage: stage,
      institutionName:
          (education?['institution_name'] as String?) ??
          (education?['university_name'] as String?) ??
          '',
      universityId: education?['university_id'] as String?,
      degree: (education?['degree'] as String?) ?? '',
      fieldOfStudy: (education?['field_of_study'] as String?) ?? '',
      classLevel: education?['class_level'] as String?,
      currentGrade: (education?['current_grade'] as String?) ?? '',
      graduationYear: education?['graduation_year'] as int?,
      cgpa: (education?['cgpa'] as num?)?.toDouble(),
      yearOfStudy: profile.yearOfStudy,
      yearsTotal: profile.yearsTotal ?? 4,
      expectedGraduation: profile.expectedGraduation,
      favourites: {
        for (final i in interests)
          if (i.kind == InterestKind.favouriteSubject ||
              i.kind == InterestKind.favouriteCourse)
            i.label,
      },
      hobbies: {
        for (final i in interests)
          if (i.kind == InterestKind.hobby || i.kind == InterestKind.interest)
            i.label,
      },
      skillIds: skills,
      intendedField: profile.intendedField,
      passion: profile.passion ?? '',
      targetRole: profile.targetRole,
      targetIndustry: profile.targetIndustry.toSet(),
    );
  }

  /// The stored number includes the dial code; the field shows the rest.
  static String _localPhone(String? stored, String dialCode) {
    if (stored == null) return '';
    return stored.startsWith(dialCode)
        ? stored.substring(dialCode.length)
        : stored;
  }

  OnboardingDraft get _draft => state.value ?? const OnboardingDraft();

  void patch(OnboardingDraft Function(OnboardingDraft draft) update) {
    state = AsyncData(update(_draft).copyWith(clearFailure: true));
  }

  void back() {
    final d = _draft;
    final previous = d.path.before(d.step);
    if (previous == null) return;
    state = AsyncData(d.copyWith(step: previous, clearFailure: true));
  }

  /// Saves the current step and advances. Returns true once onboarding is
  /// finished, so the caller can move on.
  Future<bool> saveAndContinue() async {
    final d = _draft;
    if (!d.canContinue || d.busy) return false;

    // A primary student never gets past the stage step; the screen shows them
    // why instead of a Continue button that goes nowhere.
    if (d.step == OnboardingStep.stage && !(d.stage?.isSupported ?? false)) {
      return false;
    }

    state = AsyncData(d.copyWith(busy: true, clearFailure: true));
    final repo = ref.read(onboardingRepositoryProvider);
    final next = d.path.after(d.step);
    final nextIndex = next == null ? d.path.length : d.path.numberOf(next) - 1;

    try {
      switch (d.step) {
        case OnboardingStep.basics:
          await repo.saveStep(nextIndex, {
            'full_name': d.fullName.trim(),
            'country_id': d.countryId,
            'city_id': d.cityId,
            'phone': d.phone.trim().isEmpty
                ? null
                : '${d.dialCode}${d.phone.replaceAll(RegExp(r'\D'), '')}',
          });

        case OnboardingStep.stage:
          await repo.saveStep(nextIndex, {
            'education_stage': d.stage!.wire,
            // Only a bachelor's has a year; clear it otherwise so a student
            // who changes their answer does not keep a stale one.
            if (d.stage != EducationStage.bachelors) 'year_of_study': null,
            if (d.stage != EducationStage.bachelors) 'years_total': null,
          });

        case OnboardingStep.study:
          await repo.saveEducation(
            step: nextIndex,
            stage: d.stage!,
            universityId: d.universityId,
            institutionName: d.institutionName.trim().isEmpty
                ? null
                : d.institutionName.trim(),
            degree: d.degree.trim().isEmpty ? null : d.degree.trim(),
            fieldOfStudy: d.fieldOfStudy.trim().isEmpty
                ? null
                : d.fieldOfStudy.trim(),
            classLevel: d.classLevel,
            currentGrade: d.currentGrade.trim().isEmpty
                ? null
                : d.currentGrade.trim(),
            graduationYear: d.graduationYear,
            cgpa: d.cgpa,
            cgpaScale: d.isAtSchool ? 5.0 : 4.0,
          );
          if (d.stage == EducationStage.bachelors) {
            await repo.saveStep(nextIndex, {
              'year_of_study': d.yearOfStudy,
              'years_total': d.yearsTotal,
              'expected_graduation': d.expectedGraduation
                  ?.toIso8601String()
                  .substring(0, 10),
            });
          }

        case OnboardingStep.interests:
          await repo.saveInterests(
            kinds: {
              InterestKind.favouriteSubject,
              InterestKind.favouriteCourse,
              InterestKind.hobby,
              InterestKind.interest,
            },
            entries: [
              for (final label in d.favourites)
                (
                  kind: d.isAtSchool
                      ? InterestKind.favouriteSubject
                      : InterestKind.favouriteCourse,
                  label: label,
                ),
              for (final label in d.hobbies)
                (kind: InterestKind.hobby, label: label),
            ],
          );
          await repo.saveSkills(step: nextIndex, skillIds: d.skillIds);

        case OnboardingStep.direction:
          await repo.complete(
            targetRole: d.isAtSchool ? null : d.targetRole,
            targetIndustry: d.targetIndustry.toList(),
            intendedField: d.isAtSchool ? d.intendedField : null,
            passion: d.passion.trim().isEmpty ? null : d.passion.trim(),
          );
          ref.invalidate(profileProvider);
          state = AsyncData(d.copyWith(busy: false));
          return true;
      }
    } catch (e) {
      state = AsyncData(d.copyWith(busy: false, failure: Failure.from(e)));
      return false;
    }

    ref.invalidate(profileProvider);
    state = AsyncData(
      d.copyWith(busy: false, step: next ?? d.step, clearFailure: true),
    );
    return false;
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );
