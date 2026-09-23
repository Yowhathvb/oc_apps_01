const fs = require('fs');
const file = '../../web/oc-platform/app/api/calls/[callId]/invite/route.ts';
let c = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

c = c.replace(
  '  const mysqlUser = userRows[0];\n  if (!mysqlUser) return NextResponse.json({ message: "Nomor belum terdaftar" }, { status: 404 });',
  '  const mysqlUser = userRows[0];\n  if (!mysqlUser) {\n    console.log("[INVITE ERROR] User not found in DB");\n    return NextResponse.json({ message: "Nomor belum terdaftar" }, { status: 404 });\n  }'
);

c = c.replace(
  '    console.error(error);\n    return NextResponse.json({ message: "Terjadi kesalahan" }, { status: 500 });',
  '    console.error("[INVITE FATAL ERROR]", error);\n    return NextResponse.json({ message: "Terjadi kesalahan" }, { status: 500 });'
);

c = c.replace(
  '  const caller = getSessionUser(request);',
  '  console.log("[INVITE ROUTE CALLED]");\n  const caller = getSessionUser(request);'
);

fs.writeFileSync(file, c.replace(/\n/g, '\r\n'), 'utf8');
console.log('patched route');
