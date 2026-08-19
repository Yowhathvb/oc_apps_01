import sys

path = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\users\[userId]\follow\route.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if 'sendNotification' not in code:
    code = code.replace(
        "import { errorResponse, successResponse } from '@/lib/api/response';",
        "import { errorResponse, successResponse } from '@/lib/api/response';\nimport { sendNotification } from '@/lib/notification-helper';"
    )
    
    find_str = "      await pool.query('INSERT INTO follows (follower_id, following_id) VALUES (?, ?)', [myId, targetId]);\n      return successResponse({ followed: true }, 'Followed');"
    
    replace_str = """      await pool.query('INSERT INTO follows (follower_id, following_id) VALUES (?, ?)', [myId, targetId]);
      
      try {
        const [users]: any = await pool.query('SELECT name FROM users WHERE id = ?', [myId]);
        if (users.length > 0) {
          const followerName = users[0].name;
          await sendNotification(targetId, followerName, 'follow', myId, ${followerName} mulai mengikuti Anda);
        }
      } catch (err) {
        console.error('Error sending follow notification', err);
      }
      
      return successResponse({ followed: true }, 'Followed');"""

    code = code.replace(find_str, replace_str)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print("Updated follow route")
else:
    print("Already updated")
