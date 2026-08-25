import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/failure.dart';
import '../../../core/supabase/client.dart';

class City {
  const City({required this.id, required this.name});
  final String id;
  final String name;
}

class University {
  const University({required this.id, required this.name, this.shortName});
  final String id;
  final String name;
  final String? shortName;

  String get display =>
      shortName == null || shortName!.isEmpty ? name : '$name ($shortName)';
}

class Skill {
  const Skill({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
  });
  final String id;
  final String slug;
  final String name;
  final String category;
}

/// Reference data shared by every student: cities, universities and the skill
/// vocabulary. Readable by any signed-in user, writable by none.
class ReferenceRepository {
  const ReferenceRepository(this._db);

  final SupabaseClient _db;

  Future<List<City>> cities() async {
    try {
      final rows = await _db
          .from('cities')
          .select('id, name')
          .order('sort_order');
      return rows
          .map((r) => City(id: r['id'] as String, name: r['name'] as String))
          .toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<University>> universities() async {
    try {
      final rows = await _db
          .from('universities')
          .select('id, name, short_name')
          .eq('is_active', true)
          .order('name');
      return rows
          .map(
            (r) => University(
              id: r['id'] as String,
              name: r['name'] as String,
              shortName: r['short_name'] as String?,
            ),
          )
          .toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  /// The starter grid on the skills step. Deliberately small — a wall of 440
  /// chips is not a 30-second question.
  Future<List<Skill>> popularSkills({int limit = 40}) async {
    try {
      final rows = await _db
          .from('skills')
          .select('id, slug, name, category')
          .eq('is_active', true)
          .inFilter('category', [
            'soft',
            'tools',
            'programming',
            'business',
            'marketing',
            'design',
          ])
          .order('name')
          .limit(limit);
      return rows.map(_skill).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  Future<List<Skill>> searchSkills(String query, {int limit = 30}) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final rows = await _db
          .from('skills')
          .select('id, slug, name, category')
          .eq('is_active', true)
          .ilike('name', '%$q%')
          .order('name')
          .limit(limit);
      return rows.map(_skill).toList();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  static Skill _skill(Map<String, dynamic> r) => Skill(
    id: r['id'] as String,
    slug: r['slug'] as String,
    name: r['name'] as String,
    category: r['category'] as String,
  );
}

final referenceRepositoryProvider = Provider<ReferenceRepository>(
  (ref) => ReferenceRepository(ref.watch(supabaseProvider)),
);

final citiesProvider = FutureProvider<List<City>>(
  (ref) => ref.watch(referenceRepositoryProvider).cities(),
);

final universitiesProvider = FutureProvider<List<University>>(
  (ref) => ref.watch(referenceRepositoryProvider).universities(),
);

final popularSkillsProvider = FutureProvider<List<Skill>>(
  (ref) => ref.watch(referenceRepositoryProvider).popularSkills(),
);

final skillSearchProvider = FutureProvider.family<List<Skill>, String>(
  (ref, query) => ref.watch(referenceRepositoryProvider).searchSkills(query),
);
