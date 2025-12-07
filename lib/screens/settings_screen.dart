import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'dart:io';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _username;
  
  // DeepSeek 模型参数
  double _temperature = 0.7;
  int _maxTokens = 2000;
  String _selectedModel = 'deepseek-chat';
  String _apiKey = '';
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  
  final List<String> _availableModels = [
    'deepseek-chat',
    'deepseek-coder',
    'deepseek-lite'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUsername();
    _loadModelSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId != null) {
        final result = await db.query(
          'user_settings',
          where: 'userId = ?',
          whereArgs: [userId],
        );
        
        if (result.isEmpty) {
          // 如果没有设置记录，创建一个
          await DatabaseHelper().createUserSettings(userId);
        }
      }
    }
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('current_username') ?? '未登录';
    });
  }
  
  Future<void> _loadModelSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId != null) {
        final result = await db.query(
          'user_settings',
          where: 'userId = ?',
          whereArgs: [userId],
        );
        
        if (result.isNotEmpty) {
          final settings = result.first;
          setState(() {
            _temperature = (settings['deepseek_temperature'] as double?) ?? 0.7;
            _maxTokens = (settings['deepseek_max_tokens'] as int?) ?? 2000;
            _selectedModel = (settings['deepseek_model'] as String?) ?? 'deepseek-chat';
            _apiKey = (settings['deepseek_api_key'] as String?) ?? '';
            _apiKeyController.text = _apiKey;
          });
        } else {
          // 如果没有设置记录，创建一个
          await DatabaseHelper().createUserSettings(userId);
        }
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId != null) {
        // 保存设置到数据库（移除深色模式设置）
        await db.update(
          'user_settings',
          {
            'deepseek_api_key': _apiKeyController.text.trim(),
            'deepseek_model': _selectedModel,
            'deepseek_temperature': _temperature,
            'deepseek_max_tokens': _maxTokens,
          },
          where: 'userId = ?',
          whereArgs: [userId],
        );
      }
    }
  }

  // 自动保存设置（不显示提示）
  Future<void> _autoSaveSettings() async {
    await _saveSettings();
  }

  // 手动保存设置（显示提示）
  Future<void> _manualSaveSettings() async {
    await _saveSettings();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('设置已保存')),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final db = await DatabaseHelper().database;
    
    // 验证当前密码
    final results = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [_username, _currentPasswordController.text],
    );

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('当前密码不正确')),
      );
      return;
    }

    // 更新密码
    await db.update(
      'users',
      {'password': _newPasswordController.text},
      where: 'username = ?',
      whereArgs: [_username],
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('密码已更新')),
    );

    // 清空输入框
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  // 导出全部数据功能
  Future<void> _exportAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
    ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请先登录')),
        );
        return;
      }

      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在导出数据...'),
            ],
          ),
        ),
      );

      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId == null) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('用户信息错误')),
        );
        return;
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
      final userSettings = await db.query('user_settings', where: 'userId = ?', whereArgs: [userId]);
      
      // 构建导出数据
      final exportData = {
        'exportInfo': {
          'username': username,
          'exportTime': DateTime.now().toIso8601String(),
          'version': '2.1.0', // 更新版本号 - 支持合并模式和冲突检测
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
          'userSettings': userSettings,
        }
      };

      // 转换为JSON
      final jsonString = jsonEncode(exportData);
      
      // 生成文件名
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final fileName = '${username}_农资数据_$timestamp.json';

      if (Platform.isMacOS || Platform.isWindows) {
        // macOS 和 Windows: 使用 file_picker 让用户选择保存位置
        String? selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: '保存数据备份',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        
        if (selectedPath != null) {
          final file = File(selectedPath);
          await file.writeAsString(jsonString);
          
          Navigator.of(context).pop(); // 关闭加载对话框
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('数据导出成功: $selectedPath'),
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          Navigator.of(context).pop(); // 关闭加载对话框
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已取消导出')),
          );
        }
        return;
      }

      String path;
      if (Platform.isAndroid) {
        // 请求存储权限
        if (await Permission.storage.request().isGranted) {
          final directory = Directory('/storage/emulated/0/Download');
          path = '${directory.path}/$fileName';
        } else {
          Navigator.of(context).pop(); // 关闭加载对话框
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('存储权限被拒绝')),
          );
          return;
        }
      } else if (Platform.isIOS) {
        final directory = await getApplicationDocumentsDirectory();
        path = '${directory.path}/$fileName';
      } else {
        // 其他平台使用应用文档目录作为后备方案
        final directory = await getApplicationDocumentsDirectory();
        path = '${directory.path}/$fileName';
      }

      // 写入文件
      final file = File(path);
      await file.writeAsString(jsonString);

      Navigator.of(context).pop(); // 关闭加载对话框

      if (Platform.isIOS) {
        // iOS 让用户手动选择存储位置
        await Share.shareFiles([file.path], text: '农资管理系统数据备份文件');
      } else {
        // Android 直接存入 Download 目录，并提示用户
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据导出成功: $path'),
            duration: Duration(seconds: 3),
          ),
        );
      }

    } catch (e) {
      Navigator.of(context).pop(); // 关闭加载对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  // 数据恢复功能
  Future<void> _importData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请先登录')),
    );
        return;
      }

      // 选择文件
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        
        // 解析JSON数据
        final Map<String, dynamic> importData = jsonDecode(jsonString);
        
        // 验证数据格式
        if (!importData.containsKey('exportInfo') || !importData.containsKey('data')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文件格式错误，请选择正确的备份文件')),
          );
          return;
        }

        // 检查数据来源和冲突风险
        final backupUsername = importData['exportInfo']['username'] ?? '未知';
        final backupVersion = importData['exportInfo']['version'] ?? '未知';
        final isFromDifferentUser = backupUsername != username;
        
        // 检查数据量，用于冲突风险评估
        final data = importData['data'] as Map<String, dynamic>;
        final backupSupplierCount = (data['suppliers'] as List?)?.length ?? 0;
        final backupCustomerCount = (data['customers'] as List?)?.length ?? 0;
        final backupProductCount = (data['products'] as List?)?.length ?? 0;
        final backupEmployeeCount = (data['employees'] as List?)?.length ?? 0;
        
        // 获取当前用户的数据量
        final db = await DatabaseHelper().database;
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('用户信息错误')),
          );
          return;
        }
        
        final currentSuppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        final currentCustomers = await db.query('customers', where: 'userId = ?', whereArgs: [userId]);
        final currentProducts = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        final currentEmployees = await db.query('employees', where: 'userId = ?', whereArgs: [userId]);
        
        // 检测潜在的名称冲突（仅在合并模式下提示）
        int potentialConflicts = 0;
        List<String> conflictDetails = [];
        
        if (backupSupplierCount > 0 && currentSuppliers.isNotEmpty) {
          final backupSupplierNames = (data['suppliers'] as List).map((s) => s['name'] as String).toSet();
          final currentSupplierNames = currentSuppliers.map((s) => s['name'] as String).toSet();
          final conflictingSuppliers = backupSupplierNames.intersection(currentSupplierNames);
          if (conflictingSuppliers.isNotEmpty) {
            potentialConflicts += conflictingSuppliers.length;
            conflictDetails.add('供应商: ${conflictingSuppliers.length}个重名');
          }
        }
        
        if (backupCustomerCount > 0 && currentCustomers.isNotEmpty) {
          final backupCustomerNames = (data['customers'] as List).map((c) => c['name'] as String).toSet();
          final currentCustomerNames = currentCustomers.map((c) => c['name'] as String).toSet();
          final conflictingCustomers = backupCustomerNames.intersection(currentCustomerNames);
          if (conflictingCustomers.isNotEmpty) {
            potentialConflicts += conflictingCustomers.length;
            conflictDetails.add('客户: ${conflictingCustomers.length}个重名');
          }
        }
        
        if (backupProductCount > 0 && currentProducts.isNotEmpty) {
          final backupProductNames = (data['products'] as List).map((p) => p['name'] as String).toSet();
          final currentProductNames = currentProducts.map((p) => p['name'] as String).toSet();
          final conflictingProducts = backupProductNames.intersection(currentProductNames);
          if (conflictingProducts.isNotEmpty) {
            potentialConflicts += conflictingProducts.length;
            conflictDetails.add('产品: ${conflictingProducts.length}个重名');
          }
        }
        
        if (backupEmployeeCount > 0 && currentEmployees.isNotEmpty) {
          final backupEmployeeNames = (data['employees'] as List).map((e) => e['name'] as String).toSet();
          final currentEmployeeNames = currentEmployees.map((e) => e['name'] as String).toSet();
          final conflictingEmployees = backupEmployeeNames.intersection(currentEmployeeNames);
          if (conflictingEmployees.isNotEmpty) {
            potentialConflicts += conflictingEmployees.length;
            conflictDetails.add('员工: ${conflictingEmployees.length}个重名');
          }
        }

        // 显示确认对话框
        String? importMode; // 'overwrite' 或 'merge'
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('确认数据导入'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 数据来源信息
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📦 备份信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          SizedBox(height: 4),
                          Text('来源用户: $backupUsername', style: TextStyle(fontSize: 12)),
                          Text('导出时间: ${importData['exportInfo']['exportTime'] ?? '未知'}', style: TextStyle(fontSize: 12)),
                          Text('数据版本: $backupVersion', style: TextStyle(fontSize: 12)),
                          SizedBox(height: 4),
                          Text('供应商: $backupSupplierCount | 客户: $backupCustomerCount', style: TextStyle(fontSize: 12)),
                          Text('产品: $backupProductCount | 员工: $backupEmployeeCount', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    
                    // 不同用户警告
                    if (isFromDifferentUser) ...[
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange[700], size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '警告：此备份来自不同用户（$backupUsername），请谨慎操作！',
                                style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // 冲突检测结果（仅在有冲突时显示）
                    if (potentialConflicts > 0) ...[
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error, color: Colors.red[700], size: 16),
                                SizedBox(width: 8),
                                Text(
                                  '检测到 $potentialConflicts 个潜在冲突',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red[900]),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            ...conflictDetails.map((detail) => Padding(
                              padding: EdgeInsets.only(left: 24, top: 2),
                              child: Text('• $detail', style: TextStyle(fontSize: 11, color: Colors.red[800])),
                            )),
                            SizedBox(height: 4),
                            Padding(
                              padding: EdgeInsets.only(left: 24),
                              child: Text(
                                '合并模式将跳过重名项，覆盖模式将删除所有现有数据',
                                style: TextStyle(fontSize: 11, color: Colors.red[700], fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    SizedBox(height: 16),
                    Text(
                      '请选择导入模式：',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    RadioListTile<String>(
                      title: Text('覆盖模式'),
                      subtitle: Text('删除当前所有数据，替换为备份数据（不可撤销）', style: TextStyle(fontSize: 12, color: Colors.red)),
                      value: 'overwrite',
                      groupValue: importMode,
                      onChanged: (value) {
                        setDialogState(() {
                          importMode = value;
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: Text('合并模式'),
                      subtitle: Text(
                        potentialConflicts > 0 
                          ? '保留当前数据，新增备份数据（将跳过${potentialConflicts}个重名项）' 
                          : '保留当前数据，新增备份中的数据',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                      value: 'merge',
                      groupValue: importMode,
                      onChanged: (value) {
                        setDialogState(() {
                          importMode = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('取消'),
                ),
                ElevatedButton(
                  onPressed: importMode == null ? null : () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: importMode == 'overwrite' ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(importMode == 'overwrite' ? '确认覆盖' : importMode == 'merge' ? '确认合并' : '请选择模式'),
                ),
              ],
            ),
          ),
        );

        if (confirm != true || importMode == null) return;

        // 显示加载对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text(importMode == 'overwrite' ? '正在覆盖数据...' : '正在合并数据...'),
              ],
            ),
          ),
        );

        // db 和 userId 已经在上面获取过了，直接使用

        // 在事务中执行数据恢复
        await db.transaction((txn) async {
          // 如果是覆盖模式，删除当前用户的所有数据
          if (importMode == 'overwrite') {
            await txn.delete('products', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('suppliers', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('customers', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('employees', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('purchases', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('sales', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('returns', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('income', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('remittance', where: 'userId = ?', whereArgs: [userId]);
            await txn.delete('user_settings', where: 'userId = ?', whereArgs: [userId]);
          }

          // 创建ID映射表来保持关联关系（旧ID -> 新ID）
          Map<int, int> supplierIdMap = {};
          Map<int, int> customerIdMap = {};
          Map<int, int> productIdMap = {};
          Map<int, int> employeeIdMap = {};

          // 恢复suppliers数据（让数据库自动生成新ID）
          if (data['suppliers'] != null) {
            for (var supplier in data['suppliers']) {
              final supplierData = Map<String, dynamic>.from(supplier);
              final originalId = supplierData['id'] as int;
              supplierData.remove('id'); // 移除原始ID，让数据库自动生成新ID
              supplierData['userId'] = userId;
              
              // 合并模式：检查是否已存在同名供应商
              if (importMode == 'merge') {
                final existing = await txn.query(
                  'suppliers',
                  where: 'userId = ? AND name = ?',
                  whereArgs: [userId, supplierData['name']],
                );
                if (existing.isNotEmpty) {
                  // 已存在同名供应商，使用现有ID
                  supplierIdMap[originalId] = existing.first['id'] as int;
                  continue; // 跳过插入
                }
              }
              
              // 插入并获取新生成的ID
              final newId = await txn.insert('suppliers', supplierData);
              supplierIdMap[originalId] = newId; // 建立映射关系
            }
          }

          // 恢复customers数据（让数据库自动生成新ID）
          if (data['customers'] != null) {
            for (var customer in data['customers']) {
              final customerData = Map<String, dynamic>.from(customer);
              final originalId = customerData['id'] as int;
              customerData.remove('id'); // 移除原始ID
              customerData['userId'] = userId;
              
              // 合并模式：检查是否已存在同名客户
              if (importMode == 'merge') {
                final existing = await txn.query(
                  'customers',
                  where: 'userId = ? AND name = ?',
                  whereArgs: [userId, customerData['name']],
                );
                if (existing.isNotEmpty) {
                  customerIdMap[originalId] = existing.first['id'] as int;
                  continue;
                }
              }
              
              // 插入并获取新生成的ID
              final newId = await txn.insert('customers', customerData);
              customerIdMap[originalId] = newId; // 建立映射关系
            }
          }

          // 恢复employees数据（让数据库自动生成新ID）
          if (data['employees'] != null) {
            for (var employee in data['employees']) {
              final employeeData = Map<String, dynamic>.from(employee);
              final originalId = employeeData['id'] as int;
              employeeData.remove('id'); // 移除原始ID
              employeeData['userId'] = userId;
              
              // 合并模式：检查是否已存在同名员工
              if (importMode == 'merge') {
                final existing = await txn.query(
                  'employees',
                  where: 'userId = ? AND name = ?',
                  whereArgs: [userId, employeeData['name']],
                );
                if (existing.isNotEmpty) {
                  employeeIdMap[originalId] = existing.first['id'] as int;
                  continue;
                }
              }
              
              // 插入并获取新生成的ID
              final newId = await txn.insert('employees', employeeData);
              employeeIdMap[originalId] = newId; // 建立映射关系
            }
          }

          // 恢复products数据（让数据库自动生成新ID）
          if (data['products'] != null) {
            for (var product in data['products']) {
              final productData = Map<String, dynamic>.from(product);
              final originalId = productData['id'] as int;
              productData.remove('id'); // 移除原始ID
              productData['userId'] = userId;
              
              // 更新supplierId关联关系（关键修复！）
              if (productData['supplierId'] != null) {
                final originalSupplierId = productData['supplierId'] as int;
                if (supplierIdMap.containsKey(originalSupplierId)) {
                  productData['supplierId'] = supplierIdMap[originalSupplierId];
                } else {
                  // 如果找不到映射关系，设为null
                  productData['supplierId'] = null;
                }
              }
              
              // 合并模式：检查是否已存在同名产品
              if (importMode == 'merge') {
                final existing = await txn.query(
                  'products',
                  where: 'userId = ? AND name = ?',
                  whereArgs: [userId, productData['name']],
                );
                if (existing.isNotEmpty) {
                  productIdMap[originalId] = existing.first['id'] as int;
                  continue; // 跳过插入，保留现有产品的库存和供应商信息
                }
              }
              
              // 插入并获取新生成的ID
              final newId = await txn.insert('products', productData);
              productIdMap[originalId] = newId; // 建立映射关系
            }
          }

          // 恢复purchases数据（使用映射后的supplierID）
          if (data['purchases'] != null) {
            for (var purchase in data['purchases']) {
              final purchaseData = Map<String, dynamic>.from(purchase);
              purchaseData.remove('id'); // 移除原始ID，让数据库自动生成
              purchaseData['userId'] = userId;
              
              // 更新supplierId关联关系
              if (purchaseData['supplierId'] != null) {
                final originalSupplierId = purchaseData['supplierId'] as int;
                if (supplierIdMap.containsKey(originalSupplierId)) {
                  purchaseData['supplierId'] = supplierIdMap[originalSupplierId];
                } else {
                  // 如果找不到映射关系，设为null
                  purchaseData['supplierId'] = null;
                }
              }
              
              await txn.insert('purchases', purchaseData);
            }
          }

          // 恢复sales数据（使用映射后的customerID）
          if (data['sales'] != null) {
            for (var sale in data['sales']) {
              final saleData = Map<String, dynamic>.from(sale);
              saleData.remove('id'); // 移除原始ID
              saleData['userId'] = userId;
              
              // 更新customerId关联关系
              if (saleData['customerId'] != null) {
                final originalCustomerId = saleData['customerId'] as int;
                if (customerIdMap.containsKey(originalCustomerId)) {
                  saleData['customerId'] = customerIdMap[originalCustomerId];
                } else {
                  // 如果找不到映射关系，设为null
                  saleData['customerId'] = null;
                }
              }
              
              await txn.insert('sales', saleData);
            }
          }

          // 恢复returns数据（使用映射后的customerID）
          if (data['returns'] != null) {
            for (var returnItem in data['returns']) {
              final returnData = Map<String, dynamic>.from(returnItem);
              returnData.remove('id'); // 移除原始ID
              returnData['userId'] = userId;
              
              // 更新customerId关联关系
              if (returnData['customerId'] != null) {
                final originalCustomerId = returnData['customerId'] as int;
                if (customerIdMap.containsKey(originalCustomerId)) {
                  returnData['customerId'] = customerIdMap[originalCustomerId];
                } else {
                  // 如果找不到映射关系，设为null
                  returnData['customerId'] = null;
                }
              }
              
              await txn.insert('returns', returnData);
            }
          }

          // 恢复income数据（进账记录）
          if (data['income'] != null) {
            for (var incomeItem in data['income']) {
              final incomeData = Map<String, dynamic>.from(incomeItem);
              incomeData.remove('id'); // 移除原始ID
              incomeData['userId'] = userId;
              
              // 更新customerId关联关系
              if (incomeData['customerId'] != null) {
                final originalCustomerId = incomeData['customerId'] as int;
                if (customerIdMap.containsKey(originalCustomerId)) {
                  incomeData['customerId'] = customerIdMap[originalCustomerId];
                } else {
                  incomeData['customerId'] = null;
                }
              }
              
              // 更新employeeId关联关系
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

          // 恢复remittance数据（汇款记录）
          if (data['remittance'] != null) {
            for (var remittanceItem in data['remittance']) {
              final remittanceData = Map<String, dynamic>.from(remittanceItem);
              remittanceData.remove('id'); // 移除原始ID
              remittanceData['userId'] = userId;
              
              // 更新supplierId关联关系
              if (remittanceData['supplierId'] != null) {
                final originalSupplierId = remittanceData['supplierId'] as int;
                if (supplierIdMap.containsKey(originalSupplierId)) {
                  remittanceData['supplierId'] = supplierIdMap[originalSupplierId];
                } else {
                  remittanceData['supplierId'] = null;
                }
              }
              
              // 更新employeeId关联关系
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

          // 恢复用户设置数据
          if (data['userSettings'] != null && (data['userSettings'] as List).isNotEmpty) {
            final userSettingsData = Map<String, dynamic>.from((data['userSettings'] as List).first);
            userSettingsData['userId'] = userId;
            userSettingsData.remove('id'); // 移除原始ID，让数据库自动生成新ID
            await txn.insert('user_settings', userSettingsData);
          }
        });

        Navigator.of(context).pop(); // 关闭加载对话框

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(importMode == 'overwrite' ? '数据覆盖成功！' : '数据合并成功！'),
            backgroundColor: Colors.green,
          ),
        );

        // 重新加载设置
        _loadModelSettings();

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未选择文件')),
        );
      }

    } catch (e) {
      Navigator.of(context).pop(); // 关闭加载对话框
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据恢复失败: $e')),
    );
    }
  }
  
  // 重置模型设置为默认值
  void _resetModelSettings() {
    setState(() {
      _temperature = 0.7;
      _maxTokens = 2000;
      _selectedModel = 'deepseek-chat';
      _apiKey = '';
      _apiKeyController.clear();
    });
    
    // 重置后自动保存
    _autoSaveSettings();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已重置为默认设置')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('设置', 
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(16.0),
              children: [
                // 数据管理卡片 - 移到最顶端
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.storage, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              '数据管理',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Divider(),
                        ListTile(
                          leading: Icon(Icons.download, color: Colors.green),
                          title: Text('导出全部数据'),
                          subtitle: Text('将当前用户的所有数据导出为JSON备份文件'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _exportAllData,
                        ),
                        Divider(),
                        ListTile(
                          leading: Icon(Icons.upload, color: Colors.orange),
                          title: Text('导入数据'),
                          subtitle: Text('从备份文件恢复数据（支持覆盖或合并模式）'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _importData,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                
                // 账户设置卡片
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '账户设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Divider(),
                        SizedBox(height: 8),
                        Text('当前用户: $_username'),
                        SizedBox(height: 16),
                        Text(
                          '修改密码',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _currentPasswordController,
                                decoration: InputDecoration(
                                  labelText: '当前密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureCurrentPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureCurrentPassword = !_obscureCurrentPassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscureCurrentPassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '请输入当前密码';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: _newPasswordController,
                                decoration: InputDecoration(
                                  labelText: '新密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNewPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureNewPassword = !_obscureNewPassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscureNewPassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '请输入新密码';
                                  }
                                  if (value.length < 3) {
                                    return '密码长度至少为3个字符';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 8),
                              TextFormField(
                                controller: _confirmPasswordController,
                                decoration: InputDecoration(
                                  labelText: '确认新密码',
                                  border: OutlineInputBorder(),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirmPassword = !_obscureConfirmPassword;
                                      });
                                    },
                                  ),
                                ),
                                obscureText: _obscureConfirmPassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return '请确认新密码';
                                  }
                                  if (value != _newPasswordController.text) {
                                    return '两次输入的密码不一致';
                                  }
                                  return null;
                                },
                              ),
                              SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _changePassword,
                                child: Text('更新密码'),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: Size(double.infinity, 50),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                
                // DeepSeek模型设置卡片
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'DeepSeek 模型设置',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.refresh, size: 20),
                              tooltip: '重置为默认值',
                              onPressed: _resetModelSettings,
                            ),
                          ],
                        ),
                        Divider(),
                        
                        // API Key 输入
                        ListTile(
                          title: Text('API Key'),
                          subtitle: Text('请输入您的DeepSeek API密钥'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: _apiKeyController,
                            decoration: InputDecoration(
                              hintText: '请输入API Key',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.vpn_key),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureApiKey
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureApiKey = !_obscureApiKey;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureApiKey,
                            onChanged: (value) {
                              setState(() {
                                _apiKey = value;
                              });
                              // API Key修改时自动保存
                              _autoSaveSettings();
                            },
                          ),
                        ),
                        SizedBox(height: 16),
                        
                        // 模型选择
                        ListTile(
                          title: Text('模型'),
                          subtitle: Text('选择使用的DeepSeek模型'),
                          trailing: DropdownButton<String>(
                            value: _selectedModel,
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedModel = newValue;
                                });
                                // 模型选择变更时自动保存
                                _autoSaveSettings();
                              }
                            },
                            items: _availableModels.map<DropdownMenuItem<String>>((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                          ),
                        ),
                        
                        // 温度滑块
                        ListTile(
                          title: Text('温度 (Temperature)'),
                          subtitle: Text('控制回答的创造性和随机性，值越高回答越多样'),
                          trailing: Text(_temperature.toStringAsFixed(1)),
                        ),
                        Slider(
                          value: _temperature,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          label: _temperature.toStringAsFixed(1),
                          onChanged: (value) {
                            setState(() {
                              _temperature = value;
                            });
                            // 温度调整时自动保存
                            _autoSaveSettings();
                          },
                        ),
                        
                        // 最大令牌数
                        ListTile(
                          title: Text('最大输出长度'),
                          subtitle: Text('控制回答的最大长度，值越大回答越详细'),
                          trailing: Text('$_maxTokens'),
                        ),
                        Slider(
                          value: _maxTokens.toDouble(),
                          min: 500,
                          max: 4000,
                          divisions: 7,
                          label: _maxTokens.toString(),
                          onChanged: (value) {
                            setState(() {
                              _maxTokens = value.toInt();
                            });
                            // 最大令牌数调整时自动保存
                            _autoSaveSettings();
                          },
                        ),
                        
                        // 参数说明
                        Container(
                          margin: EdgeInsets.only(top: 16),
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '参数说明:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '温度: 较低的值 (0.2) 使回答更加确定和精确，较高的值 (0.8) 使回答更有创意和多样化。',
                                style: TextStyle(fontSize: 12),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '最大输出长度: 控制AI回答的最大长度。增加这个值可以获得更详细的回答，但会消耗更多API资源。',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '关于系统',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Divider(),
                        ListTile(
                          leading: Icon(Icons.info_outline, color: Colors.blue),
                          title: Text('系统信息'),
                          subtitle: Text('农资管理系统 v2.1.0'),
                          trailing: Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            showAboutDialog(
                              context: context,
                              applicationName: '农资管理系统',
                              applicationVersion: 'v2.1.0',
                              applicationIcon: Image.asset(
                                'assets/images/background.png',
                                width: 50,
                                height: 50,
                              ),
                              applicationLegalese: '© 2025 农资管理系统',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed('/');
                  },
                  child: Text('退出登录'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[100],
                    foregroundColor: Colors.red[800],
                    minimumSize: Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
          ),
          FooterWidget(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }
}