import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/client.dart';

class RecoveryController extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authStateProvider, (_, next) {
      final event = next.value?.event;
      if (event == AuthChangeEvent.passwordRecovery) state = true;
      if (event == AuthChangeEvent.signedOut ||
          event == AuthChangeEvent.userUpdated) {
        state = false;
      }
    });
    return ref.read(authStateProvider).value?.event ==
        AuthChangeEvent.passwordRecovery;
  }
}

final passwordRecoveryProvider = NotifierProvider<RecoveryController, bool>(
  RecoveryController.new,
);
