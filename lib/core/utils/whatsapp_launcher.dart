import 'package:url_launcher/url_launcher.dart';

class WhatsAppLauncher {
  /// Launches direct WhatsApp conversation with pre-filled message
  static Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    // Sanitize phone number (remove +, spaces, hyphens)
    String cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    // If 10 digits (e.g. Indian standard), prepend country code 91 if not present
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final encodedMessage = Uri.encodeComponent(message);
    final urlString = 'https://wa.me/$cleanPhone?text=$encodedMessage';
    final uri = Uri.parse(urlString);

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Launches phone dialer
  static Future<bool> callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
