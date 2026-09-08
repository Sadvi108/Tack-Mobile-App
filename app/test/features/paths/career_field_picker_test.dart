import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/paths/application/catalog.dart';
import 'package:tack/features/paths/presentation/career_field_picker.dart';
import '../../helpers.dart';

void main() {
  setUpAll(loadTackFonts);
  testWidgets('at 360px a student chooses a field and then its career path', (
    tester,
  ) async {
    const food = CareerPath(
      id: 'food',
      slug: 'food',
      title: 'Food quality associate',
      summary: 'Explore food quality',
      category: 'agriculture',
      fieldSlug: 'agriculture',
      fieldName: 'Agriculture',
    );
    const mobile = CareerPath(
      id: 'mobile',
      slug: 'mobile',
      title: 'Mobile app developer',
      summary: 'Build apps',
      category: 'computer-science',
      fieldSlug: 'computer-science',
      fieldName: 'Computer science',
    );
    CareerPath? picked;
    await pumpAt(
      tester,
      TackScaffold(body: CareerFieldPicker(onPick: (p) => picked = p)),
      size: const Size(360, 640),
      overrides: [
        careerPathsProvider.overrideWith((ref) async => [food, mobile]),
      ],
    );
    await tester.tap(find.text('Browse fields and career paths'));
    await tester.pumpAndSettle();
    expect(find.text('Agriculture'), findsOneWidget);
    await tester.tap(find.text('Agriculture'));
    await tester.pumpAndSettle();
    expect(find.text('Food quality associate'), findsOneWidget);
    expect(find.text('Mobile app developer'), findsNothing);
    await tester.tap(find.text('Food quality associate'));
    await tester.pumpAndSettle();
    expect(picked?.slug, 'food');
    expect(tester.takeException(), isNull);
  });
}
