import sys

path = r'e:\zharfann\project\our-chat\app\oc_apps_01\lib\screens\notification_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

find_str = """                                    TextSpan(
                                      text: notif['message'].toString().replaceAll(" ", ""),
                                    ),"""

replace_str = """                                    TextSpan(
                                      text: " " + notif['message'].toString().replaceAll(senderName, "").trim(),
                                    ),
                                    if (isPostRelated && notif['post_caption'] != null && notif['post_caption'].toString().isNotEmpty)
                                      TextSpan(
                                        text: " : \"\"",
                                        style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87),
                                      ),"""

code = code.replace(find_str, replace_str)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated notification_screen.dart text formatting")
