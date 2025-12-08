// lib/database_helper.dart

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // Windows桌面平台需要初始化databaseFactory
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 为桌面平台设置数据库工厂
      databaseFactory = databaseFactoryFfi;
    }
    
    String path;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面平台使用应用数据目录
      final appDocumentsDirectory = await getApplicationDocumentsDirectory();
      path = join(appDocumentsDirectory.path, 'agrisale', 'agriculture_management.db');
      
      // 确保目录存在
      final directory = Directory(dirname(path));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } else {
      // 移动平台使用默认数据库路径
      path = join(await getDatabasesPath(), 'agriculture_management.db');
    }
    
    return await openDatabase(
      path,
      version: 12, // 更新版本号 - 添加自动备份功能字段
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      password TEXT NOT NULL
    )
  ''');
    await db.execute('''
    CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      stock REAL,
      unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋')),
      supplierId INTEGER,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id),
      UNIQUE(userId, name)
    )
  ''');
    await db.execute('''
    CREATE TABLE suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      name TEXT NOT NULL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, name)
    )
  ''');
    await db.execute('''
    CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      name TEXT NOT NULL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, name)
    )
  ''');
    await db.execute('''
    CREATE TABLE employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      name TEXT NOT NULL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      UNIQUE(userId, name)
    )
  ''');
    await db.execute('''
    CREATE TABLE income (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      incomeDate TEXT NOT NULL,
      customerId INTEGER,
      amount REAL NOT NULL,
      discount REAL DEFAULT 0,
      employeeId INTEGER,
      paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id),
      FOREIGN KEY (employeeId) REFERENCES employees (id)
    )
  ''');
    await db.execute('''
    CREATE TABLE remittance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      remittanceDate TEXT NOT NULL,
      supplierId INTEGER,
      amount REAL NOT NULL,
      employeeId INTEGER,
      paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id),
      FOREIGN KEY (employeeId) REFERENCES employees (id)
    )
  ''');
    await db.execute('''
    CREATE TABLE purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      productName TEXT NOT NULL,
      quantity REAL,
      purchaseDate TEXT,
      supplierId INTEGER,
      totalPurchasePrice REAL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (supplierId) REFERENCES suppliers (id)
    )
  ''');

    await db.execute('''
    CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      productName TEXT NOT NULL,
      quantity REAL,
      customerId INTEGER,
      saleDate TEXT,
      totalSalePrice REAL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id)
    )
  ''');

    await db.execute('''
    CREATE TABLE returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL,
      productName TEXT NOT NULL,
      quantity REAL,
      customerId INTEGER,
      returnDate TEXT,
      totalReturnPrice REAL,
      note TEXT,
      FOREIGN KEY (userId) REFERENCES users (id),
      FOREIGN KEY (customerId) REFERENCES customers (id)
    )
  ''');

    // 创建用户设置表，存储每个用户的个人设置
    await db.execute('''
    CREATE TABLE user_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId INTEGER NOT NULL UNIQUE,
      deepseek_api_key TEXT,
      deepseek_model TEXT DEFAULT 'deepseek-chat',
      deepseek_temperature REAL DEFAULT 0.7,
      deepseek_max_tokens INTEGER DEFAULT 2000,
      dark_mode INTEGER DEFAULT 0,
      FOREIGN KEY (userId) REFERENCES users (id)
    )
  ''');

    // 不再插入初始用户数据，让用户自己注册
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('数据库升级: 从版本 $oldVersion 到版本 $newVersion');
    
    // 渐进式升级，根据旧版本逐步升级
    if (oldVersion < 5) {
      // 从版本1-4升级到5：添加employees, income, remittance表
      print('升级到版本5: 添加employees, income, remittance表');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS employees (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          UNIQUE(userId, name)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS income (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          incomeDate TEXT NOT NULL,
          customerId INTEGER,
          amount REAL NOT NULL,
          discount REAL DEFAULT 0,
          employeeId INTEGER,
          paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          FOREIGN KEY (customerId) REFERENCES customers (id),
          FOREIGN KEY (employeeId) REFERENCES employees (id)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS remittance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          remittanceDate TEXT NOT NULL,
          supplierId INTEGER,
          amount REAL NOT NULL,
          employeeId INTEGER,
          paymentMethod TEXT NOT NULL CHECK(paymentMethod IN ('现金', '微信转账', '银行卡')),
          note TEXT,
          FOREIGN KEY (userId) REFERENCES users (id),
          FOREIGN KEY (supplierId) REFERENCES suppliers (id),
          FOREIGN KEY (employeeId) REFERENCES employees (id)
        )
      ''');
    }
    
    if (oldVersion < 11) {
      // 从版本10或更早升级到11：为products表添加supplierId字段
      print('升级到版本11: 为products表添加supplierId字段');
      
      // 检查products表是否已存在supplierId列
      final tableInfo = await db.rawQuery('PRAGMA table_info(products)');
      final hasSupplierIdColumn = tableInfo.any((column) => column['name'] == 'supplierId');
      
      if (!hasSupplierIdColumn) {
        // 添加supplierId列，默认值为NULL（未分配供应商）
        await db.execute('ALTER TABLE products ADD COLUMN supplierId INTEGER');
        print('✓ 已为products表添加supplierId列，现有产品的供应商设为未分配');
      } else {
        print('✓ products表已包含supplierId列，跳过');
      }
    }
    
    if (oldVersion < 12) {
      // 从版本11或更早升级到12：为user_settings表添加自动备份字段
      print('升级到版本12: 为user_settings表添加自动备份字段');
      
      // 检查user_settings表是否已存在自动备份相关列
      final tableInfo = await db.rawQuery('PRAGMA table_info(user_settings)');
      final hasAutoBackupEnabled = tableInfo.any((column) => column['name'] == 'auto_backup_enabled');
      
      if (!hasAutoBackupEnabled) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_enabled INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_interval INTEGER DEFAULT 15');
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_max_count INTEGER DEFAULT 20');
        await db.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT');
        print('✓ 已为user_settings表添加自动备份字段');
      } else {
        print('✓ user_settings表已包含自动备份字段，跳过');
    }
    }
    
    print('数据库升级完成！所有数据已保留。');
  }

  // 获取当前用户ID的辅助方法
  Future<int?> getCurrentUserId(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      columns: ['id'],
      where: 'username = ?',
      whereArgs: [username],
    );
    
    if (result.isNotEmpty) {
      return result.first['id'] as int;
    }
    return null;
  }

  // 创建用户设置记录
  Future<void> createUserSettings(int userId) async {
    final db = await database;
    await db.insert('user_settings', {
      'userId': userId,
    });
  }
}