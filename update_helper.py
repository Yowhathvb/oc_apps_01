import sys

path = r'e:\zharfann\project\our-chat\oc-platform\lib\notification-helper.ts'

with open(path, 'r', encoding='utf-8') as f:
    code = f.read()

find_str = """export async function sendNotification(
  userId: number,
  senderName: string,
  type: 'like' | 'comment' | 'follow',
  referenceId: number,
  message: string
) {
  try {
    // Save to DB
    await pool.query(
      'INSERT INTO notifications (user_id, type, reference_id, message) VALUES (?, ?, ?, ?)',
      [userId, type, referenceId, message]
    );"""

replace_str = """export async function sendNotification(
  userId: number,
  senderName: string,
  type: 'like' | 'comment' | 'follow' | 'mention',
  referenceId: number,
  message: string,
  senderId?: number
) {
  try {
    // Save to DB
    await pool.query(
      'INSERT INTO notifications (user_id, type, reference_id, message, sender_id) VALUES (?, ?, ?, ?, ?)',
      [userId, type, referenceId, message, senderId || null]
    );"""

code = code.replace(find_str, replace_str)

with open(path, 'w', encoding='utf-8') as f:
    f.write(code)
print("Updated notification-helper")
