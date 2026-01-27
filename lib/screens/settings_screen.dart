import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../utils/app_version.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import '../services/auto_backup_service.dart';
import '../services/export_service.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _deletePasswordController = TextEditingController();
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureDeletePassword = true;
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          'version': AppVersion.version, // 统一版本号管理
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
      
      // 生成文件名（保持原有格式）
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final fileName = '${username}_Agrisale数据_$timestamp.json';
          
          Navigator.of(context).pop(); // 关闭加载对话框
          
      // 使用统一的导出服务
      await ExportService.showJSONExportOptions(
        context: context,
        jsonData: jsonString,
        fileName: fileName,
      );

    } catch (e) {
      Navigator.of(context).pop(); // 关闭加载对话框
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('文件格式错误，请选择正确的备份文件')),
          );
          return;
        }

        // 检查数据来源
        final backupUsername = importData['exportInfo']['username'] ?? '未知';
        final backupVersion = importData['exportInfo']['version'] ?? '未知';
        final backupTime = importData['exportInfo']['exportTime'] ?? '未知';
        final backupTimeDisplay = _formatImportTime(backupTime);
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
            title: Text('确认导入（覆盖）数据', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 420),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 备份信息
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
                        _buildInfoRow('导出时间', backupTimeDisplay),
                        _buildInfoRow('数据版本', backupVersion),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),

                  // 数据统计（两行表格）
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.table_chart, color: Colors.teal[700], size: 18),
                            SizedBox(width: 8),
                            Text('数据统计', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        Divider(height: 16),
                        SizedBox(
                          width: 420,
                          child: Table(
                            border: TableBorder.all(color: Colors.grey[300]!, width: 0.8),
                            columnWidths: const <int, TableColumnWidth>{
                              0: FlexColumnWidth(),
                              1: FlexColumnWidth(),
                              2: FlexColumnWidth(),
                              3: FlexColumnWidth(),
                              4: FlexColumnWidth(),
                            },
                            children: [
                              TableRow(
                                children: [
                                  _buildStatCell('产品', backupProductCount),
                                  _buildStatCell('供应商', backupSupplierCount),
                                  _buildStatCell('客户', backupCustomerCount),
                                  _buildStatCell('员工', backupEmployeeCount),
                                  _buildStatCell('', 0, isEmpty: true),
                                ],
                              ),
                              TableRow(
                                children: [
                                  _buildStatCell('采购', backupPurchaseCount),
                                  _buildStatCell('销售', backupSaleCount),
                                  _buildStatCell('退货', backupReturnCount),
                                  _buildStatCell('进账', backupIncomeCount),
                                  _buildStatCell('汇款', backupRemittanceCount),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),

                  // 警告汇总
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
                                '警告提示',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red[900]),
                              ),
                            ),
                          ],
                        ),
                        Divider(height: 12, color: Colors.red[300]),
                        if (isFromDifferentUser)
                          Text(
                            '• 该备份来自不同用户（$backupUsername）',
                            style: TextStyle(fontSize: 13, color: Colors.red[800]),
                          ),
                        Text('• 将删除当前所有业务数据', style: TextStyle(fontSize: 13, color: Colors.red[800])),
                        Text('• 完全替换为备份中的数据', style: TextStyle(fontSize: 13, color: Colors.red[800])),
                        Text('• 此操作不可撤销！', style: TextStyle(fontSize: 13, color: Colors.red[900], fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                ),
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

        // 兼容云端版导出的数据：如果每条记录仅比本地版多出 version/created_at/updated_at 这3个字段，则在导入前统一忽略这3个字段
        void _stripExtraMetaFields(Map<String, dynamic> row) {
          // 只移除这三个已知的额外字段，其它字段仍然保留（如果有其它字段，后续插入时会因列不存在而报错）
          row.remove('version');
          row.remove('created_at');
          row.remove('updated_at');
        }

        // 对各表中的每条记录进行字段清理
        if (data['products'] != null) {
          for (var item in data['products']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['suppliers'] != null) {
          for (var item in data['suppliers']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['customers'] != null) {
          for (var item in data['customers']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['employees'] != null) {
          for (var item in data['employees']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['purchases'] != null) {
          for (var item in data['purchases']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['sales'] != null) {
          for (var item in data['sales']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['returns'] != null) {
          for (var item in data['returns']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['income'] != null) {
          for (var item in data['income']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
        }
        if (data['remittance'] != null) {
          for (var item in data['remittance']) {
            if (item is Map<String, dynamic>) {
              _stripExtraMetaFields(item);
            }
          }
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
                Text('正在覆盖数据...'),
              ],
            ),
          ),
        );

        final db = await DatabaseHelper().database;
        final userId = await DatabaseHelper().getCurrentUserId(username);
        
        if (userId == null) {
          Navigator.of(context).pop(); // 关闭加载对话框
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据覆盖成功！'),
            backgroundColor: Colors.green,
          ),
        );


      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未选择文件')),
        );
      }

    } catch (e) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // 关闭加载对话框
      }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  // 辅助方法：构建统计表格单元格
  Widget _buildStatCell(String label, int count, {bool isEmpty = false}) {
    if (isEmpty) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 2),
          Text('$count', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ],
      ),
    );
  }

  String _formatImportTime(String value) {
    if (value.isEmpty || value == '未知') {
      return value;
    }
    if (value.contains('T')) {
      return value.replaceFirst('T', ' ').replaceFirst(RegExp(r'\.\d+Z?$'), '');
    }
    return value;
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
      // 退出账号前，如果开启了“退出时自动备份”，先备份一次
      await AutoBackupService().backupOnExitIfNeeded();
      
      // 停止自动备份服务
      await AutoBackupService().stopAutoBackup();
      
      // 清除当前用户名（保留 last_username 用于下次登录）
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_username');
      
      // 跳转到登录界面
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  // 注销账号
  Future<void> _deleteAccount() async {
    if (_username == null || _username == '未登录') {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先登录')),
      );
      return;
    }

    // 清空密码输入框
    _deletePasswordController.clear();
    
    // 第一步：显示警告确认对话框
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 28),
            SizedBox(width: 8),
            Text('注销账号', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ 警告：此操作不可撤销！',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.red[900],
                      ),
                    ),
                    SizedBox(height: 12),
                    Text('注销账号将永久删除以下所有数据：', style: TextStyle(fontSize: 14)),
                    SizedBox(height: 8),
                    _buildDeleteWarningItem('账号信息和登录凭证'),
                    _buildDeleteWarningItem('所有产品、供应商、客户、员工数据'),
                    _buildDeleteWarningItem('所有采购、销售、退货记录'),
                    _buildDeleteWarningItem('所有进账、汇款记录'),
                    _buildDeleteWarningItem('个人设置（包括 API Key）'),
                    _buildDeleteWarningItem('该账号的所有自动备份文件'),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                '当前账号: $_username',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                '确定要继续注销此账号吗？',
                style: TextStyle(fontSize: 14),
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
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text('继续', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return;

    // 第二步：要求输入密码确认
    final passwordConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('验证密码', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('请输入账号密码以确认注销：'),
              SizedBox(height: 16),
              TextField(
                controller: _deletePasswordController,
                obscureText: _obscureDeletePassword,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureDeletePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        _obscureDeletePassword = !_obscureDeletePassword;
                      });
                    },
                  ),
                ),
              ),
            ],
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
              ),
              child: Text('确认注销', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );

    if (passwordConfirm != true) return;

    // 验证密码
    final password = _deletePasswordController.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入密码')),
      );
      return;
    }

    final isPasswordValid = await DatabaseHelper().verifyUserPassword(_username!, password);
    if (!isPasswordValid) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('密码错误，账号注销已取消'),
          backgroundColor: Colors.red,
        ),
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
            Text('正在注销账号...'),
          ],
        ),
      ),
    );

    try {
      // 停止自动备份服务
      await AutoBackupService().stopAutoBackup();

      // 获取用户ID
      final userId = await DatabaseHelper().getCurrentUserId(_username!);
      if (userId == null) {
        Navigator.of(context).pop(); // 关闭加载对话框
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('用户信息错误')),
        );
        return;
      }

      // 删除用户账号及所有数据
      final deletedCounts = await DatabaseHelper().deleteUserAccount(userId);

      // 删除该用户的所有自动备份文件
      final deletedBackupCount = await AutoBackupService().deleteBackupsForUser(_username!);

      // 清除 SharedPreferences 中的用户信息
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_username');
      // 如果 last_username 是被删除的用户，也清除它
      final lastUsername = prefs.getString('last_username');
      if (lastUsername == _username) {
        await prefs.remove('last_username');
      }

      Navigator.of(context).pop(); // 关闭加载对话框

      // 显示成功消息
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('账号已注销'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('账号 "$_username" 及其所有数据已被永久删除。'),
              SizedBox(height: 12),
              Text(
                '删除统计：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text('• 产品: ${deletedCounts['products'] ?? 0} 条'),
              Text('• 供应商: ${deletedCounts['suppliers'] ?? 0} 条'),
              Text('• 客户: ${deletedCounts['customers'] ?? 0} 条'),
              Text('• 员工: ${deletedCounts['employees'] ?? 0} 条'),
              Text('• 采购记录: ${deletedCounts['purchases'] ?? 0} 条'),
              Text('• 销售记录: ${deletedCounts['sales'] ?? 0} 条'),
              Text('• 退货记录: ${deletedCounts['returns'] ?? 0} 条'),
              Text('• 进账记录: ${deletedCounts['income'] ?? 0} 条'),
              Text('• 汇款记录: ${deletedCounts['remittance'] ?? 0} 条'),
              Text('• 自动备份文件: $deletedBackupCount 个'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('确定'),
            ),
          ],
        ),
      );

      // 跳转到登录界面
      Navigator.of(context).pushReplacementNamed('/');

    } catch (e) {
      Navigator.of(context).pop(); // 关闭加载对话框
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('注销失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 辅助方法：构建删除警告项
  Widget _buildDeleteWarningItem(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 8, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontSize: 14, color: Colors.red[800])),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, color: Colors.red[800])),
          ),
        ],
      ),
    );
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
        actions: [
          IconButton(
            onPressed: _deleteAccount,
            icon: Icon(Icons.delete_forever, color: Colors.black87),
            tooltip: '注销账号',
          ),
        ],
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
    _deletePasswordController.dispose();
    super.dispose();
  }
}