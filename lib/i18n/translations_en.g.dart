///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'translations.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	dynamic operator[](String key) => $meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'MOBILE FOUNDATION'
	String get heroEyebrow => 'MOBILE FOUNDATION';

	/// en: 'A calm control room for every landscape.'
	String get heroTitle => 'A calm control room for every landscape.';

	/// en: 'Configuration, identity, session safety, and release rails arrive ready to adapt.'
	String get heroBody => 'Configuration, identity, session safety, and release rails arrive ready to adapt.';

	/// en: 'Run the onboarding check'
	String get startAction => 'Run the onboarding check';

	/// en: 'Open preferences'
	String get secondaryAction => 'Open preferences';

	/// en: 'Template systems ready'
	String get statusReady => 'Template systems ready';

	/// en: 'Checking your home landscape…'
	String get statusPending => 'Checking your home landscape…';

	/// en: 'Runtime preferences'
	String get settingsTitle => 'Runtime preferences';

	/// en: 'Theme and locale updates rebuild the live application without a source edit.'
	String get settingsBody => 'Theme and locale updates rebuild the live application without a source edit.';

	/// en: 'Theme'
	String get themeLabel => 'Theme';

	/// en: 'System'
	String get themeSystem => 'System';

	/// en: 'Light'
	String get themeLight => 'Light';

	/// en: 'Dark'
	String get themeDark => 'Dark';

	/// en: 'Signal color'
	String get accentLabel => 'Signal color';

	/// en: 'Landscape identity'
	String get accentIdentity => 'Landscape identity';

	/// en: 'Ocean teal'
	String get accentOcean => 'Ocean teal';

	/// en: 'Alert rose'
	String get accentRose => 'Alert rose';

	/// en: 'Beacon amber'
	String get accentAmber => 'Beacon amber';

	/// en: 'Language'
	String get localeLabel => 'Language';

	/// en: 'English'
	String get localeEnglish => 'English';

	/// en: 'Spanish'
	String get localeSpanish => 'Spanish';

	/// en: 'Monthly signal budget'
	String get amountLabel => 'Monthly signal budget';

	/// en: 'Use the in-app keypad; the operating-system keyboard stays closed.'
	String get amountHelp => 'Use the in-app keypad; the operating-system keyboard stays closed.';

	/// en: 'Clear'
	String get clearAction => 'Clear';

	/// en: 'Save draft'
	String get saveAction => 'Save draft';

	/// en: 'Restore draft'
	String get restoreAction => 'Restore draft';

	/// en: 'Try again'
	String get retryAction => 'Try again';

	/// en: 'Copy error details'
	String get copyErrorAction => 'Copy error details';

	/// en: 'No active incidents'
	String get emptyTitle => 'No active incidents';

	/// en: 'The quiet state is designed, not forgotten.'
	String get emptyBody => 'The quiet state is designed, not forgotten.';

	/// en: 'Home claim checked and onboarding is ready.'
	String get onboardingComplete => 'Home claim checked and onboarding is ready.';

	/// en: 'Signal search'
	String get searchLabel => 'Signal search';

	/// en: 'Filter this control room'
	String get searchHint => 'Filter this control room';

	/// en: 'The current query is stored in the route and is safe to share.'
	String get searchState => 'The current query is stored in the route and is safe to share.';

	/// en: 'CONFIG'
	String get readinessConfig => 'CONFIG';

	/// en: 'SESSION'
	String get readinessSession => 'SESSION';

	/// en: 'LOCALES'
	String get readinessLocales => 'LOCALES';

	/// en: 'THEME'
	String get readinessTheme => 'THEME';

	/// en: '10m access · 14d refresh'
	String get readinessSessionValue => '10m access · 14d refresh';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'heroEyebrow' => 'MOBILE FOUNDATION',
			'heroTitle' => 'A calm control room for every landscape.',
			'heroBody' => 'Configuration, identity, session safety, and release rails arrive ready to adapt.',
			'startAction' => 'Run the onboarding check',
			'secondaryAction' => 'Open preferences',
			'statusReady' => 'Template systems ready',
			'statusPending' => 'Checking your home landscape…',
			'settingsTitle' => 'Runtime preferences',
			'settingsBody' => 'Theme and locale updates rebuild the live application without a source edit.',
			'themeLabel' => 'Theme',
			'themeSystem' => 'System',
			'themeLight' => 'Light',
			'themeDark' => 'Dark',
			'accentLabel' => 'Signal color',
			'accentIdentity' => 'Landscape identity',
			'accentOcean' => 'Ocean teal',
			'accentRose' => 'Alert rose',
			'accentAmber' => 'Beacon amber',
			'localeLabel' => 'Language',
			'localeEnglish' => 'English',
			'localeSpanish' => 'Spanish',
			'amountLabel' => 'Monthly signal budget',
			'amountHelp' => 'Use the in-app keypad; the operating-system keyboard stays closed.',
			'clearAction' => 'Clear',
			'saveAction' => 'Save draft',
			'restoreAction' => 'Restore draft',
			'retryAction' => 'Try again',
			'copyErrorAction' => 'Copy error details',
			'emptyTitle' => 'No active incidents',
			'emptyBody' => 'The quiet state is designed, not forgotten.',
			'onboardingComplete' => 'Home claim checked and onboarding is ready.',
			'searchLabel' => 'Signal search',
			'searchHint' => 'Filter this control room',
			'searchState' => 'The current query is stored in the route and is safe to share.',
			'readinessConfig' => 'CONFIG',
			'readinessSession' => 'SESSION',
			'readinessLocales' => 'LOCALES',
			'readinessTheme' => 'THEME',
			'readinessSessionValue' => '10m access · 14d refresh',
			_ => null,
		};
	}
}
