import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final class AmountInput extends StatefulWidget {
  const AmountInput({
    required this.label,
    required this.help,
    required this.onChanged,
    this.initialMinorUnits = 0,
    super.key,
  });

  final String label;
  final String help;
  final int initialMinorUnits;
  final ValueChanged<int> onChanged;

  @override
  State<AmountInput> createState() => _AmountInputState();
}

final class _AmountInputState extends State<AmountInput> {
  late int _minorUnits = widget.initialMinorUnits;

  void _digit(int value) {
    if (_minorUnits > 99999999) {
      return;
    }
    setState(() => _minorUnits = (_minorUnits * 10) + value);
    widget.onChanged(_minorUnits);
  }

  void _backspace() {
    setState(() => _minorUnits ~/= 10);
    widget.onChanged(_minorUnits);
  }

  @override
  Widget build(BuildContext context) {
    final String amount = NumberFormat.simpleCurrency(
      locale: Localizations.localeOf(context).toLanguageTag(),
    ).format(_minorUnits / 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(widget.help, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                amount,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: <Widget>[
            for (final int digit in <int>[1, 2, 3, 4, 5, 6, 7, 8, 9])
              _Key(label: '$digit', onPressed: () => _digit(digit)),
            _Key(
              label: '00',
              onPressed: () {
                _digit(0);
                _digit(0);
              },
            ),
            _Key(label: '0', onPressed: () => _digit(0)),
            _Key(icon: Icons.backspace_outlined, onPressed: _backspace),
          ],
        ),
      ],
    );
  }
}

final class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onPressed});

  final String? label;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: icon == null
        ? Text(label!, style: Theme.of(context).textTheme.titleMedium)
        : Icon(icon),
  );
}
