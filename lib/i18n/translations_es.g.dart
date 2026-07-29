///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'translations.g.dart';

// Path: <root>
class TranslationsEs with BaseTranslations<AppLocale, Translations> implements Translations {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.es,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <es>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key);

	late final TranslationsEs _root = this; // ignore: unused_field

	@override
	TranslationsEs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEs(meta: meta ?? this.$meta);

	// Translations
	@override String get heroEyebrow => 'BASE MÓVIL';
	@override String get heroTitle => 'Una sala de control serena para cada paisaje.';
	@override String get heroBody => 'La configuración, la identidad, la seguridad de sesión y los canales de entrega llegan listos para adaptar.';
	@override String get startAction => 'Ejecutar la comprobación de incorporación';
	@override String get secondaryAction => 'Abrir preferencias';
	@override String get statusReady => 'Sistemas de plantilla listos';
	@override String get statusPending => 'Comprobando tu paisaje de origen…';
	@override String get settingsTitle => 'Preferencias en tiempo de ejecución';
	@override String get settingsBody => 'Los cambios de tema e idioma reconstruyen la aplicación en vivo sin editar el código fuente.';
	@override String get themeLabel => 'Tema';
	@override String get themeSystem => 'Sistema';
	@override String get themeLight => 'Claro';
	@override String get themeDark => 'Oscuro';
	@override String get accentLabel => 'Color de señal';
	@override String get accentIdentity => 'Identidad del paisaje';
	@override String get accentOcean => 'Verde azulado oceánico';
	@override String get accentRose => 'Rosa de alerta';
	@override String get accentAmber => 'Ámbar de baliza';
	@override String get localeLabel => 'Idioma';
	@override String get localeEnglish => 'Inglés';
	@override String get localeSpanish => 'Español';
	@override String get amountLabel => 'Presupuesto mensual de señal';
	@override String get amountHelp => 'Usa el teclado integrado; el teclado del sistema operativo permanece cerrado.';
	@override String get clearAction => 'Limpiar';
	@override String get saveAction => 'Guardar borrador';
	@override String get restoreAction => 'Restaurar borrador';
	@override String get retryAction => 'Intentar de nuevo';
	@override String get copyErrorAction => 'Copiar detalles del error';
	@override String get emptyTitle => 'No hay incidentes activos';
	@override String get emptyBody => 'El estado tranquilo está diseñado, no olvidado.';
	@override String get onboardingComplete => 'La asignación de origen se comprobó y la incorporación está lista.';
	@override String get searchLabel => 'Búsqueda de señales';
	@override String get searchHint => 'Filtrar esta sala de control';
	@override String get searchState => 'La consulta actual se guarda en la ruta y se puede compartir.';
	@override String get readinessConfig => 'CONFIGURACIÓN';
	@override String get readinessSession => 'SESIÓN';
	@override String get readinessLocales => 'IDIOMAS';
	@override String get readinessTheme => 'TEMA';
	@override String get readinessSessionValue => '10 min de acceso · 14 días de renovación';
}

/// The flat map containing all translations for locale <es>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'heroEyebrow' => 'BASE MÓVIL',
			'heroTitle' => 'Una sala de control serena para cada paisaje.',
			'heroBody' => 'La configuración, la identidad, la seguridad de sesión y los canales de entrega llegan listos para adaptar.',
			'startAction' => 'Ejecutar la comprobación de incorporación',
			'secondaryAction' => 'Abrir preferencias',
			'statusReady' => 'Sistemas de plantilla listos',
			'statusPending' => 'Comprobando tu paisaje de origen…',
			'settingsTitle' => 'Preferencias en tiempo de ejecución',
			'settingsBody' => 'Los cambios de tema e idioma reconstruyen la aplicación en vivo sin editar el código fuente.',
			'themeLabel' => 'Tema',
			'themeSystem' => 'Sistema',
			'themeLight' => 'Claro',
			'themeDark' => 'Oscuro',
			'accentLabel' => 'Color de señal',
			'accentIdentity' => 'Identidad del paisaje',
			'accentOcean' => 'Verde azulado oceánico',
			'accentRose' => 'Rosa de alerta',
			'accentAmber' => 'Ámbar de baliza',
			'localeLabel' => 'Idioma',
			'localeEnglish' => 'Inglés',
			'localeSpanish' => 'Español',
			'amountLabel' => 'Presupuesto mensual de señal',
			'amountHelp' => 'Usa el teclado integrado; el teclado del sistema operativo permanece cerrado.',
			'clearAction' => 'Limpiar',
			'saveAction' => 'Guardar borrador',
			'restoreAction' => 'Restaurar borrador',
			'retryAction' => 'Intentar de nuevo',
			'copyErrorAction' => 'Copiar detalles del error',
			'emptyTitle' => 'No hay incidentes activos',
			'emptyBody' => 'El estado tranquilo está diseñado, no olvidado.',
			'onboardingComplete' => 'La asignación de origen se comprobó y la incorporación está lista.',
			'searchLabel' => 'Búsqueda de señales',
			'searchHint' => 'Filtrar esta sala de control',
			'searchState' => 'La consulta actual se guarda en la ruta y se puede compartir.',
			'readinessConfig' => 'CONFIGURACIÓN',
			'readinessSession' => 'SESIÓN',
			'readinessLocales' => 'IDIOMAS',
			'readinessTheme' => 'TEMA',
			'readinessSessionValue' => '10 min de acceso · 14 días de renovación',
			_ => null,
		};
	}
}
