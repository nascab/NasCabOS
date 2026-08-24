import 'package:NasCabOS/modules/base/components/custom_letter_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CustomLetterFilter does not overflow in constrained height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: Align(
              alignment: Alignment.topLeft,
              child: CustomLetterFilter(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
