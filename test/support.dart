import 'package:diene_config/diene_config.dart';

final class AppBlock {
  const AppBlock({
    required this.name,
    required this.retries,
    required this.tags,
  });

  final String name;
  final int retries;
  final List<String> tags;
}

final ConfigBlock<AppBlock> appBlock = ConfigBlock<AppBlock>(
  key: 'app',
  decode: (Map<String, Object?> values) {
    final Object? name = values['name'];
    final Object? retries = values['retries'];
    final Object? tags = values['tags'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('name must be a non-empty string');
    }
    if (retries is! int || retries < 0) {
      throw const FormatException('retries must be a non-negative integer');
    }
    if (tags is! List<Object?> || tags.any((Object? item) => item is! String)) {
      throw const FormatException('tags must be a string list');
    }
    return AppBlock(
      name: name,
      retries: retries,
      tags: tags.cast<String>().toList(growable: false),
    );
  },
);

ConfigSchema appSchema({bool rejectUnknownBlocks = true}) => ConfigSchema(
  blocks: <ConfigBlockSchema>[appBlock],
  rejectUnknownBlocks: rejectUnknownBlocks,
);
