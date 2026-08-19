import sys

path = r'e:\zharfann\project\our-chat\oc-platform\app\api\v1\notifications\route.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

find_str = """    const limit = Number(request.nextUrl.searchParams.get('limit') || 30);
    const offset = Number(request.nextUrl.searchParams.get('offset') || 0);

    const [rows]: any = await pool.query(
      'SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?',
      [userId, limit, offset]
    );"""

replace_str = """    try {
      await pool.query('ALTER TABLE notifications ADD COLUMN sender_id INT DEFAULT NULL');
    } catch(e) {
      // Column might already exist
    }

    const limit = Number(request.nextUrl.searchParams.get('limit') || 30);
    const offset = Number(request.nextUrl.searchParams.get('offset') || 0);

    const [rows]: any = await pool.query(
      SELECT n.*, 
             u.name as sender_name, u.username as sender_username, u.avatar as sender_avatar,
             p.media_url as post_media_url, p.media_type as post_media_type
      FROM notifications n
      LEFT JOIN users u ON n.sender_id = u.id
      LEFT JOIN posts p ON n.reference_id = p.id AND n.type IN ('like', 'comment', 'mention')
      WHERE n.user_id = ? 
      ORDER BY n.created_at DESC 
      LIMIT ? OFFSET ?
    , [userId, limit, offset]);"""

code = code.replace(find_str, replace_str)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated notifications GET route")
