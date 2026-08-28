/// The onboarding flow, as data.
///
/// Steps, branches, fields, validation and order all live here. The renderer
/// walks this config; no screen knows what comes next and no component
/// contains `if (stage == highSchool)`.
///
/// This flow will change a dozen times. With the sequence hardcoded across
/// components, every change is a refactor; here, adding a question is one
/// object in a list.
library;

import '../../profile/data/education_stage.dart';

enum FieldType {
  text,
  select,
  searchableSelect,
  multiChip,
  radioCards,
  repeatableRows,
  textArea,
  dateParts,
  rankPicker,
  number,
}

/// Where a field's options come from. Reference lists are loaded on demand
/// rather than shipped with the app — 197 countries and 440 skills have no
/// business in the bundle.
enum OptionSource {
  none,
  countries,
  cities,
  universities,
  subjects,
  interests,
  skills,
  careerFields,
  curriculums,
  classLevels,
  careerValues,
  activityCategories,
  targetRoles,
  targetIndustries,
  currentStatus,
  ageBands,

  /// Year 1 to 8 of a degree.
  studyYears,

  /// How many years the whole programme runs.
  programmeLengths,

  /// The next several years, for when a course finishes.
  finishYears,
}

class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.type,
    required this.label,
    this.hint,
    this.help,
    this.required = false,
    this.options = OptionSource.none,
    this.maxLength,
    this.maxRows,
    this.minSelected = 0,
    this.dependsOn,
    this.rowFields = const [],
    this.notSureOption,
  });

  final String key;
  final FieldType type;
  final String label;
  final String? hint;

  /// Shown under the field. Where an answer is never displayed to anyone else,
  /// this is where that promise is made.
  final String? help;

  final bool required;
  final OptionSource options;
  final int? maxLength;
  final int? maxRows;
  final int minSelected;

  /// Clearing this field's value when the named field changes, so a student
  /// who switches country is not left with a city from the previous one.
  final String? dependsOn;

  /// For repeatable rows: the fields inside one row.
  final List<FieldSpec> rowFields;

  /// The label for a prominent "not sure yet" answer.
  ///
  /// Wherever direction is asked, not knowing is the honest state for most
  /// people and the app rewards it rather than treating it as a blank.
  final String? notSureOption;

  bool get isDirectionQuestion => notSureOption != null;
}

class StepSpec {
  const StepSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fields,
    this.branch,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<FieldSpec> fields;

  /// Null for steps every student sees.
  final OnboardingBranch? branch;
}

enum OnboardingBranch {
  primary,
  highSchool,
  bachelors,
  graduated;

  static OnboardingBranch? forStage(EducationStage? stage) => switch (stage) {
    EducationStage.primary => OnboardingBranch.primary,
    EducationStage.highSchool => OnboardingBranch.highSchool,
    EducationStage.bachelors => OnboardingBranch.bachelors,
    EducationStage.graduated => OnboardingBranch.graduated,
    null => null,
  };

  String get wire => switch (this) {
    OnboardingBranch.primary => 'primary',
    OnboardingBranch.highSchool => 'high_school',
    OnboardingBranch.bachelors => 'bachelors',
    OnboardingBranch.graduated => 'graduated',
  };
}

/// The whole flow.
class OnboardingFlow {
  const OnboardingFlow._();

  static const basics = StepSpec(
    id: 'basics',
    title: 'About you',
    subtitle: 'So the app can address you properly.',
    fields: [
      FieldSpec(
        key: 'full_name',
        type: FieldType.text,
        label: 'Your name',
        hint: 'As it should appear on your CV',
        required: true,
      ),
      FieldSpec(
        key: 'country_id',
        type: FieldType.searchableSelect,
        label: 'Country',
        hint: 'Where you live',
        required: true,
        options: OptionSource.countries,
      ),
      FieldSpec(
        key: 'city_id',
        type: FieldType.searchableSelect,
        label: 'City',
        hint: 'Where you live',
        required: true,
        options: OptionSource.cities,
        // Switching country must not leave a city from the old one behind.
        dependsOn: 'country_id',
      ),
      FieldSpec(
        key: 'phone',
        type: FieldType.text,
        label: 'Phone number',
        hint: '712345678',
        help: 'Optional. We only use this if an employer needs to reach you.',
        dependsOn: 'country_id',
      ),
      FieldSpec(
        key: 'age_band',
        type: FieldType.select,
        label: 'How old are you?',
        hint: 'Choose a range',
        required: true,
        options: OptionSource.ageBands,
        help: 'We ask because Tack is not built for under-13s yet.',
      ),
    ],
  );

