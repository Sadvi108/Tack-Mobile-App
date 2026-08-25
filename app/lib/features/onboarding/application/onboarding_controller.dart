import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failure.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/onboarding_repository.dart';

/// Everything the wizard has collected so far, plus where the student is.
class OnboardingDraft {
  const OnboardingDraft({
    this.step = OnboardingStep.you,
    this.fullName = '',
    this.cityId,
    this.phone = '',
    this.universityId,
    this.universityName = '',
    this.degree = '',
    this.fieldOfStudy = '',
    this.graduationYear,
    this.cgpa,
    this.yearOfStudy,
    this.yearsTotal = 4,
    this.expectedGraduation,
    this.skillIds = const {},
    this.targetRole,
    this.targetIndustry = const {},
    this.busy = false,
    this.failure,
  });

  final OnboardingStep step;

  final String fullName;
  final String? cityId;
  final String phone;

  final String? universityId;
  final String universityName;
  final String degree;
  final String fieldOfStudy;
  final int? graduationYear;
  final double? cgpa;

  final int? yearOfStudy;
  final int yearsTotal;
  final DateTime? expectedGraduation;

  final Set<String> skillIds;

  final String? targetRole;
  final Set<String> targetIndustry;

  final bool busy;
  final Failure? failure;

  /// The mode this answer would produce, shown back to the student on the year
  /// step so the consequence of the answer is visible before they commit.
  YearMode get previewMode {
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
  bool get canContinue => switch (step) {
        OnboardingStep.you => fullName.trim().length >= 2 &&
            cityId != null &&
            phone.replaceAll(RegExp(r'\D'), '').length == 10,
        OnboardingStep.education =>
          (universityId != null || universityName.trim().isNotEmpty) && degree.trim().isNotEmpty,
        OnboardingStep.year => yearOfStudy != null && expectedGraduation != null,
        OnboardingStep.skills => skillIds.isNotEmpty,
        OnboardingStep.target => targetRole != null,
      };

  int get stepNumber => step.index + 1;
  int get stepCount => OnboardingStep.values.length;

  OnboardingDraft copyWith({
    OnboardingStep? step,
    String? fullName,
    String? cityId,
    String? phone,
    String? universityId,
    String? universityName,
    String? degree,
    String? fieldOfStudy,
    int? graduationYear,
    double? cgpa,
    int? yearOfStudy,
    int? yearsTotal,
    DateTime? expectedGraduation,
    Set<String>? skillIds,
    String? targetRole,
    Set<String>? targetIndustry,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
    bool clearCgpa = false,
  }) =>
      OnboardingDraft(
        step: step ?? this.step,
        fullName: fullName ?? this.fullName,
        cityId: cityId ?? this.cityId,
        phone: phone ?? this.phone,
        universityId: universityId ?? this.universityId,
        universityName: universityName ?? this.universityName,
        degree: degree ?? this.degree,
        fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
        graduationYear: graduationYear ?? this.graduationYear,
        cgpa: clearCgpa ? null : (cgpa ?? this.cgpa),
        yearOfStudy: yearOfStudy ?? this.yearOfStudy,
        yearsTotal: yearsTotal ?? this.yearsTotal,
        expectedGraduation: expectedGraduation ?? this.expectedGraduation,
        skillIds: skillIds ?? this.skillIds,
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

    final stepIndex = profile.onboardingStep.clamp(0, OnboardingStep.values.length - 1);

    return OnboardingDraft(
      step: OnboardingStep.values[stepIndex],
      fullName: profile.fullName ?? '',
      cityId: profile.cityId,
      phone: profile.phone ?? '',
      universityId: education?['university_id'] as String?,
      universityName: (education?['university_name'] as String?) ?? '',
      degree: (education?['degree'] as String?) ?? '',
      fieldOfStudy: (education?['field_of_study'] as String?) ?? '',
      graduationYear: education?['graduation_year'] as int?,
      cgpa: (education?['cgpa'] as num?)?.toDouble(),
      yearOfStudy: profile.yearOfStudy,
      yearsTotal: profile.yearsTotal ?? 4,
      expectedGraduation: profile.expectedGraduation,
      skillIds: skills,
      targetRole: profile.targetRole,
      targetIndustry: profile.targetIndustry.toSet(),
    );
  }

  OnboardingDraft get _draft => state.value ?? const OnboardingDraft();

  void patch(OnboardingDraft Function(OnboardingDraft draft) update) {
    state = AsyncData(update(_draft).copyWith(clearFailure: true));
  }

  void back() {
    final d = _draft;
    if (d.step.index == 0) return;
    state = AsyncData(d.copyWith(step: OnboardingStep.values[d.step.index - 1], clearFailure: true));
  }

  /// Saves the current step, then advances. Returns true once the last step is
  /// saved, so the caller can move on to the score reveal.
  Future<bool> saveAndContinue() async {
    final d = _draft;
    if (!d.canContinue || d.busy) return false;

    state = AsyncData(d.copyWith(busy: true, clearFailure: true));
    final repo = ref.read(onboardingRepositoryProvider);
    final nextIndex = d.step.index + 1;

    try {
      switch (d.step) {
        case OnboardingStep.you:
          await repo.saveStep(nextIndex, {
            'full_name': d.fullName.trim(),
            'city_id': d.cityId,
            'phone': '+880${d.phone.replaceAll(RegExp(r'\D'), '')}',
          });
        case OnboardingStep.education:
          await repo.saveEducation(
            step: nextIndex,
            universityId: d.universityId,
            universityName: d.universityId == null ? d.universityName.trim() : null,
            degree: d.degree.trim(),
            fieldOfStudy: d.fieldOfStudy.trim().isEmpty ? null : d.fieldOfStudy.trim(),
            graduationYear: d.graduationYear,
            cgpa: d.cgpa,
          );
        case OnboardingStep.year:
          await repo.saveStep(nextIndex, {
            'year_of_study': d.yearOfStudy,
            'years_total': d.yearsTotal,
            'expected_graduation':
                d.expectedGraduation!.toIso8601String().substring(0, 10),
          });
        case OnboardingStep.skills:
          await repo.saveSkills(step: nextIndex, skillIds: d.skillIds);
        case OnboardingStep.target:
          await repo.complete(
            targetRole: d.targetRole!,
            targetIndustry: d.targetIndustry.toList(),
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
    state = AsyncData(d.copyWith(
      busy: false,
      step: OnboardingStep.values[nextIndex],
      clearFailure: true,
    ));
    return false;
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, OnboardingDraft>(OnboardingController.new);
