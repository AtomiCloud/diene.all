import 'package:diene_flutter_base/generated/service/export.dart';
import 'package:diene_flutter_base/i18n/translations.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all shipped locales compile with required typed keys', () async {
    final Translations english = await AppLocale.en.build();
    final Translations spanish = await AppLocale.es.build();

    expect(english.heroTitle, isNotEmpty);
    expect(spanish.heroTitle, isNotEmpty);
    expect(english.retryAction, isNotEmpty);
    expect(spanish.retryAction, isNotEmpty);
  });

  test('generated OA3 model serializes and deserializes', () {
    const UserProfile profile = UserProfile(
      id: 'user-1',
      homeLandscape: 'lapras',
    );

    expect(UserProfile.fromJson(profile.toJson()).homeLandscape, 'lapras');
  });
}
