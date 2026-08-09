import 'package:flutter/material.dart';

final class SafeAreaShell extends StatelessWidget {
  const SafeAreaShell({required this.child, this.bottomAction, super.key});

  final Widget child;
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: <Widget>[
        Expanded(child: child),
        if (bottomAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(width: double.infinity, child: bottomAction),
          ),
      ],
    ),
  );
}
