import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Database? _db;

Future<Database> getDatabase() async {
  if (_db != null) return _db!;
  _db = await openChatDataBase();
  return _db!;
}

Future<int> getUnreadBroadcastCount() async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    columns: ['id'],
    where: 'is_broadcast = 1 AND is_me = 0 AND is_read = 0',
  );
  return rows.length;
}

// returns the count of all peer's unread messages combined
Future<int> getTotalUnreadPrivateCount() async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    columns: ['id'],
    where: 'is_broadcast = 0 AND is_me = 0 AND is_read = 0',
  );
  return rows.length;
}

// returns unread message count from a single peer
Future<int> getUnreadPrivateCountForPeer(String peerMac) async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    columns: ['id'],
    where: 'peer_mac = ? AND is_broadcast = 0 AND is_me = 0 AND is_read = 0',
    whereArgs: [peerMac],
  );
  return rows.length;
}

Future<void> markBroadcastMessagesAsRead() async {
  final db = await getDatabase();
  await db.update('messages', {
    'is_read': 1,
  }, where: 'is_broadcast = 1 AND is_me = 0 AND is_read = 0');
}

Future<void> markPrivateMessagesAsRead(String peerMac) async {
  final db = await getDatabase();
  await db.update(
    'messages',
    {'is_read': 1},
    where: 'peer_mac = ? AND is_broadcast = 0 AND is_me = 0 AND is_read = 0',
    whereArgs: [peerMac],
  );
}

Future<int?> getLastMessageTimeFromPeer(String peerMac) async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    columns: ['timestamp'],
    where: 'peer_mac = ? AND is_broadcast = 0',
    whereArgs: [peerMac],
    orderBy: 'timestamp DESC',
    limit: 1,
  );

  if (rows.isEmpty) return null;

  return rows.first['timestamp'] as int?;
}

Future<void> updateLastMessageStatus(String targetMac, String newStatus) async {
  final db = await getDatabase();

  final rows = await db.query(
    'messages',
    columns: ['id'],
    where: 'peer_mac = ? AND is_me = 1 AND is_broadcast = 0',
    whereArgs: [targetMac],
    orderBy: 'timestamp DESC',
    limit: 1,
  );

  if (rows.isNotEmpty) {
    await db.update(
      'messages',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
  }
}

Future<void> InsertMessage(DbMessage msg) async {
  final db = await getDatabase();
  await db.insert("messages", msg.toMap());
}

Future<List<DbMessage>> getBroadcastMessage() async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    where: 'is_broadcast = 1',
    orderBy: 'timestamp ASC',
  );
  return rows.map((row) => DbMessage.fromMap(row)).toList();
}

Future<List<DbMessage>> getPrivateMessages(String peerMac) async {
  final db = await getDatabase();
  final rows = await db.query(
    'messages',
    where: 'peer_mac = ? AND is_broadcast = 0',
    whereArgs: [peerMac],
    orderBy: 'timestamp ASC',
  );
  return rows.map((row) => DbMessage.fromMap(row)).toList();
}

class DbMessage {
  final int? id;
  final String? peerMac;
  final String senderName;
  final String content;
  final bool isMe;
  final int timestamp;
  final bool isBroadcast;
  String? status;
  bool isRead;

  DbMessage({
    this.id,
    this.peerMac,
    required this.senderName,
    required this.content,
    required this.isMe,
    required this.timestamp,
    required this.isBroadcast,
    this.status,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'peer_mac': peerMac,
      'sender_name': senderName,
      'content': content,
      'is_me': isMe ? 1 : 0,
      'timestamp': timestamp,
      'is_broadcast': isBroadcast ? 1 : 0,
      'status': status,
      'is_read': isRead ? 1 : 0,
    };
  }

  DbMessage.fromMap(Map<String, dynamic> map)
    : id = map['id'] as int?,
      peerMac = map['peer_mac'] as String?,
      senderName = (map['sender_name'] as String?) ?? '',
      content = (map['content'] as String?) ?? '',
      isMe = ((map['is_me'] as int?) ?? 0) == 1,
      timestamp = (map['timestamp'] as int?) ?? 0,
      isBroadcast = ((map['is_broadcast'] as int?) ?? 0) == 1,
      status = map['status'] as String?,
      isRead = ((map['is_read'] as int?) ?? 0) == 1;
}

Future<Database> openChatDataBase() async {
  final dbPath = await getDatabasesPath();
  final path = join(dbPath, "chat.db");

  return openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
      CREATE TABLE peers (
        mac TEXT PRIMARY KEY,
        name TEXT,
        color_hex TEXT,
        rssi TEXT,
        last_seen INTEGER
      )
      ''');

      await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        peer_mac TEXT,
        sender_name TEXT,
        content TEXT,
        is_me INTEGER,
        timestamp INTEGER,
        is_broadcast INTEGER,
        status TEXT,
        is_read INTEGER DEFAULT 0
      )
      ''');
    },
  );
}

Future<void> savePeer(DbPeer peer) async {
  final db = await getDatabase();
  await db.insert(
    'peers',
    peer.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<List<DbPeer>> getSavedPeers() async {
  final db = await getDatabase();
  final rows = await db.query('peers', orderBy: 'last_seen DESC');
  return rows.map((row) => DbPeer.fromMap(row)).toList();
}

class DbPeer {
  final String mac;
  final String name;
  final String? colorHex;
  final String? rssi;
  final int? lastSeen;

  DbPeer({
    required this.mac,
    required this.name,
    this.colorHex,
    this.rssi,
    this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'mac': mac,
      'name': name,
      'color_hex': colorHex,
      'rssi': rssi,
      'last_seen': lastSeen,
    };
  }

  DbPeer.fromMap(Map<String, dynamic> map)
    : mac = map['mac'] as String,
      name = (map['name'] as String?) ?? '',
      colorHex = map['color_hex'] as String?,
      rssi = map['rssi'] as String?,
      lastSeen = map['last_seen'] as int?;
}
