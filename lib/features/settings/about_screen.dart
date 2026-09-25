import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/design.dart';

/// The version string shown on the About page. Kept next to the screen (and
/// matching `pubspec.yaml`'s `version: 1.0.0+11`) so a release bump is a
/// two-line edit, not a string hunt.
const String kAppVersionLabel = 'Version 1.0.0 (11)';

/// The family-canonical About page — the kit's [OptAboutPage] brand moment
/// over this app's BrandTheme gradient, so OptDAI closes on the same note as
/// every other app in the suite. URL handling stays here (url_launcher is not
/// a kit dependency).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return OptAboutPage(
      logo: Image.asset('assets/branding/icon.png'),
      appName: 'OptDAI',
      version: kAppVersionLabel,
      tagline: 'Doctor assistance intelligence',
      description:
          'OptDAI is an offline-first clinical record for the consulting '
          'room: an encrypted on-device chart with dictation, reference-range '
          'flagging and an on-device assistant that answers questions about '
          'the register. Everything — records, audio, speech recognition and '
          'the language model — runs on this device; nothing leaves it.',
      onOpenUrl: _openUrl,
      productUrl: 'https://opterp.com',
      companyUrl: 'https://geofinity.com.np',
    );
  }
}
