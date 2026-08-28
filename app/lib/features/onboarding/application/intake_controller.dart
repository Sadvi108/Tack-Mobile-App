import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../profile/data/education_stage.dart';
import '../../profile/data/profile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/draft_repository.dart';
import '../domain/derive_mode.dart';
import '../domain/flow_config.dart';

/// What the intake screen is showing.
class IntakeState {
  const IntakeState({
    required this.stepId,
    required this.answers,
    this.branch,
    this.busy = false,
    this.failure,
    this.finishedScore,
  });

  final String stepId;
  final OnboardingBranch? branch;
  final Map<String, dynamic> answers;
  final bool busy;
  final Failure? failure;

  /// Set once onboarding is finished, so the screen can reveal it.
  final int? finishedScore;

  static const loading = IntakeState(stepId: 'basics', answers: {});

  StepSpec get step => OnboardingFlow.byId(stepId) ?? OnboardingFlow.basics;
  int get position => OnboardingFlow.positionOf(stepId, branch);
  int get length => OnboardingFlow.lengthOf(branch);

  EducationStage? get stage =>
      EducationStage.fromWire(answers['stage'] as String?);

  /// The mode this student will land in, previewed from what they have said.
  YearMode get previewMode => deriveMode(
    stage: stage,
    yearOfStudy: _int('year_of_study'),
    yearsTotal: _int('years_total'),
    graduationYear: _int('graduation_year'),
    graduationMonth: _int('graduation_month'),
  );

  /// Whether this student is too young for Tack to hold data on at all.
  ///
  /// The age band is asked for directly, so it answers this on its own; a
  /// birth year is accepted as a fallback for anyone who gave one.
  bool get tooYoung =>
      AgeBand.fromWire(answers['age_band'] as String?)?.isUnderThirteen ??
      isUnderThirteen(birthYear: _int('birth_year'));

  int? _int(String key) {
    final raw = answers[key];
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw);
    if (raw is num) return raw.toInt();
    return null;
  }

  /// Whether the current step has enough to move on.
  ///
  /// Read from the config rather than written per screen, so adding a required
  /// field is one property rather than an edit in two places.
  bool get canContinue {
    for (final field in step.fields) {
      if (!field.required) continue;
      final value = answers[field.key];
      if (value == null) return false;
      if (value is String && value.trim().isEmpty) return false;
      if (value is List && value.length < (field.minSelected).clamp(1, 99)) {
        return false;
      }
    }
    return true;
  }

  IntakeState copyWith({
    String? stepId,
    OnboardingBranch? branch,
    Map<String, dynamic>? answers,
    bool? busy,
    Failure? failure,
    int? finishedScore,
    bool clearFailure = false,
  }) => IntakeState(
    stepId: stepId ?? this.stepId,
    branch: branch ?? this.branch,
    answers: answers ?? this.answers,
    busy: busy ?? this.busy,
    failure: clearFailure ? null : (failure ?? this.failure),
    finishedScore: finishedScore ?? this.finishedScore,
  );
}

class IntakeController extends AsyncNotifier<IntakeState> {
  @override
  Future<IntakeState> build() async {
    if (!ref.watch(isSignedInProvider)) return IntakeState.loading;

    final draft = await ref.watch(onboardingDraftProvider.future);
    final state = IntakeState(
      stepId: draft.currentStep,
      branch: draft.branch,
      answers: draft.answers,
    );

    unawaitedTrack('onboarding_resumed', {
      'step': draft.currentStep,
      if (draft.branch != null) 'branch': draft.branch!.wire,
    });

    return state;
  }

  void unawaitedTrack(String event, Map<String, Object?> properties) {
    ref
        .read(analyticsProvider)
        .track(
          event,
          properties: {
            for (final entry in properties.entries)
              if (entry.value != null) entry.key: entry.value!,
          },
        )
        .ignore();
  }

  IntakeState get _state => state.value ?? IntakeState.loading;

