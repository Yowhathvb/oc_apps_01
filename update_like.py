import sys

path = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\posts\[postId]\like\route.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if 'sendNotification' not in code:
    code = code.replace(
        "import { cookies } from 'next/headers';",
        "import { cookies } from 'next/headers';\nimport { sendNotification } from '@/lib/notification-helper';"
    )
    
    find_str = "      await pool.query('INSERT INTO post_likes (post_id, user_id) VALUES (?, ?)', [postId, userId]);\n      await pool.query('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?', [postId]);\n      return NextResponse.json({ success: true, message: 'Liked' });"
    
    replace_str = """      await pool.query('INSERT INTO post_likes (post_id, user_id) VALUES (?, ?)', [postId, userId]);
      await pool.query('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?', [postId]);

      const [posts]: any = await pool.query('SELECT user_id FROM posts WHERE id = ?', [postId]);
      const [users]: any = await pool.query('SELECT name FROM users WHERE id = ?', [userId]);
      if (posts.length > 0 && users.length > 0) {
        const authorId = posts[0].user_id;
        const likerName = users[0].name;
        if (authorId !== userId) {
          await sendNotification(authorId, likerName, 'like', parseInt(postId), ${likerName} menyukai postingan Anda);
        }
      }

      return NextResponse.json({ success: true, message: 'Liked' });"""

    code = code.replace(find_str, replace_str)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print("Updated like route")
else:
    print("Already updated")
