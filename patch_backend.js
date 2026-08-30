const fs = require('fs');
const path = require('path');

const routePath = path.resolve(__dirname, '../../web/oc-platform/app/api/chat/[chatRoomId]/messages/route.ts');
let routeCode = fs.readFileSync(routePath, 'utf8');

if (!routeCode.includes('/messages-read')) {
  // We'll replace the await pool.query UPDATE messages with the new logic
  const regex = /await\s+pool\.query\(\s*`UPDATE\s+messages\s+SET\s+is_read\s*=\s*1\s+WHERE\s+chat_room_id\s*=\s*\?\s+AND\s+sender_id\s*!=\s*\?\s+AND\s+is_read\s*=\s*0`,\s*\[chatRoomId,\s*userId\]\s*\);/m;

  const replaceText = `const [updateResult]: any = await pool.query(
      \`UPDATE messages 
       SET is_read = 1 
       WHERE chat_room_id = ? AND sender_id != ? AND is_read = 0\`,
      [chatRoomId, userId]
    );

    if (updateResult && updateResult.affectedRows > 0) {
      try {
        const socketPort = process.env.SOCKET_SERVER_PORT || 4000;
        await fetch(\`http://localhost:\${socketPort}/messages-read\`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ roomId: chatRoomId, userId }),
        });
      } catch (e) {
        console.error('Error emitting messages:read:', e);
      }
    }`;

  if (regex.test(routeCode)) {
    routeCode = routeCode.replace(regex, replaceText);
    fs.writeFileSync(routePath, routeCode, 'utf8');
    console.log('Patched messages route.ts via Regex');
  } else {
    console.log('Regex did not match in messages route.ts');
  }
} else {
  console.log('messages route.ts already patched');
}
