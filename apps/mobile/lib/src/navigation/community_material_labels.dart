import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Match the spoken language to the Chinese interface, including numerals.
class CommunitySpokenLocale extends StatelessWidget {
  const CommunitySpokenLocale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(localeForSubtree: const Locale('zh', 'CN'), child: child);
}

/// The shipped Chinese UI uses the SDK's default Material strings. Override
/// navigation labels without changing locale, formatting, or dependencies.
class CommunityMaterialLabels extends DefaultMaterialLocalizations {
  const CommunityMaterialLabels();

  @override
  String get backButtonTooltip => '返回';

  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _CommunityMaterialLabelsDelegate();
}

class _CommunityMaterialLabelsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _CommunityMaterialLabelsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(const CommunityMaterialLabels());

  @override
  bool shouldReload(_CommunityMaterialLabelsDelegate old) => false;
}
