import 'package:flutter/material.dart';

void showFailure(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.toString().replaceFirst(
            RegExp(r'^(Bad state: |FormatException: )'),
            '',
          ),
        ),
      ),
    );

Future<void> runUiAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) showFailure(context, error);
  }
}