  static const stage = StepSpec(
    id: 'stage',
    title: 'Where are you now?',
    subtitle:
        'This decides everything the app shows you. You can change it later.',
    fields: [
      FieldSpec(
        key: 'stage',
        type: FieldType.radioCards,
        label: 'Where are you in your education?',
        required: true,
      ),
    ],
  );

  // ------------------------------------------------------------ high school
  static const hsSchool = StepSpec(
    id: 'hs_school',
    branch: OnboardingBranch.highSchool,
    title: 'Your school',
    subtitle:
        'Your results are never shown to anyone. They only feed your own score.',
    fields: [
      FieldSpec(
        key: 'institution_name',
        type: FieldType.text,
        label: 'School or college',
        hint: 'Where you study now',
        required: true,
      ),
      FieldSpec(
        key: 'current_class',
        type: FieldType.select,
        label: 'Which class',
        hint: 'Choose your class',
        required: true,
        options: OptionSource.classLevels,
      ),
      FieldSpec(
        key: 'curriculum',
        type: FieldType.select,
        label: 'Curriculum',
        hint: 'Choose one',
        options: OptionSource.curriculums,
        dependsOn: 'country_id',
      ),
      FieldSpec(
        key: 'expected_end_year',
        type: FieldType.select,
        label: 'When do you finish?',
        hint: 'Choose a year',
        required: true,
        options: OptionSource.finishYears,
      ),
      FieldSpec(
        key: 'gpa',
        type: FieldType.number,
        label: 'Your last result',
        hint: '4.83',
        help: 'Optional, and never shown to anyone.',
      ),
    ],
  );

  static const hsEnjoy = StepSpec(
    id: 'hs_enjoy',
    branch: OnboardingBranch.highSchool,
    title: 'What you enjoy',
    subtitle: 'Subjects you like and things you do outside class. Both count.',
    fields: [
      FieldSpec(
        key: 'favourite_subjects',
        type: FieldType.multiChip,
        label: 'Subjects you like most',
        required: true,
        minSelected: 1,
        options: OptionSource.subjects,
      ),
      FieldSpec(
        key: 'hard_subjects',
        type: FieldType.multiChip,
        label: 'Subjects you find hard',
        help:
            'Optional, and useful — it is how Tack works out what to help with.',
        options: OptionSource.subjects,
      ),
      FieldSpec(
        key: 'interests',
        type: FieldType.multiChip,
        label: 'Things you do outside class',
        options: OptionSource.interests,
      ),
    ],
  );

  static const hsDirection = StepSpec(
    id: 'hs_direction',
    branch: OnboardingBranch.highSchool,
    title: 'Where you are heading',
    subtitle: 'No pressure — a rough idea is enough, and it can change.',
    fields: [
      FieldSpec(
        key: 'intended_field_slug',
        type: FieldType.multiChip,
        label: 'What would you like to study?',
        required: true,
        minSelected: 1,
        options: OptionSource.careerFields,
        notSureOption: 'Not sure yet',
      ),
      FieldSpec(
        key: 'career_values',
        type: FieldType.rankPicker,
        label: 'What matters most to you in a career?',
        help: 'Pick up to three, most important first.',
        options: OptionSource.careerValues,
      ),
      FieldSpec(
        key: 'ten_year_note',
        type: FieldType.textArea,
        label: 'What would you love to be doing in ten years?',
        hint: 'Anything at all. There is no right answer.',
        help: 'Optional.',
        maxLength: 200,
      ),
    ],
  );

  // -------------------------------------------------------------- bachelor's
  static const uniUniversity = StepSpec(
    id: 'uni_university',
    branch: OnboardingBranch.bachelors,
    title: 'Your university',
    subtitle: 'Your CGPA is optional and is never shown to anyone.',
    fields: [
      FieldSpec(
        key: 'institution_id',
        type: FieldType.searchableSelect,
        label: 'University',
        hint: 'Choose your university',
        required: true,
        options: OptionSource.universities,
        dependsOn: 'country_id',
      ),
      FieldSpec(
        key: 'degree',
        type: FieldType.text,
        label: 'Degree',
        hint: 'BSc, BBA, BA and so on',
        required: true,
      ),
      FieldSpec(
        key: 'major',
        type: FieldType.text,
        label: 'Subject or department',
        hint: 'Computer science, finance, English…',
      ),
      FieldSpec(
        key: 'year_of_study',
        type: FieldType.select,
        label: 'Which year are you in?',
        hint: 'Choose your year',
        required: true,
        options: OptionSource.studyYears,
        help: 'This is what decides everything the app shows you.',
      ),
      FieldSpec(
        key: 'years_total',
        type: FieldType.select,
        label: 'How long is your programme?',
        hint: 'Choose a length',
        required: true,
        options: OptionSource.programmeLengths,
        // Final year is relative: year 4 of 4 is launch, year 4 of 5 is not.
        // Without this the app would tell a medical student to start applying
        // a year early.
        help: 'Year 4 of a 5-year course is not the same as year 4 of 4.',
      ),
      FieldSpec(
        key: 'graduation',
        type: FieldType.dateParts,
        label: 'When do you expect to graduate?',
        required: true,
      ),
      FieldSpec(
        key: 'gpa',
        type: FieldType.number,
        label: 'CGPA',
        hint: '3.45',
        help: 'Optional, and never shown to anyone.',
      ),
    ],
  );

