import sys

path = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\posts\[postId]\comments\route.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

if 'sendNotification' not in code:
    code = code.replace(
        "import jwt from 'jsonwebtoken';",
        "import jwt from 'jsonwebtoken';\nimport { sendNotification } from '@/lib/notification-helper';"
    )
    
    find_str = "    return NextResponse.json({ comment: newComment[0] });"
    
    replace_str = """    // Notification triggers
    try {
      const commenterName = newComment[0].authorName;
      const [posts]: any = await pool.query('SELECT user_id FROM posts WHERE id = ?', [postId]);
      if (posts.length > 0) {
        const authorId = posts[0].user_id;
        
        // 1. Notify Post Author
        if (authorId !== userId) {
          await sendNotification(authorId, commenterName, 'comment', postId, ${commenterName} mengomentari postingan Anda);
        }
        
        // 2. Parse Mentions and Notify Tagged Users
        // Mention format: @username
        const mentionRegex = /@([a-zA-Z0-9_]+)/g;
        let match;
        const mentionedUsernames = [];
        while ((match = mentionRegex.exec(text)) !== null) {
          mentionedUsernames.push(match[1]);
        }
        
        if (mentionedUsernames.length > 0) {
          // unique usernames
          const uniqueUsernames = [...new Set(mentionedUsernames)];
          const placeholders = uniqueUsernames.map(() => '?').join(',');
          const [mentionedUsers]: any = await pool.query(SELECT id, username FROM users WHERE username IN (), uniqueUsernames);
          
          for (const u of mentionedUsers) {
            // Don't notify if they tagged themselves or if the tagged user is the post author (they already got comment notif)
            if (u.id !== userId && u.id !== authorId) {
              await sendNotification(u.id, commenterName, 'comment', postId, ${commenterName} menyebut Anda di komentarnya);
            }
          }
        }
      }
    } catch(err) {
      console.error('Error sending comment notifications', err);
    }

    return NextResponse.json({ comment: newComment[0] });"""

    code = code.replace(find_str, replace_str)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(code)
    print("Updated comment route")
else:
    print("Already updated")
