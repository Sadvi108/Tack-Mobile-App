import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';
import '../../../design/tack.dart';
import '../domain/flow_config.dart';

/// Loads the options behind a field, when the field is opened.
///
/// 197 countries, 131 subjects and 440 skills have no business in the app
/// bundle or in memory before somebody taps the field that needs them.
class OptionRepository {
  const OptionRepository(this._db);

  final SupabaseClient _db;

  Future<List<PickerOption<String>>> load(
    OptionSource source, {
    String? countryId,
  }) async {
    try {
      return switch (source) {
        OptionSource.countries => await _countries(),
        OptionSource.cities => await _cities(countryId),
        OptionSource.universities => await _universities(countryId),
        OptionSource.subjects => await _reference('subjects'),
        OptionSource.interests => await _reference('interests'),
        OptionSource.skills => await _skills(),
        OptionSource.careerFields => await _careerFields(),
        OptionSource.curriculums => _static(_curriculums),
        OptionSource.classLevels => _static(_classLevels),
        OptionSource.careerValues => _static(_careerValues),
        OptionSource.activityCategories => _static(_activityCategories),
        OptionSource.targetRoles => _static(_targetRoles),
        OptionSource.targetIndustries => _static(_targetIndustries),
        OptionSource.currentStatus => _static(_currentStatus),
        OptionSource.ageBands => _static(_ageBands),
        OptionSource.studyYears => _studyYears(),
        OptionSource.programmeLengths => _programmeLengths(),
        OptionSource.finishYears => _finishYears(),
        OptionSource.none => const <PickerOption<String>>[],
      };
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<PickerOption<String>>> _countries() async {
    final rows = await _db
        .from('countries')
        .select('id, name, dial_code')
        .order('sort_order')
        .order('name');
    return rows
        .map(
          (r) => PickerOption(
            value: r['id'] as String,
            label: r['name'] as String,
            trailing: r['dial_code'] as String?,
          ),
        )
        .toList();
  }

  Future<List<PickerOption<String>>> _cities(String? countryId) async {
    if (countryId == null) return const [];
    final rows = await _db
        .from('cities')
        .select('id, name')
        .eq('country_id', countryId)
        .order('sort_order');
    return rows
        .map(
          (r) => PickerOption(
            value: r['id'] as String,
            label: r['name'] as String,
          ),
        )
        .toList();
  }

  Future<List<PickerOption<String>>> _universities(String? countryId) async {
    // Universities are seeded for Bangladesh. Elsewhere the student types
    // their own rather than scrolling a list that does not contain it.
    final rows = await _db
        .from('universities')
        .select('id, name, short_name')
        .eq('is_active', true)
        .order('name');
    return rows
        .map(
          (r) => PickerOption(
            value: r['id'] as String,
            label: r['name'] as String,
            trailing: r['short_name'] as String?,
          ),
        )
        .toList();
  }

  Future<List<PickerOption<String>>> _reference(String table) async {
    final rows = await _db
        .from(table)
        .select('slug, name')
        .eq('is_active', true)
        .order('category')
        .order('sort_order');
    return rows
        .map(
          (r) => PickerOption(
            value: r['slug'] as String,
            label: r['name'] as String,
          ),
        )
        .toList();
  }

  Future<List<PickerOption<String>>> _skills() async {
    final rows = await _db
        .from('skills')
        .select('id, name')
        .eq('is_active', true)
        .order('category')
        .order('name');
    return rows
        .map(
          (r) => PickerOption(
            value: r['id'] as String,
            label: r['name'] as String,
          ),
        )
        .toList();
  }

  Future<List<PickerOption<String>>> _careerFields() async {
    final rows = await _db
        .from('career_fields')
        .select('slug, name')
        .eq('is_active', true)
        .order('sort_order');
    return [
      for (final r in rows)
        PickerOption(
          value: r['slug'] as String,
          label: r['name'] as String,
          // Not knowing is the honest answer for most sixteen-year-olds, so it
          // sits at the top and is styled as a real choice.
          highlighted: r['slug'] == 'undecided',
        ),
    ];
  }

  /// Years of a degree. The last year of the programme is what decides
  /// whether a student is in launch mode, so the labels say which is which
  /// rather than leaving them to count.
  static List<PickerOption<String>> _studyYears() => [
    for (var y = 1; y <= 8; y++) PickerOption(value: '$y', label: 'Year $y'),
  ];

  static List<PickerOption<String>> _programmeLengths() => [
    for (var y = 2; y <= 8; y++) PickerOption(value: '$y', label: '$y years'),
  ];

  static List<PickerOption<String>> _finishYears() {
    final thisYear = DateTime.now().year;
    return [
      for (var y = thisYear; y <= thisYear + 8; y++)
        PickerOption(value: '$y', label: '$y'),
    ];
  }

  static List<PickerOption<String>> _static(List<(String, String)> pairs) => [
    for (final (value, label) in pairs)
      PickerOption(value: value, label: label),
  ];

  static const _curriculums = [
    ('national', 'National curriculum'),
    ('english_medium', 'English medium'),
    ('o_a_level', 'O and A levels'),
    ('ib', 'International Baccalaureate'),
    ('madrasah', 'Madrasah'),
    ('other', 'Something else'),
  ];

  static const _classLevels = [
    ('class_9', 'Class 9'),
    ('class_10', 'Class 10 (SSC)'),
    ('class_11', 'Class 11 (HSC first year)'),
    ('class_12', 'Class 12 (HSC second year)'),
    ('o_level', 'O levels'),
    ('as_level', 'AS levels'),
    ('a_level', 'A levels'),
    ('diploma', 'Diploma'),
  ];

  static const _careerValues = [
    ('money', 'Earning well'),
    ('stability', 'Job security'),
    ('creativity', 'Being creative'),
    ('helping', 'Helping people'),
    ('independence', 'Working independently'),
    ('recognition', 'Being recognised'),
    ('learning', 'Always learning'),
    ('balance', 'Time for life outside work'),
  ];

  static const _activityCategories = [
    ('club', 'A club or society'),
    ('volunteering', 'Volunteering'),
    ('competition', 'Competitions'),
    ('leadership', 'A leadership role'),
    ('sports', 'Sports'),
    ('research', 'Research'),
    ('none', 'Nothing yet'),
  ];

  static const _targetRoles = [
    ('Frontend developer', 'Frontend developer'),
    ('Backend developer', 'Backend developer'),
    ('Data analyst', 'Data analyst'),
    ('Digital marketer', 'Digital marketer'),
    ('HR executive', 'HR executive'),
    ('Business analyst', 'Business analyst'),
    ('Graphic designer', 'Graphic designer'),
    ('QA engineer', 'QA engineer'),
    ('Accountant', 'Accountant'),
    ('Content writer', 'Content writer'),
  ];

  static const _targetIndustries = [
    ('Software and IT', 'Software and IT'),
    ('Banking and finance', 'Banking and finance'),
    ('Telecom', 'Telecom'),
    ('E-commerce', 'E-commerce'),
    ('RMG and textiles', 'RMG and textiles'),
    ('FMCG', 'FMCG'),
    ('Pharmaceuticals', 'Pharmaceuticals'),
    ('Education', 'Education'),
    ('Development and NGO', 'Development and NGO'),
    ('Media and advertising', 'Media and advertising'),
    ('Startups', 'Startups'),
    ('Government', 'Government'),
  ];

  static const _currentStatus = [
    ('job_hunting', 'Looking for a job'),
    ('employed', 'Working'),
    ('freelancing', 'Freelancing'),
    ('studying_further', 'Studying further'),
  ];

  static const _ageBands = [
    ('under_13', 'Under 13'),
    ('13_15', '13 to 15'),
    ('16_18', '16 to 18'),
    ('19_22', '19 to 22'),
    ('23_26', '23 to 26'),
    ('27_plus', '27 or older'),
  ];
}

final optionRepositoryProvider = Provider<OptionRepository>(
  (ref) => OptionRepository(ref.watch(supabaseProvider)),
);

/// The "not sure yet" option, added to any field that declares one.
PickerOption<String> notSureOption(String label) =>
    PickerOption(value: 'undecided', label: label, highlighted: true);
