import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../../../domain/entities/entities.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;

  AppDatabase._();
  factory AppDatabase() => _instance ??= AppDatabase._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'idtlabelqc.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE work_orders (
        id TEXT PRIMARY KEY,
        order_number TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        product_id TEXT,
        product_name TEXT,
        machine_id TEXT,
        machine_name TEXT,
        operator_id TEXT NOT NULL,
        operator_name TEXT NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        expected_symbology TEXT,
        master_pattern_id TEXT,
        observations TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE master_patterns (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        product_id TEXT,
        job_reference TEXT NOT NULL,
        symbology TEXT NOT NULL,
        min_acceptable_grade TEXT NOT NULL,
        decoded_value TEXT NOT NULL,
        reference_image BLOB NOT NULL,
        parameters_json TEXT NOT NULL,
        overall_grade TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        created_by TEXT NOT NULL,
        observations TEXT,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE barcode_verifications (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        symbology TEXT NOT NULL,
        decoded_value TEXT NOT NULL,
        standard TEXT NOT NULL,
        overall_grade TEXT NOT NULL,
        overall_grade_numeric REAL NOT NULL,
        captured_image BLOB,
        capture_mode TEXT NOT NULL,
        work_order_id TEXT,
        checkpoint_id TEXT,
        master_pattern_id TEXT,
        operator_id TEXT,
        parameters_json TEXT NOT NULL,
        pattern_comparison_json TEXT,
        recommendations_json TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE operator_users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'operator',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        last_login INTEGER
      )
    ''');

    // Seed admin user
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('operator_users', {
      'id': 'admin-001',
      'name': 'Administrador',
      'username': 'admin',
      'password_hash': base64Encode(utf8.encode('admin123')),
      'role': 'admin',
      'is_active': 1,
      'created_at': now,
    });
  }

  // ── Verifications ──
  Future<String> insertVerification(BarcodeVerification v) async {
    final db = await database;
    await db.insert('barcode_verifications', {
      'id': v.id,
      'timestamp': v.timestamp.millisecondsSinceEpoch,
      'symbology': v.symbology.name,
      'decoded_value': v.decodedValue,
      'standard': v.standard,
      'overall_grade': v.overallGrade.letter,
      'overall_grade_numeric': v.overallGrade.numeric,
      'captured_image': v.capturedImage,
      'capture_mode': v.captureMode.name,
      'work_order_id': v.workOrderId,
      'checkpoint_id': v.checkpointId,
      'master_pattern_id': v.masterPatternId,
      'operator_id': v.operatorId,
      'parameters_json': jsonEncode(v.parameters.toJson()),
      'pattern_comparison_json': v.patternComparison != null
          ? jsonEncode(v.patternComparison!.toJson()) : null,
      'recommendations_json': jsonEncode(v.recommendations.map((r) => r.toJson()).toList()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return v.id;
  }

  Future<List<Map<String, dynamic>>> getRecentVerifications({int limit = 50}) async {
    final db = await database;
    return db.query('barcode_verifications',
        orderBy: 'timestamp DESC', limit: limit);
  }

  // ── Work Orders ──
  Future<void> insertWorkOrder(WorkOrder wo) async {
    final db = await database;
    await db.insert('work_orders', {
      'id': wo.id,
      'order_number': wo.orderNumber,
      'customer_id': wo.customerId,
      'customer_name': wo.customerName,
      'product_id': wo.productId,
      'product_name': wo.productName,
      'machine_id': wo.machineId,
      'machine_name': wo.machineName,
      'operator_id': wo.operatorId,
      'operator_name': wo.operatorName,
      'start_date': wo.startDate.millisecondsSinceEpoch,
      'status': 'active',
      'expected_symbology': wo.expectedSymbology?.name,
      'master_pattern_id': wo.masterPatternId,
      'observations': wo.observations,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getActiveWorkOrders() async {
    final db = await database;
    return db.query('work_orders',
        where: "status IN ('active', 'draft', 'paused')",
        orderBy: 'start_date DESC');
  }

  Future<Map<String, dynamic>?> getWorkOrderById(String id) async {
    final db = await database;
    final rows = await db.query('work_orders', where: 'id = ?', whereArgs: [id]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> updateWorkOrderStatus(String id, WorkOrderStatus status) async {
    final db = await database;
    await db.update(
      'work_orders',
      {
        'status': status.name,
        if (status == WorkOrderStatus.completed)
          'end_date': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Patterns ──
  Future<void> insertPattern(MasterPattern pattern) async {
    final db = await database;
    await db.insert('master_patterns', {
      'id': pattern.id,
      'customer_id': pattern.customerId,
      'product_id': pattern.productId,
      'job_reference': pattern.jobReference,
      'symbology': pattern.symbology.name,
      'min_acceptable_grade': pattern.minAcceptableGrade.letter,
      'decoded_value': pattern.decodedValue,
      'reference_image': pattern.referenceImage,
      'parameters_json': jsonEncode(pattern.referenceParameters.toJson()),
      'overall_grade': pattern.overallGrade.letter,
      'created_at': pattern.createdAt.millisecondsSinceEpoch,
      'created_by': pattern.createdBy,
      'observations': pattern.observations,
      'is_active': 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllPatterns() async {
    final db = await database;
    return db.query('master_patterns',
        where: 'is_active = 1', orderBy: 'created_at DESC');
  }

  // ── Auth ──
  Future<Map<String, dynamic>?> authenticate(String username, String password) async {
    final db = await database;
    final hash = base64Encode(utf8.encode(password));
    final rows = await db.query(
      'operator_users',
      where: 'username = ? AND password_hash = ? AND is_active = 1',
      whereArgs: [username, hash],
    );
    if (rows.isNotEmpty) {
      await db.update('operator_users',
          {'last_login': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: [rows.first['id']]);
      return rows.first;
    }
    return null;
  }

  // ── Dashboard ──
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;
    final rows = await db.query('barcode_verifications');
    final counts = <String, int>{};
    double gradeSum = 0;
    for (final row in rows) {
      final g = row['overall_grade'] as String;
      counts[g] = (counts[g] ?? 0) + 1;
      gradeSum += (row['overall_grade_numeric'] as num).toDouble();
    }
    final total = rows.length;
    return {
      'total': total,
      'gradeA': counts['A'] ?? 0,
      'gradeB': counts['B'] ?? 0,
      'gradeC': counts['C'] ?? 0,
      'gradeD': counts['D'] ?? 0,
      'gradeF': counts['F'] ?? 0,
      'mean': total > 0 ? gradeSum / total : 0.0,
      'okRate': total > 0
          ? ((counts['A'] ?? 0) + (counts['B'] ?? 0) + (counts['C'] ?? 0)) / total
          : 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> getGradeTrend({int days = 14}) async {
    final db = await database;
    final from = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    return db.query('barcode_verifications',
        where: 'timestamp >= ?',
        whereArgs: [from],
        orderBy: 'timestamp ASC');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
