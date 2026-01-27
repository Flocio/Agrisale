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
    
    final db = await openDatabase(
      path,
      version: 13, // 更新版本号 - 添加新单位（件、瓶）
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    // 无论版本如何，都检查并修复缺失的列（确保数据库结构完整）
    await _ensureDatabaseSchema(db);
    
    return db;
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
      unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋', '件', '瓶')),
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
      auto_backup_enabled INTEGER DEFAULT 0,
      auto_backup_interval INTEGER DEFAULT 15,
      auto_backup_max_count INTEGER DEFAULT 20,
      last_backup_time TEXT,
      auto_backup_on_launch INTEGER DEFAULT 0,
      auto_backup_on_exit INTEGER DEFAULT 0,
      auto_backup_next_time TEXT,
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
    
    if (oldVersion < 13) {
      // 从版本12或更早升级到13：更新products表的unit CHECK约束，添加'件'和'瓶'
      print('升级到版本13: 更新products表的单位约束，添加"件"和"瓶"');
      
      // SQLite不支持直接修改CHECK约束，需要重建表
      // 1. 创建新表（带新的CHECK约束）
      await db.execute('''
        CREATE TABLE products_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          name TEXT NOT NULL,
          description TEXT,
          stock REAL,
          unit TEXT NOT NULL CHECK(unit IN ('斤', '公斤', '袋', '件', '瓶')),
          supplierId INTEGER,
          FOREIGN KEY (userId) REFERENCES users (id),
          FOREIGN KEY (supplierId) REFERENCES suppliers (id),
          UNIQUE(userId, name)
        )
      ''');
      
      // 2. 复制数据到新表
      await db.execute('''
        INSERT INTO products_new (id, userId, name, description, stock, unit, supplierId)
        SELECT id, userId, name, description, stock, unit, supplierId FROM products
      ''');
      
      // 3. 删除旧表
      await db.execute('DROP TABLE products');
      
      // 4. 重命名新表
      await db.execute('ALTER TABLE products_new RENAME TO products');
      
      print('✓ 已更新products表的单位约束，现支持：斤、公斤、袋、件、瓶');
    }
    
    // 无论版本如何，都检查并添加缺失的自动备份字段（修复可能的不完整升级）
    // 这样可以确保即使升级过程中出现问题，也能修复
    final tableInfo = await db.rawQuery('PRAGMA table_info(user_settings)');
    final columnNames = tableInfo.map((col) => col['name'] as String).toList();
    
    bool hasChanges = false;
    
    if (!columnNames.contains('auto_backup_enabled')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_enabled INTEGER DEFAULT 0');
      print('✓ 已添加 auto_backup_enabled 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_interval')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_interval INTEGER DEFAULT 15');
      print('✓ 已添加 auto_backup_interval 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_max_count')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_max_count INTEGER DEFAULT 20');
      print('✓ 已添加 auto_backup_max_count 列');
      hasChanges = true;
    }
    if (!columnNames.contains('last_backup_time')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT');
      print('✓ 已添加 last_backup_time 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_on_launch')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_on_launch INTEGER DEFAULT 0');
      print('✓ 已添加 auto_backup_on_launch 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_on_exit')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_on_exit INTEGER DEFAULT 0');
      print('✓ 已添加 auto_backup_on_exit 列');
      hasChanges = true;
    }
    if (!columnNames.contains('auto_backup_next_time')) {
      await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_next_time TEXT');
      print('✓ 已添加 auto_backup_next_time 列');
      hasChanges = true;
    }
    
    if (!hasChanges && oldVersion < 12) {
      print('✓ user_settings表已包含所有自动备份字段');
    }
    
    print('数据库升级完成！所有数据已保留。');
  }

  // 确保数据库结构完整（检查和修复缺失的列）
  // 这个方法在每次打开数据库时都会被调用，确保即使升级过程中出现问题也能修复
  Future<void> _ensureDatabaseSchema(Database db) async {
    try {
      // 检查 user_settings 表是否存在
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='user_settings'"
      );
      
      if (tables.isEmpty) {
        // 表不存在，说明是新数据库，会在 _onCreate 中创建
        return;
      }
      
      // 检查并添加缺失的列
      final tableInfo = await db.rawQuery('PRAGMA table_info(user_settings)');
      final columnNames = tableInfo.map((col) => col['name'] as String).toList();
      
      bool hasChanges = false;
      
      if (!columnNames.contains('auto_backup_enabled')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_enabled INTEGER DEFAULT 0');
        print('✓ [修复] 已添加 auto_backup_enabled 列');
        hasChanges = true;
      }
      if (!columnNames.contains('auto_backup_interval')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_interval INTEGER DEFAULT 15');
        print('✓ [修复] 已添加 auto_backup_interval 列');
        hasChanges = true;
      }
      if (!columnNames.contains('auto_backup_max_count')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_max_count INTEGER DEFAULT 20');
        print('✓ [修复] 已添加 auto_backup_max_count 列');
        hasChanges = true;
      }
      if (!columnNames.contains('last_backup_time')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT');
        print('✓ [修复] 已添加 last_backup_time 列');
        hasChanges = true;
      }
      if (!columnNames.contains('auto_backup_on_launch')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_on_launch INTEGER DEFAULT 0');
        print('✓ [修复] 已添加 auto_backup_on_launch 列');
        hasChanges = true;
      }
      if (!columnNames.contains('auto_backup_on_exit')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_on_exit INTEGER DEFAULT 0');
        print('✓ [修复] 已添加 auto_backup_on_exit 列');
        hasChanges = true;
      }
      if (!columnNames.contains('auto_backup_next_time')) {
        await db.execute('ALTER TABLE user_settings ADD COLUMN auto_backup_next_time TEXT');
        print('✓ [修复] 已添加 auto_backup_next_time 列');
        hasChanges = true;
      }
      
      if (hasChanges) {
        print('✓ 数据库结构修复完成');
      }
    } catch (e) {
      print('检查数据库结构时出错: $e');
      // 不抛出异常，避免影响数据库打开
    }
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

  /// 删除用户账号及其所有关联数据
  /// 
  /// 在事务中删除用户的所有数据，包括：
  /// - 用户设置 (user_settings)
  /// - 产品 (products)
  /// - 供应商 (suppliers)
  /// - 客户 (customers)
  /// - 员工 (employees)
  /// - 采购记录 (purchases)
  /// - 销售记录 (sales)
  /// - 退货记录 (returns)
  /// - 进账记录 (income)
  /// - 汇款记录 (remittance)
  /// - 用户账号 (users)
  /// 
  /// 返回删除的数据统计
  Future<Map<String, int>> deleteUserAccount(int userId) async {
    final db = await database;
    final Map<String, int> deletedCounts = {};
    
    await db.transaction((txn) async {
      // 按照正确的顺序删除（先删除有外键依赖的表）
      
      // 1. 删除用户设置
      deletedCounts['user_settings'] = await txn.delete(
        'user_settings',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      // 2. 删除交易记录（这些表引用了 products, suppliers, customers, employees）
      deletedCounts['purchases'] = await txn.delete(
        'purchases',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['sales'] = await txn.delete(
        'sales',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['returns'] = await txn.delete(
        'returns',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['income'] = await txn.delete(
        'income',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['remittance'] = await txn.delete(
        'remittance',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      // 3. 删除基础数据（products 引用了 suppliers）
      deletedCounts['products'] = await txn.delete(
        'products',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['suppliers'] = await txn.delete(
        'suppliers',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['customers'] = await txn.delete(
        'customers',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      deletedCounts['employees'] = await txn.delete(
        'employees',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      // 4. 最后删除用户账号本身
      deletedCounts['users'] = await txn.delete(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
    
    return deletedCounts;
  }

  /// 验证用户密码
  Future<bool> verifyUserPassword(String username, String password) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    return result.isNotEmpty;
  }
}