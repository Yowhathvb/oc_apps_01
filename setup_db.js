const mysql = require('mysql2/promise');
require('dotenv').config({ path: 'e:/zharfann/project/our-chat/oc-platform/.env' });

async function run() {
  const pool = mysql.createPool({
    host: process.env.MYSQL_HOST || 'localhost',
    user: process.env.MYSQL_USER || 'root',
    password: process.env.MYSQL_PASSWORD || '',
    database: process.env.MYSQL_DATABASE || 'our_chat',
    port: process.env.MYSQL_PORT || 3306,
  });

  const query = 'CREATE TABLE IF NOT EXISTS notifications (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, type VARCHAR(50) NOT NULL, reference_id INT, message TEXT NOT NULL, is_read BOOLEAN DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE);';

  try {
    await pool.query(query);
    console.log('Notifications table checked/created successfully.');
  } catch (err) {
    console.error('Error creating notifications table:', err);
  } finally {
    process.exit(0);
  }
}
run();
