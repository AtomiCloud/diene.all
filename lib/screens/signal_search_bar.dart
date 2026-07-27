/// The query-param-bound search bar (search-bar standard, Flutter variant).
///
/// The route is the source of truth: the controller is initialized from the
/// current location, live edits use `replace` so history is not flooded, and an
/// empty query removes the parameter rather than leaving `?q=`. Nothing about
/// the current query is held only in widget state, which is what makes the link
/// shareable and back/forward correct.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../routing/query_state.dart';

/// A search field bound to the `q` query parameter of the current route.
final class SignalSearchBar extends StatefulWidget {
  const SignalSearchBar({
    required this.query,
    required this.path,
    required this.hintText,
    required this.clearTooltip,
    super.key,
  });

  /// The current shareable state, parsed from the route by the screen.
  final SignalQuery query;

  /// The app path this bar writes back to (its own screen's path).
  final String path;

  final String hintText;
  final String clearTooltip;

  @override
  State<SignalSearchBar> createState() => _SignalSearchBarState();
}

final class _SignalSearchBarState extends State<SignalSearchBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query.text,
  );

  @override
  void didUpdateWidget(SignalSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Back/forward and any external route change must be reflected here: the
    // route drives the field, not the other way round. Guarded so typing does
    // not fight the controller.
    final String incoming = widget.query.text;
    if (oldWidget.query.text != incoming && _controller.text != incoming) {
      _controller.value = TextEditingValue(
        text: incoming,
        selection: TextSelection.collapsed(offset: incoming.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _write(String value) {
    // `replace`, not `push`: a live edit is a correction of where you are, not a
    // new place you went. Pushing every keystroke would make Back walk through
    // the query letter by letter.
    context.replace(
      widget.query
          .copyWith(text: value.trim(), page: 1)
          .toLocation(widget.path),
    );
  }

  @override
  Widget build(BuildContext context) => SearchBar(
    controller: _controller,
    hintText: widget.hintText,
    leading: const Icon(Icons.search_rounded),
    trailing: <Widget>[
      if (_controller.text.isNotEmpty)
        IconButton(
          tooltip: widget.clearTooltip,
          onPressed: () {
            _controller.clear();
            // An empty query REMOVES the parameter, so the canonical link for
            // the unfiltered view is the bare path.
            _write('');
            setState(() {});
          },
          icon: const Icon(Icons.close_rounded),
        ),
    ],
    onChanged: (String value) {
      _write(value);
      setState(() {});
    },
  );
}
