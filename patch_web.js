const fs = require('fs');
const path = require('path');

const pagePath = path.resolve(__dirname, '../../web/oc-platform/app/chat/[chatRoomId]/page.tsx');
let pageCode = fs.readFileSync(pagePath, 'utf8');

if (!pageCode.includes("fetch(`/api/chat/${targetRoomId}/messages?limit=1`)")) {
  const findRegex = /\/\/\s*Scroll\s*to\s*bottom\s*setTimeout\(\(\)\s*=>\s*messagesEndRef\.current\?\.scrollIntoView\(\{\s*behavior:\s*'smooth'\s*\}\),\s*100\);\s*\}/m;

  const replaceText = `// Scroll to bottom
      setTimeout(() => messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' }), 100);

      // Mark as read immediately if it's from the other user
      if (String(newMsg.sender_id) !== String(userId)) {
        const targetRoomId = actualRoomId || chatRoomId;
        fetch(\`/api/chat/\${targetRoomId}/messages?limit=1\`).catch(console.error);
      }
    }`;

  if (findRegex.test(pageCode)) {
    pageCode = pageCode.replace(findRegex, replaceText);
    fs.writeFileSync(pagePath, pageCode, 'utf8');
    console.log('Patched page.tsx successfully.');
  } else {
    console.log('Could not find exact text via regex in page.tsx');
  }
} else {
  console.log('page.tsx already patched.');
}