  static const uniCourses = StepSpec(
    id: 'uni_courses',
    branch: OnboardingBranch.bachelors,
    title: 'Your courses',
    subtitle: 'Skip anything you would rather not fill in now.',
    fields: [
      FieldSpec(
        key: 'courses',
        type: FieldType.repeatableRows,
        label: 'This semester\'s courses',
        maxRows: 8,
        rowFields: [
          FieldSpec(key: 'code', type: FieldType.text, label: 'Code'),
          FieldSpec(
            key: 'title',
            type: FieldType.text,
            label: 'Title',
            required: true,
          ),
          FieldSpec(key: 'credits', type: FieldType.number, label: 'Credits'),
        ],
      ),
      FieldSpec(
        key: 'skills',
        type: FieldType.multiChip,
        label: 'Skills you have',
        help: 'Anything you have done, even at a beginner level.',
        options: OptionSource.skills,
      ),
    ],
  );

  static const uniDirection = StepSpec(
    id: 'uni_direction',
    branch: OnboardingBranch.bachelors,
    title: 'Your direction',
    subtitle: 'A rough idea is enough. Nothing here is locked in.',
    fields: [
      FieldSpec(
        key: 'target_role',
        type: FieldType.searchableSelect,
        label: 'What kind of job are you aiming at?',
        hint: 'Choose a role',
        required: true,
        options: OptionSource.targetRoles,
        notSureOption: 'Not sure yet',
      ),
      FieldSpec(
        key: 'target_industry',
        type: FieldType.multiChip,
        label: 'Any industries you like the look of?',
        help: 'Optional.',
        options: OptionSource.targetIndustries,
      ),
      FieldSpec(
        key: 'activities',
        type: FieldType.multiChip,
        label: 'Anything outside your course?',
        options: OptionSource.activityCategories,
      ),
      FieldSpec(
        key: 'experiences',
        type: FieldType.repeatableRows,
        label: 'Any internship or work yet?',
        help: 'Optional. Leave it empty if not — most students have none yet.',
        maxRows: 4,
        rowFields: [
          FieldSpec(
            key: 'role',
            type: FieldType.text,
            label: 'What you did',
            required: true,
          ),
          FieldSpec(key: 'organisation', type: FieldType.text, label: 'Where'),
        ],
      ),
    ],
  );

  // --------------------------------------------------------------- graduated
  static const gradDegree = StepSpec(
    id: 'grad_degree',
    branch: OnboardingBranch.graduated,
    title: 'Your degree',
    subtitle: 'What you finished, and where.',
    fields: [
      FieldSpec(
        key: 'institution_id',
        type: FieldType.searchableSelect,
        label: 'Where you studied',
        hint: 'Choose your university',
        required: true,
        options: OptionSource.universities,
        dependsOn: 'country_id',
      ),
      FieldSpec(
        key: 'degree',
        type: FieldType.text,
        label: 'Degree',
        hint: 'BSc, BBA, BA and so on',
        required: true,
      ),
      FieldSpec(key: 'major', type: FieldType.text, label: 'Subject'),
      FieldSpec(
        key: 'graduation',
        type: FieldType.dateParts,
        label: 'When did you graduate?',
        required: true,
      ),
      FieldSpec(
        key: 'current_status',
        type: FieldType.select,
        label: 'What are you doing now?',
        hint: 'Choose one',
        required: true,
        options: OptionSource.currentStatus,
      ),
      FieldSpec(
        key: 'gpa',
        type: FieldType.number,
        label: 'CGPA',
        hint: '3.45',
        help: 'Optional, and never shown to anyone.',
      ),
    ],
  );

