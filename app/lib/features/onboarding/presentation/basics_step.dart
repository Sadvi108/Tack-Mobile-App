import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tack.dart';
import '../../profile/data/education_stage.dart';
import '../application/onboarding_controller.dart';
import '../data/reference_repository.dart';
import 'picker_sheet.dart';

/// Who you are and where you live.
///
/// Country comes before city, and the phone prefix follows from it. The form
/// used to hard-code +880, which quietly told anyone outside Bangladesh that
/// the app was not for them.
class BasicsStep extends ConsumerStatefulWidget {
  const BasicsStep({super.key, required this.draft});

  final OnboardingDraft draft;

  @override
  ConsumerState<BasicsStep> createState() => _BasicsStepState();
}

class _BasicsStepState extends ConsumerState<BasicsStep> {
  late final _name = TextEditingController(text: widget.draft.fullName);
  late final _phone = TextEditingController(text: widget.draft.phone);
  late final _city = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final controller = ref.read(onboardingControllerProvider.notifier);
    final countries = ref.watch(countriesProvider);
    final cities = ref.watch(citiesProvider(draft.countryId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TackTextField(
          label: 'Your name',
          hint: 'As it should appear on your CV',
          controller: _name,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          onChanged: (v) => controller.patch((d) => d.copyWith(fullName: v)),
        ),
        const SizedBox(height: TackSpace.stack),

        countries.when(
          loading: () => const TackSkeleton(height: 52, radius: 12),
          error: (_, _) => Text(
            'The country list did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (list) => TackSelectField<Country>(
            label: 'Country',
            hint: 'Where you live',
            value: list.where((c) => c.id == draft.countryId).firstOrNull,
            valueLabel: (c) => c.name,
            onTap: () async {
              final picked = await showPickerSheet<Country>(
                context: context,
                title: 'Your country',
                options: list,
                labelOf: (c) => '${c.name}  ${c.dialCode}',
                selected: list
                    .where((c) => c.id == draft.countryId)
                    .firstOrNull,
                searchHint: 'Search countries',
              );
              if (picked == null) return;
              // Changing country clears the city: the old one belongs to a
              // list that is no longer on screen.
              _city.clear();
              controller.patch(
                (d) => OnboardingDraft(
                  step: d.step,
                  fullName: d.fullName,
                  countryId: picked.id,
                  dialCode: picked.dialCode,
                  cityId: null,
                  phone: d.phone,
                  stage: d.stage,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: TackSpace.stack),

        cities.when(
          loading: () => const TackSkeleton(height: 52, radius: 12),
          error: (_, _) => Text(
            'The city list did not load. Check your connection and try again.',
            style: TackText.fieldError,
          ),
          data: (list) {
            if (draft.countryId == null) {
              return TackSelectField<City>(
                label: 'City',
                hint: 'Choose a country first',
                value: null,
                valueLabel: (c) => c.name,
                enabled: false,
                onTap: () {},
              );
            }
            if (list.isEmpty) {
              // No seeded list for this country; let them type rather than
              // showing an empty picker.
              return TackTextField(
                label: 'City',
                hint: 'Where you live',
                controller: _city,
                onChanged: (v) => controller.patch(
                  (d) => d.copyWith(cityId: v.trim().isEmpty ? null : v.trim()),
                ),
              );
            }
            return TackSelectField<City>(
              label: 'City',
              hint: 'Choose your city',
              value: list.where((c) => c.id == draft.cityId).firstOrNull,
              valueLabel: (c) => c.name,
              onTap: () async {
                final picked = await showPickerSheet<City>(
                  context: context,
                  title: 'Your city',
                  options: list,
                  labelOf: (c) => c.name,
                  selected: list.where((c) => c.id == draft.cityId).firstOrNull,
                  searchHint: 'Search cities',
                );
                if (picked != null) {
                  controller.patch((d) => d.copyWith(cityId: picked.id));
                }
              },
            );
          },
        ),
        const SizedBox(height: TackSpace.stack),

        TackTextField(
          label: 'Phone number (optional)',
          hint: '712345678',
          controller: _phone,
          keyboardType: TextInputType.phone,
          maxLength: 15,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          prefix: Text(
            draft.dialCode,
            style: TackText.body.copyWith(color: TackColors.muted),
          ),
          helperText: 'We only use this if an employer needs to reach you.',
          onChanged: (v) => controller.patch((d) => d.copyWith(phone: v)),
        ),
      ],
    );
  }
}
