// Outside links: phone dialer, email, WhatsApp, website, and the system
// share sheet for plain text.
library;

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// TallyConnect contact details and links, as published on
/// https://tally-connect.com/ (Contact section and footer).
abstract final class TcSite {
  static const String website = 'https://tally-connect.com/';
  static const String dashboard = 'https://dashboard.tally-connect.com';
  static const String supportEmail = 'info@averlonworld.com';
  static const String supportPhone = '+91 9892440788';
  static const String supportHours = '24/7 Support Available';
  static const String company = 'Averlon Enterprise Solutions Private Limited';
  static const String address =
      '5th Floor, Lodha Supremus - II, Phase - II, Unit No. A-515, Road No. '
      '22, Wagle Industrial Estate, Thane West, 400604, Mumbai, '
      'Maharashtra, India';
}

/// Opens [uri] in the app that handles it. False when nothing could.
Future<bool> openLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Opens WhatsApp with [text] ready to send (the user picks the contact);
/// falls back to the share sheet when WhatsApp is not installed.
Future<bool> shareOnWhatsApp(String text) async {
  final String q = Uri.encodeComponent(text);
  if (await openLink(Uri.parse('whatsapp://send?text=$q'))) return true;
  if (await openLink(Uri.parse('https://wa.me/?text=$q'))) return true;
  return shareText(text);
}

/// The system share sheet with [text].
Future<bool> shareText(String text, {String? subject}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
    return true;
  } catch (_) {
    return false;
  }
}
