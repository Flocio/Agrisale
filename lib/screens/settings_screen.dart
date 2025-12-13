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
import '../services/auto_backup_service.dart';

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
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUsername();
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
      // 不导出 user_settings（包含个人隐私数据如 API Key）
      
      // 构建导出数据
      final exportData = {
        'exportInfo': {
          'username': username,
          'exportTime': DateTime.now().toIso8601String(),
          'version': '2.4.0', // 更新版本号
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
          // 用户设置（user_settings）不导出
          // 理由：包含个人隐私数据（API Key）和个人偏好，与业务数据无关
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
        await Share.shareFiles([file.path], text: 'Agrisale数据备份文件');
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

  // 数据恢复功能（仅覆盖模式）
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

        // 检查数据来源
        final backupUsername = importData['exportInfo']['username'] ?? '未知';
        final backupVersion = importData['exportInfo']['version'] ?? '未知';
        final backupTime = importData['exportInfo']['exportTime'] ?? '未知';
        final isFromDifferentUser = backupUsername != username;
        
        // 检查数据量
        final data = importData['data'] as Map<String, dynamic>;
        final backupSupplierCount = (data['suppliers'] as List?)?.length ?? 0;
        final backupCustomerCount = (data['customers'] as List?)?.length ?? 0;
        final backupProductCount = (data['products'] as List?)?.length ?? 0;
        final backupEmployeeCount = (data['employees'] as List?)?.length ?? 0;
        final backupPurchaseCount = (data['purchases'] as List?)?.length ?? 0;
        final backupSaleCount = (data['sales'] as List?)?.length ?? 0;
        final backupReturnCount = (data['returns'] as List?)?.length ?? 0;
        final backupIncomeCount = (data['income'] as List?)?.length ?? 0;
        final backupRemittanceCount = (data['remittance'] as List?)?.length ?? 0;

        // 显示确认对话框
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('确认覆盖数据', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 数据来源信息
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                            SizedBox(width: 8),
                            Text('备份信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Divider(height: 16),
                        _buildInfoRow('来源用户', backupUsername),
                        _buildInfoRow('导出时间', backupTime.split('T')[0]),
                        _buildInfoRow('数据版本', backupVersion),
                        Divider(height: 16),
                        Text('数据统计:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        _buildDataCountRow('供应商', backupSupplierCount),
                        _buildDataCountRow('客户', backupCustomerCount),
                        _buildDataCountRow('产品', backupProductCount),
                        _buildDataCountRow('员工', backupEmployeeCount),
                        _buildDataCountRow('采购记录', backupPurchaseCount),
                        _buildDataCountRow('销售记录', backupSaleCount),
                        _buildDataCountRow('退货记录', backupReturnCount),
                        _buildDataCountRow('进账记录', backupIncomeCount),
                        _buildDataCountRow('汇款记录', backupRemittanceCount),
                      ],
                    ),
                  ),
                  
                  // 不同用户警告
                  if (isFromDifferentUser) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '警告：此备份来自不同用户（$backupUsername）！',
                              style: TextStyle(fontSize: 13, color: Colors.orange[900], fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // 覆盖警告
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[400]!, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '覆盖模式',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red[900]),
                              ),
                            ),
                          ],
                        ),
                        Divider(height: 12, color: Colors.red[300]),
                        Text('• 将删除当前所有业务数据', style: TextStyle(fontSize: 13, color: Colors.red[800])),
                        Text('• 完全替换为备份中的数据', style: TextStyle(fontSize: 13, color: Colors.red[800])),
                        Text('• 此操作不可撤销！', style: TextStyle(fontSize: 13, color: Colors.red[900], fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green[600], size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '您的个人设置（API Key等）不会改变',
                                  style: TextStyle(fontSize: 12, color: Colors.green[800]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('取消', style: TextStyle(fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('确认覆盖', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        // 显示加载对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('正在覆盖数据...'),
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

        // 在事务中执行数据恢复
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
          // 注意：不删除 user_settings，保留用户的个人设置和隐私数据

          // 创建ID映射表来保持关联关系（旧ID -> 新ID）
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
              
              // 更新supplierId关联关系
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
              
              // 更新customerId关联关系
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
              
              // 更新customerId关联关系
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

          // 恢复remittance数据
          if (data['remittance'] != null) {
            for (var remittanceItem in data['remittance']) {
              final remittanceData = Map<String, dynamic>.from(remittanceItem);
              remittanceData.remove('id');
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

          // 用户设置（user_settings）不导入
          // 理由：用户设置包含个人隐私数据（API Key）和个人偏好
          //       与业务数据无关，应该保留当前设置
        });

        Navigator.of(context).pop(); // 关闭加载对话框

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据覆盖成功！'),
            backgroundColor: Colors.green,
          ),
        );


      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未选择文件')),
        );
      }

    } catch (e) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // 关闭加载对话框
      }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据恢复失败: $e')),
    );
    }
  }
  
  // 辅助方法：构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
  
  // 辅助方法：构建数据计数行
  Widget _buildDataCountRow(String label, int count) {
    return Padding(
      padding: EdgeInsets.only(left: 8, top: 2),
      child: Text('• $label: $count 条', style: TextStyle(fontSize: 12)),
    );
  }
  
  // 退出登录
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认退出'),
        content: Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('退出'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      // 停止自动备份服务
      await AutoBackupService().stopAutoBackup();
      
      // 清除当前用户名（保留 last_username 用于下次登录）
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_username');
      
      // 跳转到登录界面
      Navigator.of(context).pushReplacementNamed('/');
    }
  }
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('账户设置', 
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
                        Text(
                          '数据管理',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
                          title: Text('导入数据（覆盖）'),
                          subtitle: Text('从备份文件恢复数据，将完全替换当前业务数据'),
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
                ElevatedButton(
                  onPressed: _logout,
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
    super.dispose();
  }
}