import sys

path = r'e:\zharfann\project\our-chat\app\oc_apps_01\lib\screens\media_screen.dart'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

# Add imports
if 'mention_parser.dart' not in code:
    code = code.replace(
        "import 'notification_screen.dart';",
        "import 'notification_screen.dart';\nimport '../utils/mention_parser.dart';\nimport '../utils/mention_input.dart';"
    )

# Replace post caption with MentionParser
code = code.replace(
    "Text(post.caption, style: const TextStyle(fontSize: 15)),",
    "MentionParser.buildText(context, post.caption, style: const TextStyle(fontSize: 15), myUserId: _myUserId),"
)

# Replace CommentSheet subtitle with MentionParser
code = code.replace(
    "subtitle: Text(c['text'].toString()),",
    "subtitle: MentionParser.buildText(context, c['text'].toString(), myUserId: widget.myUserId),"
)

# Replace CommentSheet TextField with MentionInput
find_textfield = """              child: TextField(
                controller: _commentController,
                decoration: InputDecoration(
                  hintText: 'Tambahkan komentar...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  suffixIcon: _isSending
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send, color: Color(0xFF0F3460)),
                          onPressed: _sendComment,
                        ),
                ),
              ),"""

replace_textfield = """              child: MentionInput(
                controller: _commentController,
                hintText: 'Tambahkan komentar...',
                isSending: _isSending,
                onSend: _sendComment,
              ),"""

code = code.replace(find_textfield, replace_textfield)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated media_screen.dart with mentions")
