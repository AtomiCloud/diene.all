import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class PersistentFormField extends StatefulWidget {
  const PersistentFormField({
    required this.storageKey,
    required this.label,
    required this.preferences,
    required this.validator,
    this.onChanged,
    super.key,
  });

  final String storageKey;
  final String label;
  final SharedPreferences preferences;
  final String? Function(String value) validator;
  final ValueChanged<String>? onChanged;

  @override
  State<PersistentFormField> createState() => PersistentFormFieldState();
}

final class PersistentFormFieldState extends State<PersistentFormField> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.preferences.getString(widget.storageKey) ?? '';
  }

  Future<void> clear() async {
    _controller.clear();
    setState(() => _error = null);
    await widget.preferences.remove(widget.storageKey);
    widget.onChanged?.call('');
  }

  Future<void> restore() async {
    _controller.text = widget.preferences.getString(widget.storageKey) ?? '';
    setState(() => _error = widget.validator(_controller.text));
    widget.onChanged?.call(_controller.text);
  }

  Future<void> submitted() => clear();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textInputAction: TextInputAction.done,
    autofillHints: const <String>[AutofillHints.name],
    decoration: InputDecoration(labelText: widget.label, errorText: _error),
    onChanged: (String value) async {
      setState(() => _error = widget.validator(value));
      await widget.preferences.setString(widget.storageKey, value);
      widget.onChanged?.call(value);
    },
  );
}
