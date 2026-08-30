const fs = require('fs');
const path = require('path');

const pagePath = path.resolve(__dirname, '../../web/oc-platform/app/chat/[chatRoomId]/page.tsx');
let pageCode = fs.readFileSync(pagePath, 'utf8');

if (!pageCode.includes("socket.on('messages:read'")) {
  const findText = `    socket.on('message', (newMsg: Message) => {`;
  const replaceText = `    socket.on('messages:read', (data: any) => {
      const readerId = data.readerId ? String(data.readerId) : null;
      if (readerId && readerId !== String(userId)) {
        setMessages(prev => prev.map(m => 
          String(m.sender_id) === String(userId) && !m.read ? { ...m, read: true } : m
        ));
      }
    })

    socket.on('message', (newMsg: Message) => {`;

  pageCode = pageCode.replace(findText, replaceText);
  fs.writeFileSync(pagePath, pageCode, 'utf8');
  console.log('Patched page.tsx with messages:read listener.');
} else {
  console.log('page.tsx already has messages:read listener.');
}
