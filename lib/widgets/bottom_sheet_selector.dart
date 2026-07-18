import 'package:flutter/material.dart';

final class SelectorOption<T> {
  const SelectorOption({
    required this.value,
    required this.label,
    this.description,
  });

  final T value;
  final String label;
  final String? description;
}

final class BottomSheetSelector<T> extends StatelessWidget {
  const BottomSheetSelector({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<SelectorOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final SelectorOption<T> selected = options.firstWhere(
      (SelectorOption<T> option) => option.value == value,
    );
    return Semantics(
      button: true,
      label: label,
      value: selected.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final T? next = await showModalBottomSheet<T>(
            context: context,
            showDragHandle: true,
            useSafeArea: true,
            builder: (BuildContext context) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                for (final SelectorOption<T> option in options)
                  ListTile(
                    minTileHeight: 56,
                    title: Text(option.label),
                    subtitle: option.description == null
                        ? null
                        : Text(option.description!),
                    trailing: option.value == value
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          );
          if (next != null) {
            onChanged(next);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
