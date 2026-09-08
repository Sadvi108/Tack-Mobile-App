import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/features/vault/data/document_models.dart';
import 'package:tack/features/vault/data/document_repository.dart';
import 'package:tack/features/vault/presentation/vault_screen.dart';
import '../../helpers.dart';

class _Repository extends DocumentRepository {
  _Repository()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final gate = Completer<void>();
  final opened = <String>[];
  @override
  Future<void> openOnDevice(String id) async {
    opened.add(id);
    await gate.future;
  }
}

void main() {
  setUpAll(loadTackFonts);
  testWidgets(
    'tapping a resume opens it once and keeps its options available at 360px',
    (tester) async {
      final repository = _Repository();
      final document = TackDocument(
        id: 'resume',
        type: DocumentType.cv,
        title: 'My resume',
        storagePath: 'private/resume',
        status: DocumentStatus.ready,
        mimeType: 'application/pdf',
        createdAt: DateTime(2026),
      );
      await pumpAt(
        tester,
        const VaultScreen(),
        overrides: [
          documentRepositoryProvider.overrideWithValue(repository),
          documentsProvider.overrideWith((ref) async => [document]),
        ],
      );
      await tester.tap(find.text('My resume'));
      await tester.pump();
      await tester.tap(find.text('My resume'));
      expect(repository.opened, ['resume']);
      repository.gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Options for My resume'));
      await tester.pumpAndSettle();
      expect(find.text('Open with an app'), findsOneWidget);
      expect(find.text('Free CV check'), findsOneWidget);
      expect(find.text('Rename it'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    },
  );
}
