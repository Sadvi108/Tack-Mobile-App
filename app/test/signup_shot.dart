import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tack/features/auth/presentation/signup_screen.dart';

import 'helpers.dart';
import 'shot_util.dart';

void main() {
  setUpAll(loadTackFonts);

  testWidgets('sign up at the 360px floor', (tester) async {
    await shoot(tester, const SignUpScreen(), 'signup', const Size(360, 640));
  });
}
