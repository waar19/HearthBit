import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Acceso corto a las traducciones dentro del árbol de widgets.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Traducciones fuera del árbol de widgets (controladores y servicios que
/// generan mensajes visibles sin tener un BuildContext, p. ej. errores
/// asíncronos o el texto del SOS del modo rescate).
AppLocalizations get currentL10n => lookupAppLocalizations(
  basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  ),
);
