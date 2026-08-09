/// An immutable note with a [title] and [body], plus a JSON wire codec.
///
/// This is the replaceable sample value type of the library template. The wire
/// form is a plain JSON object `{"title": <string>, "body": <string>}`.
final class Note {
  /// Creates a note from its [title] and [body].
  const Note({required this.title, required this.body});

  /// Decodes a note from its JSON wire form.
  ///
  /// Throws a [FormatException] when [title] is missing or empty, or when
  /// [body] is not a string.
  factory Note.fromJson(Map<String, Object?> json) {
    final Object? title = json['title'];
    final Object? body = json['body'];
    if (title is! String || title.isEmpty) {
      throw const FormatException('Note.title must be a non-empty string.');
    }
    if (body is! String) {
      throw const FormatException('Note.body must be a string.');
    }
    return Note(title: title, body: body);
  }

  /// Human-readable heading of the note.
  final String title;

  /// Free-form contents of the note.
  final String body;

  /// Encodes this note to its JSON wire form.
  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'body': body,
  };

  @override
  bool operator ==(Object other) =>
      other is Note && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'Note(title: $title, body: $body)';
}
