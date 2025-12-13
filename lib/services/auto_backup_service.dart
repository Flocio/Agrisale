import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../utils/app_version.dart';

class AutoBackupService {
  static final AutoBackupService _instance = AutoBackupService._internal();
  factory AutoBackupService() => _instance;
  AutoBackupService._internal();

  Timer? _autoBackupTimer;
  bool _isBackupRunning = false;
  DateTime? _nextBackupTime; // 记录下次备份时间

  // 启动自动备份
  Future<void> startAutoBackup(int intervalMinutes) async {
    await stopAutoBackup(); // 先停止现有的定时器
    
    final interval = Duration(minutes: intervalMinutes);
    print('启动自动备份服务，间隔: $intervalMinutes 分钟');
    
    // 设置下次备份时间
    _nextBackupTime = DateTime.now().add(interval);
    
    _autoBackupTimer = Timer.periodic(interval, (timer) async {
      await performAutoBackup();
      // 每次备份后更新下次备份时间
      _nextBackupTime = DateTime.now().add(interval);
    });
  }

  // 停止自动备份
  Future<void> stopAutoBackup() async {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    _nextBackupTime = null; // 清除下次备份时间
    print('停止自动备份服务');
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
      
      // 更新最后备份时间
      await db.update(
        'user_settings',
        {'last_backup_time': DateTime.now().toIso8601String()},
        where: 'userId = ?',
        whereArgs: [userId],
      );
      
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
      baseDir = Directory('/storage/emulated/0/Android/data/com.yikang.agrisale/files');
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

  // 获取所有备份文件列表
  Future<List<Map<String, dynamic>>> getBackupList() async {
    try {
      final backupDir = await getAutoBackupDirectory();
      final files = backupDir.listSync()
        .where((f) => f is File && f.path.endsWith('.json'))
        .map((f) => f as File)
        .toList();
      
      // 按修改时间排序（新 → 旧）
      files.sort((a, b) => 
        b.lastModifiedSync().compareTo(a.lastModifiedSync())
      );
      
      // 构建备份信息列表
      List<Map<String, dynamic>> backupList = [];
      for (var file in files) {
        final stat = await file.stat();
        backupList.add({
          'path': file.path,
          'fileName': file.path.split('/').last,
          'modifiedTime': stat.modified,
          'size': stat.size,
        });
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

  // 删除所有备份
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
  Future<bool> restoreBackup(String filePath, int userId) async {
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
      final db = await DatabaseHelper().database;

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

      print('恢复备份成功');
      return true;
    } catch (e) {
      print('恢复备份失败: $e');
      return false;
    }
  }
}

