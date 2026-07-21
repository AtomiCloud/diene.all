import 'package:diene_config/diene_config.dart';

final class AppSettings {
  const AppSettings(this.name, this.tags);

  final String name;
  final List<String> tags;
}

final ConfigBlock<AppSettings> appBlock = ConfigBlock<AppSettings>(
  key: 'app',
  decode: (Map<String, Object?> values) => AppSettings(
    values['name']! as String,
    (values['tags']! as List<Object?>).cast<String>(),
  ),
);

Future<void> main() async {
  final ConfigLoader loader = ConfigLoader(
    base: YamlConfigSource.string('''
app: {name: base, tags: [base]}
'''),
    overlay: YamlConfigSource.string('''
app: {name: lapras}
'''),
    developmentOverride: YamlConfigSource.string('{}'),
    dartDefines: DartDefineOverrides(
      prefix: 'APP_',
      values: const <String, String>{
        'APP_APP__NAME': String.fromEnvironment('APP_APP__NAME'),
      },
    ),
    schema: ConfigSchema(blocks: <ConfigBlockSchema>[appBlock]),
  );
  final DieneConfig config = await loader.load();
  final AppSettings app = config.slice(appBlock);
  print('${app.name}: ${app.tags.join(', ')}');
  print(config.rawSlice('app'));

  // A store build normally supplies this define; keeping the source explicit
  // makes the example runnable without one.
  print(landscape(source: const DartDefineLandscapeSource(value: 'lapras')));
}
