import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tack/features/coach/data/coach_repository.dart';

class _Functions extends Mock implements FunctionsClient {}

/// Only the functions client is ever touched by `ask`.
class _Db extends Fake implements SupabaseClient {
  _Db(this.functions);

  @override
  final FunctionsClient functions;
}

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  late _Functions functions;
  late CoachRepository repository;

  setUp(() {
    functions = _Functions();
    repository = CoachRepository(_Db(functions));
    when(() => functions.invoke(any(), body: any(named: 'body'))).thenAnswer(
      (_) async => FunctionResponse(
        status: 200,
        data: {'threadId': 't1', 'reply': 'Hi.', 'answeredBy': 'data'},
      ),
    );
  });

  Map<String, dynamic> sentBody() =>
      verify(
            () => functions.invoke('coach', body: captureAny(named: 'body')),
          ).captured.single
          as Map<String, dynamic>;

  test('every question carries a fresh operation id', () async {
    // Without one the server keyed the job on the question's text, so asking
    // the same thing again later came back as a duplicate of the first time.
    await repository.ask('How do I explain a gap year?');
    final first = sentBody()['operationId'] as String;
    expect(first, matches(_uuidV4));

    await repository.ask('How do I explain a gap year?');
    final second = sentBody()['operationId'] as String;
    expect(second, matches(_uuidV4));
    expect(second, isNot(first));
  });

  test('a retry sends the id it is given, so it is charged once', () async {
    const id = '2f1c3a4b-5d6e-4f70-8a9b-0c1d2e3f4a5b';
    await repository.ask('Again?', threadId: 't1', operationId: id);
    final body = sentBody();
    expect(body['operationId'], id);
    expect(body['threadId'], 't1');
  });
}