  /// Records one answer locally. Saved to the draft when the step is left.
  void answer(String key, Object? value) {
    final current = _state;
    final next = {...current.answers, key: value};

    // A field that depends on another is cleared when that other changes, so
    // switching country never leaves a city from the previous one behind.
    for (final step in [
      OnboardingFlow.basics,
      ...OnboardingFlow.highSchoolSteps,
      ...OnboardingFlow.bachelorsSteps,
      ...OnboardingFlow.graduatedSteps,
    ]) {
      for (final field in step.fields) {
        if (field.dependsOn == key && next[field.key] != null) {
          next.remove(field.key);
        }
      }
    }

    // Picking a stage picks a branch, and changing it invalidates the answers
    // that belonged to the old one.
    if (key == 'stage') {
      final branch = OnboardingBranch.forStage(
        EducationStage.fromWire(value as String?),
      );
      state = AsyncData(
        current.copyWith(answers: next, branch: branch, clearFailure: true),
      );
      unawaitedTrack('onboarding_branch_chosen', {'branch': branch?.wire});
      return;
    }

    state = AsyncData(current.copyWith(answers: next, clearFailure: true));
  }

  Future<void> back() async {
    final current = _state;
    final previous = OnboardingFlow.previous(current.stepId, current.branch);
    if (previous == null) return;
    state = AsyncData(
      current.copyWith(stepId: previous.id, clearFailure: true),
    );
  }

  /// Jumps to a step, used by the review screen's edit links.
  void goTo(String stepId) {
    state = AsyncData(_state.copyWith(stepId: stepId, clearFailure: true));
  }

  /// Saves this step and moves on. Returns true when onboarding is finished.
  Future<bool> saveAndContinue() async {
    final current = _state;
    if (!current.canContinue || current.busy) return false;

    // Nobody under thirteen gets a profile, so the flow stops here rather
    // than at submit.
    if (current.stepId == 'basics' && current.tooYoung) return false;
    if (current.stepId == 'stage' && current.stage == EducationStage.primary) {
      return false;
    }

    state = AsyncData(current.copyWith(busy: true, clearFailure: true));
    final repository = ref.read(draftRepositoryProvider);

    try {
      if (current.stepId == 'review') {
        final score = await repository.submit(current.answers);
        ref
          ..invalidate(profileProvider)
          ..invalidate(onboardingDraftProvider);
        unawaitedTrack('onboarding_completed', {
          'branch': current.branch?.wire,
          'mode': current.previewMode.name,
        });
        state = AsyncData(current.copyWith(busy: false, finishedScore: score));
        return true;
      }

      final next = OnboardingFlow.next(current.stepId, current.branch);
      await repository.saveStep(
        stepId: current.stepId,
        answers: current.answers,
        nextStepId: next?.id ?? current.stepId,
        branch: current.branch,
      );

      unawaitedTrack('onboarding_step_completed', {
        'step': current.stepId,
        'branch': current.branch?.wire,
      });

      state = AsyncData(
        current.copyWith(
          busy: false,
          stepId: next?.id ?? current.stepId,
          clearFailure: true,
        ),
      );
      return false;
    } catch (e) {
      // A failed save must never lose what was typed: the answers stay in
      // state and the student can retry.
      state = AsyncData(
        current.copyWith(busy: false, failure: Failure.from(e)),
      );
      return false;
    }
  }

  /// The primary-school exit. No account, no profile — an email and nothing
  /// else.
  Future<bool> joinWaitlist(String email) async {
    final current = _state;
    state = AsyncData(current.copyWith(busy: true, clearFailure: true));
    try {
      await ref
          .read(draftRepositoryProvider)
          .joinWaitlist(
            email: email,
            countryId: current.answers['country_id'] as String?,
          );
      unawaitedTrack('waitlist_joined', {'reason': 'too_young'});
      state = AsyncData(current.copyWith(busy: false));
      return true;
    } catch (e) {
      state = AsyncData(
        current.copyWith(busy: false, failure: Failure.from(e)),
      );
      return false;
    }
  }
}

final intakeControllerProvider =
    AsyncNotifierProvider<IntakeController, IntakeState>(IntakeController.new);
