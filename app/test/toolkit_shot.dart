import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/core/ai/allowance.dart';
import 'package:tack/core/offline/sync.dart';
import 'package:tack/design/tack.dart';
import 'package:tack/features/interview/data/interview_models.dart';
import 'package:tack/features/toolkit/application/toolkit_status.dart';
import 'package:tack/features/toolkit/presentation/toolkit_screen.dart';
import 'package:tack/features/vault/application/cv_check.dart';

import 'helpers.dart';
import 'shot_util.dart';

/// The Toolkit hub for design review: explore and launch, at 360px and on a
/// large phone, light and dark. Named *_shot.dart so `flutter test` skips it;
/// run it with `flutter test test/toolkit_shot.dart`.
void main() {
  setUpAll(loadTackFonts);
  tearDown(() => TackBrightness.set(Brightness.light));

  final documents = [
    TackDocument(
      id: 'cv',
      type: DocumentType.cv,
      title: 'CV',
      storagePath: 'users/u/cv',
      status: DocumentStatus.ready,
      mimeType: 'application/pdf',
      isDefault: true,
      createdAt: DateTime(2026, 11),
    ),
    TackDocument(
      id: 'cert',
      type: DocumentType.certificate,
      title: 'Certificate',
      storagePath: 'users/u/cert',
      status: DocumentStatus.ready,
      mimeType: 'image/png',
      createdAt: DateTime(2026, 11),
    ),
  ];

  for (final mode in [YearMode.explore, YearMode.launch]) {
    for (final size in [const Size(360, 780), const Size(430, 932)]) {
      for (final brightness in Brightness.values) {
        final name =
            'toolkit-${mode.name}-${size.width.toInt()}-${brightness.name}';
        testWidgets(name, (tester) async {
          TackBrightness.set(brightness);
          await shoot(
            tester,
            const ToolkitScreen(),
            name,
            size,
            brightness: brightness,
            panels: const [0, 600],
            overrides: [
              modeProvider.overrideWithValue(mode),
              isOnlineProvider.overrideWithValue(true),
              pendingChangesProvider.overrideWith((ref) => Stream.value(0)),
              documentsProvider.overrideWith((ref) async => documents),
              dueQuestionsProvider.overrideWith(
                (ref) async => [
                  for (var i = 0; i < 3; i++)
                    DueQuestion(
                      questionId: 'q$i',
                      role: 'data-analyst',
                      question: 'Question $i',
                    ),
                ],
              ),
              aiAllowanceProvider.overrideWith(
                (ref) async => const AiAllowance(used: 2, limit: 8),
              ),
            ],
          );
        });
      }
    }
  }
}
