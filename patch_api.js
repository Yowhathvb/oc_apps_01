const fs = require('fs');
const path = 'C:/zharfan/project/our-chat/web/oc-platform/app/api/chat/rooms/route.ts';
let c = fs.readFileSync(path, 'utf8');
c = c.replace(
  'u1.name as user_1_name, u1.phone as user_1_phone,',
  'u1.name as user_1_name, u1.phone as user_1_phone, u1.profile_pic as user_1_profile_pic,'
);
c = c.replace(
  'u2.name as user_2_name, u2.phone as user_2_phone,',
  'u2.name as user_2_name, u2.phone as user_2_phone, u2.profile_pic as user_2_profile_pic,'
);
c = c.replace(
  'const otherUserPhone = isUser1 ? room.user_2_phone : room.user_1_phone;',
  'const otherUserPhone = isUser1 ? room.user_2_phone : room.user_1_phone;\n      const otherUserProfilePic = isUser1 ? room.user_2_profile_pic : room.user_1_profile_pic;'
);
c = c.replace(
  "other_user_phone: otherUserPhone || '',",
  "other_user_phone: otherUserPhone || '',\n        other_user_profile_pic: otherUserProfilePic || '',"
);
c = c.replace(
  "other_user_phone: '',",
  "other_user_phone: '',\n        other_user_profile_pic: '',"
);
fs.writeFileSync(path, c, 'utf8');
console.log('Patched API');
