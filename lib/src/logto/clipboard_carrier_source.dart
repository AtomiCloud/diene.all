import 'package:flutter/services.dart';

import '../deferred/deferred_login.dart';

/// iOS clipboard carrier reader (C0 §7). Reads the clipboard on launch with no
/// consent tap and clears it only when it still equals the captured value.
final class ClipboardCarrierReader implements ClipboardCarrierSource {
  const ClipboardCarrierReader();

  @override
  Future<String?> read() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> clearIfEquals(String value) async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text?.trim() == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}

/// Android Install Referrer source backed by injected callbacks, so the actual
/// `android_play_install_referrer` plugin stays in the app (flutter-base)
/// rather than in this dependency-light package.
final class CallbackInstallReferrerSource implements InstallReferrerSource {
  const CallbackInstallReferrerSource({
    required Future<String?> Function() readReferrer,
    required Future<void> Function() markProcessed,
  }) : _readReferrer = readReferrer,
       _markProcessed = markProcessed;

  final Future<String?> Function() _readReferrer;
  final Future<void> Function() _markProcessed;

  @override
  Future<String?> read() => _readReferrer();

  @override
  Future<void> markProcessed() => _markProcessed();
}
