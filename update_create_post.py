import sys

path = r'e:\zharfann\project\our-chat\app\oc_apps_01\lib\screens\create_post_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if 'mention_input.dart' not in code:
    code = code.replace(
        "import 'package:image_picker/image_picker.dart';",
        "import 'package:image_picker/image_picker.dart';\nimport '../utils/mention_input.dart';"
    )

find_textfield = """            TextField(
              controller: _captionController,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'Apa yang Anda pikirkan?',
                border: InputBorder.none,
              ),
            ),"""

replace_textfield = """            MentionInput(
              controller: _captionController,
              maxLines: 5,
              hintText: 'Apa yang Anda pikirkan?',
              isSending: false,
              onSend: () {}, // Not used here
            ),"""

code = code.replace(find_textfield, replace_textfield)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated create_post_screen.dart")
