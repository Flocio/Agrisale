import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../utils/app_version.dart';
import '../services/audit_log_service.dart';
import '../models/audit_log.dart';

class AutoBackupService {
  static final AutoBackupService _instance = AutoBackupService._internal();
  factory AutoBackupService() => _instance;
  AutoBackupService._internal();

  Timer? _autoBackupTimer;
  bool _isBackupRunning = false;
  DateTime? _nextBackupTime; // 记录下次备份时间

  // 将下次备份时间持久化到 user_settings.auto_backup_next_time 中
  Future<void> _saveNextBackupTime(DateTime? time) async {
    _nextBackupTime = time;

    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      if (username == null) return;

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId == null) return;

      await db.update(
        'user_settings',
        {'auto_backup_next_time': time?.toIso8601String()},
        where: 'userId = ?',
        whereArgs: [userId],
      );
    } catch (e) {
      // 持久化失败不影响备份逻辑
      print('保存下次自动备份时间失败（不影响备份）: $e');
    }
  }

  // 从 user_settings.auto_backup_next_time 中恢复下次备份时间
  Future<DateTime?> _loadNextBackupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      if (username == null) return null;

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId == null) return null;

      final result = await db.query(
        'user_settings',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      if (result.isEmpty) return null;

      final nextTimeStr = result.first['auto_backup_next_time'] as String?;
      if (nextTimeStr == null) return null;

      return DateTime.tryParse(nextTimeStr);
    } catch (e) {
      print('加载下次自动备份时间失败（不影响备份）: $e');
      return null;
    }
  }

  void _schedulePeriodicBackups(Duration interval) {
    final now = DateTime.now();
    final nextTime = now.add(interval);
    _saveNextBackupTime(nextTime);

    _autoBackupTimer = Timer.periodic(interval, (timer) async {
      await performAutoBackup();
      final next = DateTime.now().add(interval);
      _saveNextBackupTime(next);
    });
  }

  /// 使用新的间隔重新启动自动备份调度（从当前时间开始，不使用上次记录的下次备份时间）
  Future<void> restartWithNewInterval(int intervalMinutes) async {
    await stopAutoBackup();
    final interval = Duration(minutes: intervalMinutes);
    print('使用新间隔重新启动自动备份服务，间隔: $intervalMinutes 分钟');
    _schedulePeriodicBackups(interval);
  }

  // 启动自动备份
  Future<void> startAutoBackup(int intervalMinutes) async {
    await stopAutoBackup(); // 先停止现有的定时器
    
    final interval = Duration(minutes: intervalMinutes);
    print('启动自动备份服务，间隔: $intervalMinutes 分钟');
    
    // 尝试从上次记录中恢复下次备份时间，以保证跨重启/重新登录的连贯性
    final storedNextTime = await _loadNextBackupTime();
    final now = DateTime.now();

    if (storedNextTime != null && storedNextTime.isAfter(now)) {
      // 还有剩余时间，先等待到 storedNextTime，再进入周期性备份
      final initialDelay = storedNextTime.difference(now);
      _nextBackupTime = storedNextTime;
      _autoBackupTimer = Timer(initialDelay, () async {
      await performAutoBackup();
        _schedulePeriodicBackups(interval);
    });
    } else {
      // 没有记录或已过期，从现在开始按间隔计时
      _schedulePeriodicBackups(interval);
    }
  }

  // 停止自动备份
  Future<void> stopAutoBackup() async {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    // 仅清除内存中的时间，不清除数据库中的记录，以便下次登录时还能知道原来的计划时间
    _nextBackupTime = null;
    print('停止自动备份服务');
  }

  /// 如果开启了“退出时自动备份”，在退出账号或关闭应用前调用一次
  Future<void> backupOnExitIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      if (username == null) return;

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId == null) return;

      final result = await db.query(
        'user_settings',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      if (result.isEmpty) return;

      final settings = result.first;
      final backupOnExit = (settings['auto_backup_on_exit'] as int?) == 1;
      if (!backupOnExit) return;

      await performAutoBackup();
    } catch (e) {
      // 退出前自动备份失败不影响退出或关闭应用
      print('退出前自动备份失败（不影响退出）: $e');
    }
  }
  
  // 获取距离下一次备份的剩余时间（秒）
  int? getSecondsUntilNextBackup() {
    if (_nextBackupTime == null || _autoBackupTimer == null) {
      return null;
    }
    final now = DateTime.now();
    final difference = _nextBackupTime!.difference(now);
    return difference.inSeconds > 0 ? difference.inSeconds : 0;
  }
  
  // 格式化剩余时间为易读格式
  String formatTimeUntilNextBackup() {
    final seconds = getSecondsUntilNextBackup();
    if (seconds == null) {
      return '未启动';
    }
    
    if (seconds == 0) {
      return '即将备份...';
    }
    
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    
    if (hours > 0) {
      return '$hours 小时 $minutes 分钟 $secs 秒';
    } else if (minutes > 0) {
      return '$minutes 分钟 $secs 秒';
    } else {
      return '$secs 秒';
    }
  }

  // 执行一次备份
  Future<bool> performAutoBackup() async {
    if (_isBackupRunning) {
      print('备份正在进行中，跳过本次');
      return false;
    }

    _isBackupRunning = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        print('未登录，跳过自动备份');
        _isBackupRunning = false;
        return false;
      }

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId == null) {
        print('用户信息错误，跳过自动备份');
        _isBackupRunning = false;
        return false;
      }

      // 获取当前用户的所有数据
      final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
      final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
      final customers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
      final employees = await db.query('employees', where: 'userId = ?', whereArgs: [userId]);
      final purchases = await db.query('purchases', where: 'userId = ?', whereArgs: [userId]);
      final sales = await db.query('sales', where: 'userId = ?', whereArgs: [userId]);
      final returns = await db.query('returns', where: 'userId = ?', whereArgs: [userId]);
      final income = await db.query('income', where: 'userId = ?', whereArgs: [userId]);
      final remittance = await db.query('remittance', where: 'userId = ?', whereArgs: [userId]);
      
      // 构建备份数据
      final backupData = {
        'backupInfo': {
          'type': 'auto_backup',
          'username': username,
          'backupTime': DateTime.now().toIso8601String(),
          'version': AppVersion.version,
        },
        'data': {
          'products': products,
          'suppliers': suppliers,
          'customers': customers,
          'employees': employees,
          'purchases': purchases,
          'sales': sales,
          'returns': returns,
          'income': income,
          'remittance': remittance,
        }
      };

      // 转换为JSON
      final jsonString = jsonEncode(backupData);
      
      // 生成文件名
      final now = DateTime.now();
      final fileName = 'auto_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.json';
      
      // 获取备份目录并保存
      final backupDir = await getAutoBackupDirectory();
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonString);
      
      print('自动备份成功: $fileName');
      
      // 更新最后备份时间（如果列存在）
      try {
        // 先检查列是否存在
        final tableInfo = await db.rawQuery('PRAGMA table_info(user_settings)');
        final hasLastBackupTime = tableInfo.any((column) => column['name'] == 'last_backup_time');
        
        if (hasLastBackupTime) {
          await db.update(
            'user_settings',
            {'last_backup_time': DateTime.now().toIso8601String()},
            where: 'userId = ?',
            whereArgs: [userId],
          );
        } else {
          // 如果列不存在，先添加列
          await db.execute('ALTER TABLE user_settings ADD COLUMN last_backup_time TEXT');
      await db.update(
        'user_settings',
        {'last_backup_time': DateTime.now().toIso8601String()},
        where: 'userId = ?',
        whereArgs: [userId],
      );
        }
      } catch (e) {
        // 更新备份时间失败不影响备份成功
        print('更新备份时间失败（不影响备份）: $e');
      }
      
      // 清理旧备份
      await _cleanOldBackups();
      
      _isBackupRunning = false;
      return true;
      
    } catch (e) {
      print('自动备份失败: $e');
      _isBackupRunning = false;
      return false;
    }
  }

  // 获取备份目录
  Future<Directory> getAutoBackupDirectory() async {
    Directory baseDir;
    
    if (Platform.isAndroid) {
      // Android: 使用外部存储
      baseDir = Directory('/storage/emulated/0/Android/data/org.drflo.agrisale/files');
      if (!await baseDir.exists()) {
        // 如果外部存储不可用，使用应用文档目录
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else if (Platform.isIOS) {
      // iOS: 使用 Documents 目录
      baseDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // 桌面平台: 使用 Application Support
      baseDir = await getApplicationSupportDirectory();
    } else {
      // 其他平台：后备方案
      baseDir = await getApplicationDocumentsDirectory();
    }
    
    final autoBackupDir = Directory('${baseDir.path}/AutoBackups');
    if (!await autoBackupDir.exists()) {
      await autoBackupDir.create(recursive: true);
    }
    
    return autoBackupDir;
  }

  // 获取当前用户的备份文件列表（只返回属于当前登录用户的备份）
  Future<List<Map<String, dynamic>>> getBackupList() async {
    try {
      // 获取当前登录用户名
      final prefs = await SharedPreferences.getInstance();
      final currentUsername = prefs.getString('current_username');
      if (currentUsername == null) {
        print('未登录，无法获取备份列表');
        return [];
      }

      final backupDir = await getAutoBackupDirectory();
      final files = backupDir.listSync()
        .where((f) => f is File && f.path.endsWith('.json'))
        .map((f) => f as File)
        .toList();
      
      // 按修改时间排序（新 → 旧）
      files.sort((a, b) => 
        b.lastModifiedSync().compareTo(a.lastModifiedSync())
      );
      
      // 构建备份信息列表，只包含当前用户的备份
      List<Map<String, dynamic>> backupList = [];
      for (var file in files) {
        try {
          final jsonString = await file.readAsString();
          final Map<String, dynamic> backupData = jsonDecode(jsonString);
          final backupUsername = backupData['backupInfo']?['username'] as String?;
          
          // 只添加属于当前用户的备份
          if (backupUsername == currentUsername) {
            final stat = await file.stat();
            backupList.add({
              'path': file.path,
              'fileName': file.path.split('/').last,
              'modifiedTime': stat.modified,
              'size': stat.size,
              'username': backupUsername,
            });
          }
        } catch (e) {
          // 单个文件读取失败，跳过
          print('读取备份文件失败 ${file.path}: $e');
        }
      }
      
      return backupList;
    } catch (e) {
      print('获取备份列表失败: $e');
      return [];
    }
  }

  // 删除指定备份
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        print('删除备份成功: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      print('删除备份失败: $e');
      return false;
    }
  }

  // 删除当前用户的所有备份（getBackupList 已经只返回当前用户的备份）
  Future<int> deleteAllBackups() async {
    try {
      final backupList = await getBackupList();
      int deletedCount = 0;
      
      for (var backup in backupList) {
        if (await deleteBackup(backup['path'])) {
          deletedCount++;
        }
      }
      
      return deletedCount;
    } catch (e) {
      print('删除所有备份失败: $e');
      return 0;
    }
  }

  // 删除指定用户的所有备份文件
  Future<int> deleteBackupsForUser(String username) async {
    try {
      final backupList = await getBackupList();
      int deletedCount = 0;
      
      for (var backup in backupList) {
        final filePath = backup['path'] as String;
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final jsonString = await file.readAsString();
            final Map<String, dynamic> backupData = jsonDecode(jsonString);
            
            // 检查备份文件中的用户名是否匹配
            final backupUsername = backupData['backupInfo']?['username'] as String?;
            if (backupUsername == username) {
              if (await deleteBackup(filePath)) {
                deletedCount++;
              }
            }
          }
        } catch (e) {
          // 单个文件读取失败不影响继续处理其他文件
          print('检查备份文件失败 $filePath: $e');
        }
      }
      
      print('删除用户 $username 的备份文件: $deletedCount 个');
      return deletedCount;
    } catch (e) {
      print('删除用户备份文件失败: $e');
      return 0;
    }
  }

  // 清理旧备份（保留指定数量）
  Future<void> _cleanOldBackups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      if (username == null) return;

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId == null) return;

      // 获取最大保留数量设置
      final settings = await db.query(
        'user_settings',
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
      if (settings.isEmpty) return;
      
      final maxCount = (settings.first['auto_backup_max_count'] as int?) ?? 20;
      
      final backupList = await getBackupList();
      
      // 如果备份数量超过最大值，删除旧的
      if (backupList.length > maxCount) {
        for (var i = maxCount; i < backupList.length; i++) {
          await deleteBackup(backupList[i]['path']);
        }
        print('清理旧备份: 删除了 ${backupList.length - maxCount} 个');
      }
    } catch (e) {
      print('清理旧备份失败: $e');
    }
  }

  // 恢复备份
  Future<bool> restoreBackup(String filePath, int userId, {String? username}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('备份文件不存在');
        return false;
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> importData = jsonDecode(jsonString);
      
      // 验证数据格式
      if (!importData.containsKey('backupInfo') || !importData.containsKey('data')) {
        print('备份文件格式错误');
        return false;
      }

      final data = importData['data'] as Map<String, dynamic>;
      final backupInfo = importData['backupInfo'] as Map<String, dynamic>;
      final backupUsername = backupInfo['username'] ?? '未知';
      final backupTime = backupInfo['backupTime'] ?? '未知';
      final backupVersion = backupInfo['version'] ?? '未知';
      
      // 获取数据量统计（将要导入的数据）
      final supplierCount = (data['suppliers'] as List?)?.length ?? 0;
      final customerCount = (data['customers'] as List?)?.length ?? 0;
      final productCount = (data['products'] as List?)?.length ?? 0;
      final employeeCount = (data['employees'] as List?)?.length ?? 0;
      final purchaseCount = (data['purchases'] as List?)?.length ?? 0;
      final saleCount = (data['sales'] as List?)?.length ?? 0;
      final returnCount = (data['returns'] as List?)?.length ?? 0;
      final incomeCount = (data['income'] as List?)?.length ?? 0;
      final remittanceCount = (data['remittance'] as List?)?.length ?? 0;
      final db = await DatabaseHelper().database;

      // 在删除前统计现有数据数量（用于日志记录）
      final beforeSupplierCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM suppliers WHERE userId = ?', [userId])) ?? 0;
      final beforeCustomerCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM customers WHERE userId = ?', [userId])) ?? 0;
      final beforeEmployeeCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM employees WHERE userId = ?', [userId])) ?? 0;
      final beforeProductCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM products WHERE userId = ?', [userId])) ?? 0;
      final beforePurchaseCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM purchases WHERE userId = ?', [userId])) ?? 0;
      final beforeSaleCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM sales WHERE userId = ?', [userId])) ?? 0;
      final beforeReturnCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM returns WHERE userId = ?', [userId])) ?? 0;
      final beforeIncomeCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM income WHERE userId = ?', [userId])) ?? 0;
      final beforeRemittanceCount = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM remittance WHERE userId = ?', [userId])) ?? 0;

      // 在事务中执行恢复
      await db.transaction((txn) async {
        // 删除当前用户的业务数据（不包括 user_settings）
        await txn.delete('products', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('suppliers', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('customers', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('employees', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('purchases', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('sales', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('returns', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('income', where: 'userId = ?', whereArgs: [userId]);
        await txn.delete('remittance', where: 'userId = ?', whereArgs: [userId]);

        // 创建ID映射表
        Map<int, int> supplierIdMap = {};
        Map<int, int> customerIdMap = {};
        Map<int, int> productIdMap = {};
        Map<int, int> employeeIdMap = {};

        // 恢复suppliers数据
        if (data['suppliers'] != null) {
          for (var supplier in data['suppliers']) {
            final supplierData = Map<String, dynamic>.from(supplier);
            final originalId = supplierData['id'] as int;
            supplierData.remove('id');
            supplierData['userId'] = userId;
            final newId = await txn.insert('suppliers', supplierData);
            supplierIdMap[originalId] = newId;
          }
        }

        // 恢复customers数据
        if (data['customers'] != null) {
          for (var customer in data['customers']) {
            final customerData = Map<String, dynamic>.from(customer);
            final originalId = customerData['id'] as int;
            customerData.remove('id');
            customerData['userId'] = userId;
            final newId = await txn.insert('customers', customerData);
            customerIdMap[originalId] = newId;
          }
        }

        // 恢复employees数据
        if (data['employees'] != null) {
          for (var employee in data['employees']) {
            final employeeData = Map<String, dynamic>.from(employee);
            final originalId = employeeData['id'] as int;
            employeeData.remove('id');
            employeeData['userId'] = userId;
            final newId = await txn.insert('employees', employeeData);
            employeeIdMap[originalId] = newId;
          }
        }

        // 恢复products数据
        if (data['products'] != null) {
          for (var product in data['products']) {
            final productData = Map<String, dynamic>.from(product);
            final originalId = productData['id'] as int;
            productData.remove('id');
            productData['userId'] = userId;
            
            // 更新supplierId关联关系
            if (productData['supplierId'] != null) {
              final originalSupplierId = productData['supplierId'] as int;
              if (supplierIdMap.containsKey(originalSupplierId)) {
                productData['supplierId'] = supplierIdMap[originalSupplierId];
              } else {
                productData['supplierId'] = null;
              }
            }
            
            final newId = await txn.insert('products', productData);
            productIdMap[originalId] = newId;
          }
        }

        // 恢复purchases数据
        if (data['purchases'] != null) {
          for (var purchase in data['purchases']) {
            final purchaseData = Map<String, dynamic>.from(purchase);
            purchaseData.remove('id');
            purchaseData['userId'] = userId;
            
            if (purchaseData['supplierId'] != null) {
              final originalSupplierId = purchaseData['supplierId'] as int;
              if (supplierIdMap.containsKey(originalSupplierId)) {
                purchaseData['supplierId'] = supplierIdMap[originalSupplierId];
              } else {
                purchaseData['supplierId'] = null;
              }
            }
            
            await txn.insert('purchases', purchaseData);
          }
        }

        // 恢复sales数据
        if (data['sales'] != null) {
          for (var sale in data['sales']) {
            final saleData = Map<String, dynamic>.from(sale);
            saleData.remove('id');
            saleData['userId'] = userId;
            
            if (saleData['customerId'] != null) {
              final originalCustomerId = saleData['customerId'] as int;
              if (customerIdMap.containsKey(originalCustomerId)) {
                saleData['customerId'] = customerIdMap[originalCustomerId];
              } else {
                saleData['customerId'] = null;
              }
            }
            
            await txn.insert('sales', saleData);
          }
        }

        // 恢复returns数据
        if (data['returns'] != null) {
          for (var returnItem in data['returns']) {
            final returnData = Map<String, dynamic>.from(returnItem);
            returnData.remove('id');
            returnData['userId'] = userId;
            
            if (returnData['customerId'] != null) {
              final originalCustomerId = returnData['customerId'] as int;
              if (customerIdMap.containsKey(originalCustomerId)) {
                returnData['customerId'] = customerIdMap[originalCustomerId];
              } else {
                returnData['customerId'] = null;
              }
            }
            
            await txn.insert('returns', returnData);
          }
        }

        // 恢复income数据
        if (data['income'] != null) {
          for (var incomeItem in data['income']) {
            final incomeData = Map<String, dynamic>.from(incomeItem);
            incomeData.remove('id');
            incomeData['userId'] = userId;
            
            if (incomeData['customerId'] != null) {
              final originalCustomerId = incomeData['customerId'] as int;
              if (customerIdMap.containsKey(originalCustomerId)) {
                incomeData['customerId'] = customerIdMap[originalCustomerId];
              } else {
                incomeData['customerId'] = null;
              }
            }
            
            if (incomeData['employeeId'] != null) {
              final originalEmployeeId = incomeData['employeeId'] as int;
              if (employeeIdMap.containsKey(originalEmployeeId)) {
                incomeData['employeeId'] = employeeIdMap[originalEmployeeId];
              } else {
                incomeData['employeeId'] = null;
              }
            }
            
            await txn.insert('income', incomeData);
          }
        }

        // 恢复remittance数据
        if (data['remittance'] != null) {
          for (var remittanceItem in data['remittance']) {
            final remittanceData = Map<String, dynamic>.from(remittanceItem);
            remittanceData.remove('id');
            remittanceData['userId'] = userId;
            
            if (remittanceData['supplierId'] != null) {
              final originalSupplierId = remittanceData['supplierId'] as int;
              if (supplierIdMap.containsKey(originalSupplierId)) {
                remittanceData['supplierId'] = supplierIdMap[originalSupplierId];
              } else {
                remittanceData['supplierId'] = null;
              }
            }
            
            if (remittanceData['employeeId'] != null) {
              final originalEmployeeId = remittanceData['employeeId'] as int;
              if (employeeIdMap.containsKey(originalEmployeeId)) {
                remittanceData['employeeId'] = employeeIdMap[originalEmployeeId];
              } else {
                remittanceData['employeeId'] = null;
              }
            }
            
            await txn.insert('remittance', remittanceData);
          }
        }
      });
      
      // 记录操作日志
      try {
        // 如果没有传入 username，尝试从 SharedPreferences 获取
        String? finalUsername = username;
        if (finalUsername == null) {
          final prefs = await SharedPreferences.getInstance();
          finalUsername = prefs.getString('current_username') ?? '未知用户';
        }
        
        await AuditLogService().logCover(
          userId: userId,
          username: finalUsername,
          entityName: '备份恢复',
          oldData: {
            'operation': '自动备份恢复',
            'source_user': backupUsername,
            'source_time': backupTime,
            'source_version': backupVersion,
            'before_counts': {
              'suppliers': beforeSupplierCount,
              'customers': beforeCustomerCount,
              'employees': beforeEmployeeCount,
              'products': beforeProductCount,
              'purchases': beforePurchaseCount,
              'sales': beforeSaleCount,
              'returns': beforeReturnCount,
              'income': beforeIncomeCount,
              'remittance': beforeRemittanceCount,
            },
          },
          newData: {
            'import_counts': {
              'suppliers': supplierCount,
              'customers': customerCount,
              'employees': employeeCount,
              'products': productCount,
              'purchases': purchaseCount,
              'sales': saleCount,
              'returns': returnCount,
              'income': incomeCount,
              'remittance': remittanceCount,
            },
            'total_count': supplierCount + customerCount + employeeCount + 
                          productCount + purchaseCount + saleCount + 
                          returnCount + incomeCount + remittanceCount,
          },
          note: '恢复自动备份（覆盖）：供应商 $supplierCount，客户 $customerCount，员工 $employeeCount，产品 $productCount，采购 $purchaseCount，销售 $saleCount，退货 $returnCount，进账 $incomeCount，汇款 $remittanceCount',
        );
      } catch (e) {
        print('记录备份恢复日志失败: $e');
        // 日志记录失败不影响业务
      }

      print('恢复备份成功');
      return true;
    } catch (e) {
      print('恢复备份失败: $e');
      return false;
    }
  }
}

