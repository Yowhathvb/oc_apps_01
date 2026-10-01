import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<String> _getDbPath() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'unknown';
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'local_contacts_$userId.db');
  }

  Future<Database> _initDatabase() async {
    final path = await _getDbPath();
    return await openDatabase(
      path,
      version: 5, // Bumped version to 5 for pinned_chats
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phone_number TEXT UNIQUE NOT NULL,
        saved_name TEXT NOT NULL,
        is_registered INTEGER DEFAULT 0
      )
    ''');
    await _createCallHistoryTable(db);
    await _createPinnedChatsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCallHistoryTable(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE call_history ADD COLUMN type TEXT DEFAULT "audio"');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE contacts ADD COLUMN is_registered INTEGER DEFAULT 0');
    }
    if (oldVersion < 5) {
      await _createPinnedChatsTable(db);
    }
  }

  Future<void> _createCallHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE call_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        other_phone TEXT NOT NULL,
        other_name TEXT,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        type TEXT DEFAULT "audio"
      )
    ''');
  }

  Future<void> _createPinnedChatsTable(Database db) async {
    await db.execute('''
      CREATE TABLE pinned_chats (
        id TEXT PRIMARY KEY,
        pinned_at INTEGER NOT NULL
      )
    ''');
  }

  // Insert or update a contact
  Future<void> saveContact(String phoneNumber, String savedName, {bool isRegistered = false}) async {
    final db = await database;
    await db.insert(
      'contacts',
      {
        'phone_number': phoneNumber, 
        'saved_name': savedName,
        'is_registered': isRegistered ? 1 : 0
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get all contacts
  Future<List<Map<String, dynamic>>> getContacts() async {
    final db = await database;
    return await db.query('contacts', orderBy: 'saved_name ASC');
  }

  // Get a single contact by phone number
  Future<Map<String, dynamic>?> getContactByPhone(String phoneNumber) async {
    final db = await database;
    final results = await db.query(
      'contacts',
      where: 'phone_number = ?',
      whereArgs: [phoneNumber],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  // --- Call History Methods ---

  Future<void> insertCallHistory({
    required String otherPhone,
    String? otherName,
    required String direction,
    required String status,
    required String timestamp,
    String type = 'audio',
  }) async {
    final db = await database;
    await db.insert(
      'call_history',
      {
        'other_phone': otherPhone,
        'other_name': otherName,
        'direction': direction,
        'status': status,
        'timestamp': timestamp,
        'type': type,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCallHistory() async {
    final db = await database;
    return await db.query('call_history', orderBy: 'timestamp DESC');
  }

  Future<void> clearCallHistory() async {
    final db = await database;
    await db.delete('call_history');
  }

  // --- Pinned Chats Methods ---

  Future<void> pinChat(String id) async {
    final db = await database;
    await db.insert(
      'pinned_chats',
      {
        'id': id,
        'pinned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> unpinChat(String id) async {
    final db = await database;
    await db.delete(
      'pinned_chats',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getPinnedChats() async {
    final db = await database;
    return await db.query('pinned_chats', orderBy: 'pinned_at DESC');
  }
}
