import 'package:flutter/material.dart';

final class AsyncButton extends StatefulWidget {
  const AsyncButton({
    required this.onPressed,
    required this.label,
    this.icon,
    this.outlined = false,
    super.key,
  });

  final Future<void> Function()? onPressed;
  final Widget label;
  final IconData? icon;
  final bool outlined;

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

final class _AsyncButtonState extends State<AsyncButton> {
  bool _pending = false;

  Future<void> _run() async {
    if (_pending || widget.onPressed == null) {
      return;
    }
    setState(() => _pending = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) {
        setState(() => _pending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: _pending
          ? Row(
              key: const ValueKey<String>('pending'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                const SizedBox(width: 10),
                Flexible(child: widget.label),
              ],
            )
          : Row(
              key: const ValueKey<String>('ready'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.icon != null) ...<Widget>[
                  Icon(widget.icon, size: 19),
                  const SizedBox(width: 9),
                ],
                Flexible(child: widget.label),
              ],
            ),
    );
    return Semantics(
      button: true,
      enabled: !_pending && widget.onPressed != null,
      child: widget.outlined
          ? OutlinedButton(onPressed: _pending ? null : _run, child: content)
          : FilledButton(onPressed: _pending ? null : _run, child: content),
    );
  }
}
