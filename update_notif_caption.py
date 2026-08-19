import sys

path = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\notifications\route.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

find_str = """      SELECT n.*, 
             u.name as sender_name, u.username as sender_username, NULL as sender_avatar,
             p.media_url as post_media_url, p.media_type as post_media_type
      FROM notifications n"""

replace_str = """      SELECT n.*, 
             u.name as sender_name, u.username as sender_username, u.avatar as sender_avatar,
             p.media_url as post_media_url, p.media_type as post_media_type, p.caption as post_caption
      FROM notifications n"""

code = code.replace(find_str, replace_str)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated notifications GET route for caption")