  static const gradDirection = StepSpec(
    id: 'grad_direction',
    branch: OnboardingBranch.graduated,
    title: 'Your direction',
    subtitle: 'A rough idea is enough. Nothing here is locked in.',
    fields: [
      FieldSpec(
        key: 'target_role',
        type: FieldType.searchableSelect,
        label: 'What kind of job are you aiming at?',
        hint: 'Choose a role',
        required: true,
        options: OptionSource.targetRoles,
        notSureOption: 'Not sure yet',
      ),
      FieldSpec(
        key: 'target_industry',
        type: FieldType.multiChip,
        label: 'Any industries you like the look of?',
        help: 'Optional.',
        options: OptionSource.targetIndustries,
      ),
      FieldSpec(
        key: 'skills',
        type: FieldType.multiChip,
        label: 'Skills you have',
        options: OptionSource.skills,
      ),
      FieldSpec(
        key: 'experiences',
        type: FieldType.repeatableRows,
        label: 'Experience so far',
        help: 'Internships and jobs. Optional.',
        maxRows: 6,
        rowFields: [
          FieldSpec(
            key: 'role',
            type: FieldType.text,
            label: 'What you did',
            required: true,
          ),
          FieldSpec(key: 'organisation', type: FieldType.text, label: 'Where'),
        ],
      ),
    ],
  );

  static const review = StepSpec(
    id: 'review',
    title: 'Check it over',
    subtitle: 'Change anything that is not right, then finish.',
    fields: [],
  );

  /// Everybody starts here.
  static const shared = [basics, stage];

  static const List<StepSpec> highSchoolSteps = [
    hsSchool,
    hsEnjoy,
    hsDirection,
  ];
  static const List<StepSpec> bachelorsSteps = [
    uniUniversity,
    uniCourses,
    uniDirection,
  ];
  static const List<StepSpec> graduatedSteps = [gradDegree, gradDirection];

  /// The steps a student on this branch will see, in order.
  ///
  /// Primary has no steps: it ends at the waitlist and creates no account.
  static List<StepSpec> stepsFor(OnboardingBranch? branch) => switch (branch) {
    null => shared,
    OnboardingBranch.primary => shared,
    OnboardingBranch.highSchool => [...shared, ...highSchoolSteps, review],
    OnboardingBranch.bachelors => [...shared, ...bachelorsSteps, review],
    OnboardingBranch.graduated => [...shared, ...graduatedSteps, review],
  };

  static StepSpec? byId(String id) {
    for (final step in [
      basics,
      stage,
      ...highSchoolSteps,
      ...bachelorsSteps,
      ...graduatedSteps,
      review,
    ]) {
      if (step.id == id) return step;
    }
    return null;
  }

  /// What comes after this step, or null when the flow is finished.
  static StepSpec? next(String stepId, OnboardingBranch? branch) {
    final steps = stepsFor(branch);
    final index = steps.indexWhere((s) => s.id == stepId);
    if (index < 0 || index + 1 >= steps.length) return null;
    return steps[index + 1];
  }

  static StepSpec? previous(String stepId, OnboardingBranch? branch) {
    final steps = stepsFor(branch);
    final index = steps.indexWhere((s) => s.id == stepId);
    if (index <= 0) return null;
    return steps[index - 1];
  }

  /// One-based position, for a progress bar that reflects the branch the
  /// student is actually on rather than a fixed count.
  static int positionOf(String stepId, OnboardingBranch? branch) {
    final index = stepsFor(branch).indexWhere((s) => s.id == stepId);
    return index < 0 ? 1 : index + 1;
  }

  /// How many steps the bar should show.
  ///
  /// Before a branch is chosen the real answer is unknown, and showing the two
  /// shared steps would put a student half way along the bar on question one.
  /// The longest branch is used until they pick, so the bar only ever shortens
  /// — which reads as progress rather than as the goalposts moving.
  static int lengthOf(OnboardingBranch? branch) {
    if (branch == null || branch == OnboardingBranch.primary) {
      return [
        for (final b in [
          OnboardingBranch.highSchool,
          OnboardingBranch.bachelors,
          OnboardingBranch.graduated,
        ])
          stepsFor(b).length,
      ].reduce((a, b) => a > b ? a : b);
    }
    return stepsFor(branch).length;
  }
}

/// The answers one date pick produces.
///
/// The required-field check reads [FieldSpec.key], while the submit path reads
/// the year and month separately. Both were written by hand in the widget and
/// the key was missed, which left Continue permanently disabled on any step
/// asking for a date. Returning them together makes that impossible to get
/// half right.
Map<String, Object> answersForDate({
  required String fieldKey,
  required int year,
  required int month,
  required String monthName,
}) => {
  fieldKey: '$year-$month',
  '${fieldKey}__label': '$monthName $year',
  'graduation_year': year,
  'graduation_month': month,
};
