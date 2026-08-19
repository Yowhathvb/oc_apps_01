const fs = require('fs');
const path = 'e:/zharfann/project/our-chat/oc-platform/app/api/v1/posts/[postId]/like/route.ts';
let code = fs.readFileSync(path, 'utf8');

if (!code.includes('sendNotification')) {
  code = code.replace(
    "import { cookies } from 'next/headers';",
    "import { cookies } from 'next/headers';\nimport { sendNotification } from '@/lib/notification-helper';"
  );
  
  const likeLogic = 
      await pool.query('INSERT INTO post_likes (post_id, user_id) VALUES (?, ?)', [postId, userId]);
      await pool.query('UPDATE posts SET likes_count = likes_count + 1 WHERE id = ?', [postId]);
      
      // Get author of the post and user name
      const [posts]: any = await pool.query('SELECT user_id FROM posts WHERE id = ?', [postId]);
      const [users]: any = await pool.query('SELECT name FROM users WHERE id = ?', [userId]);
      if (posts.length > 0 && users.length > 0) {
        const authorId = posts[0].user_id;
        const likerName = users[0].name;
        if (authorId !== userId) {
          await sendNotification(authorId, likerName, 'like', parseInt(postId), \\ menyukai postingan Anda\);
        }
      }
      
      return NextResponse.json({ success: true, message: 'Liked' });
;
  
  code = code.replace(
    /await pool\.query\('INSERT INTO post_likes.*?return NextResponse\.json\(\{ success: true, message: 'Liked' \}\);/s,
    likeLogic.trim()
  );
  
  fs.writeFileSync(path, code);
  console.log('like/route.ts updated');
} else {
  console.log('Already updated');
}
