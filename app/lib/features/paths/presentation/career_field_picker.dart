import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tack/design/tack.dart';
import '../../../core/failure.dart';
import '../application/catalog.dart';

/// The same reference catalogue powers exploration and Radar role searches.
class CareerFieldPicker extends ConsumerWidget {
  const CareerFieldPicker({super.key, required this.onPick});
  final ValueChanged<CareerPath> onPick;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    try {
      final paths = await ref.read(careerPathsProvider.future);
      if (!context.mounted) return;
      final fields = catalogFields(paths);
      final field = await showSearchPicker<String>(
        context: context,
        title: 'Choose a field',
        searchHint: 'Search study fields',
        load: () async => [
          const PickerOption(
            value: '',
            label: 'Not sure yet — browse every field',
          ),
          for (final f in fields)
            PickerOption(
              value: f.slug,
              label: f.name,
              trailing: '${f.count} paths',
            ),
        ],
      );
      if (field == null || !context.mounted) return;
      final options = filterCatalog(paths, field: field);
      final path = await showSearchPicker<CareerPath>(
        context: context,
        title: 'Choose a career path',
        searchHint: 'Search roles',
        load: () async => [
          for (final path in options)
            PickerOption(
              value: path,
              label: path.title,
              trailing: field.isEmpty ? path.fieldName : null,
            ),
        ],
      );
      if (path != null) onPick(path);
    } catch (error) {
      if (context.mounted) {
        TackToast.show(
          context,
          message: Failure.from(error).message,
          kind: TackToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => TackButton.secondary(
    'Browse fields and career paths',
    onPressed: () => _choose(context, ref),
  );
}
