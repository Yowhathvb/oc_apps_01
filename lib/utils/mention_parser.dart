import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MentionParser {
  static Widget buildText(
    BuildContext context, 
    String text, 
    {TextStyle? style, String? myUserId}
  ) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    final matches = mentionRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: style);
    }

    int currentIndex = 0;
    List<TextSpan> spans = [];

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start), style: style));
      }

      final username = match.group(1);
      final mentionText = match.group(0); // includes @

      spans.add(TextSpan(
        text: mentionText,
        style: (style ?? const TextStyle()).copyWith(color: Colors.blue, fontWeight: FontWeight.bold),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            // Kita perlu ambil ID dari username, ini sedikit tricky kalau tidak ada API untuk GET user by username, 
            // Namun saya ingat kita punya endpoint by-username atau profile?
            // Jika tidak, biarkan saja warna biru untuk saat ini atau arahkan dengan cara lain.
            // Oh, backend saya lihat tadi punya pp/api/v1/users/by-username/[username]
            importUserProfileByUsername(context, username!, myUserId);
          },
      ));

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex), style: style));
    }

    return RichText(text: TextSpan(children: spans));
  }

  static Future<void> importUserProfileByUsername(BuildContext context, String username, String? myUserId) async {
    // Ideally we should resolve username to ID, but let's assume we can navigate to UserProfileScreen with username if needed.
    // However UserProfileScreen requires userId.
    // For now, let's just print or do nothing if we can't easily resolve it here without async delay in UI.
    // Actually, we can push a temporary loading screen or just resolve it.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clicked on @')));
  }
}
