// lib/screens/supplier_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import '../widgets/entity_detail_dialog.dart';
import '../utils/visual_length_formatter.dart';
import 'supplier_records_screen.dart';
import 'supplier_transactions_screen.dart';
import 'supplier_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audit_log_service.dart';
import '../models/audit_log.dart';

class SupplierScreen extends StatefulWidget {
  @override
  _SupplierScreenState createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  bool _showDeleteButtons = false; // 控制是否显示删除按钮

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredSuppliers = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterSuppliers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤供应商的方法
  void _filterSuppliers() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      if (searchText.isEmpty) {
        _filteredSuppliers = List.from(_suppliers);
        _isSearching = false;
      } else {
        _filteredSuppliers = _suppliers.where((supplier) {
          final name = supplier['name'].toString().toLowerCase();
          final note = (supplier['note'] ?? '').toString().toLowerCase();
          return name.contains(searchText) || note.contains(searchText);
        }).toList();
        _isSearching = true;
      }
    });
  }

  Future<void> _fetchSuppliers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的供应商
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _suppliers = suppliers;
          _filteredSuppliers = suppliers; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addSupplier() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下供应商名称是否已存在
          final existingSupplier = await db.query(
            'suppliers',
            where: 'userId = ? AND name = ?',
            whereArgs: [userId, result['name']],
          );

          if (existingSupplier.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 添加userId到供应商数据
            result['userId'] = userId;
            final insertedId = await db.insert('suppliers', result);
            
            // 记录日志（不影响主业务逻辑）
            try {
              await AuditLogService().logCreate(
                entityType: EntityType.supplier,
                userId: userId,
                username: username,
                entityId: insertedId,
                entityName: result['name'],
                newData: {...result, 'id': insertedId},
              );
            } catch (e) {
              print('记录创建日志失败: $e');
            }
            
            _fetchSuppliers();
          }
        }
      }
    }
  }

  Future<void> _editSupplier(Map<String, dynamic> supplier) async {
    // 确保传递给对话框的是一个副本，避免引用问题
    final Map<String, dynamic> supplierCopy = Map<String, dynamic>.from(supplier);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SupplierDialog(supplier: supplierCopy),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下供应商名称是否已存在（排除当前编辑的供应商）
          final existingSupplier = await db.query(
            'suppliers',
            where: 'userId = ? AND name = ? AND id != ?',
            whereArgs: [userId, result['name'], supplier['id']],
          );

          if (existingSupplier.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 确保userId不变
            result['userId'] = userId;
            
            // 先更新数据库
            await db.update('suppliers', result, where: 'id = ? AND userId = ?', whereArgs: [supplier['id'], userId]);
            
            // 记录日志（不影响主业务逻辑）
            try {
              final oldData = Map<String, dynamic>.from(supplier);
              // 构建 newData 时保持与 oldData 相同的字段顺序
              final newData = {
                'id': supplier['id'],
                'userId': userId,
                'name': result['name'],
                'note': result['note'],
                'created_at': supplier['created_at'],
                'updated_at': supplier['updated_at'],
              };
              await AuditLogService().logUpdate(
                entityType: EntityType.supplier,
                userId: userId,
                username: username,
                entityId: supplier['id'] as int,
                entityName: result['name'],
                oldData: oldData,
                newData: newData,
              );
            } catch (e) {
              print('记录更新日志失败: $e');
            }
            
            _fetchSuppliers();
          }
        }
      }
    }
  }

  Future<void> _deleteSupplier(int id, String name) async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username == null) return;
    final userId = await DatabaseHelper().getCurrentUserId(username);
    if (userId == null) return;
    
    // 查询该供应商相关的记录数量
    final purchasesCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM purchases WHERE supplierId = ? AND userId = ?',
      [id, userId],
    )).first['count'] as int;
    
    final productsCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE supplierId = ? AND userId = ?',
      [id, userId],
    )).first['count'] as int;
    
    final remittanceCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM remittance WHERE supplierId = ? AND userId = ?',
      [id, userId],
    )).first['count'] as int;
    
    final totalRelatedRecords = purchasesCount + productsCount + remittanceCount;
    
    // 构建警告消息
    String warningMessage = '您确定要删除供应商 "$name" 吗？';
    
    if (totalRelatedRecords > 0) {
      warningMessage += '\n\n⚠️ 警告：该供应商有以下关联记录：';
      if (purchasesCount > 0) {
        warningMessage += '\n• 采购记录: $purchasesCount 条';
      }
      if (productsCount > 0) {
        warningMessage += '\n• 产品记录: $productsCount 个';
      }
      if (remittanceCount > 0) {
        warningMessage += '\n• 汇款记录: $remittanceCount 条';
      }
      warningMessage += '\n\n删除后，这些记录的供应商将显示为"未分配供应商"或"未知供应商"。';
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            if (totalRelatedRecords > 0)
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            if (totalRelatedRecords > 0)
              SizedBox(width: 8),
            Text('确认删除'),
          ],
        ),
        content: Text(warningMessage),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: totalRelatedRecords > 0 
                    ? TextButton.styleFrom(foregroundColor: Colors.red)
                    : null,
                child: Text(totalRelatedRecords > 0 ? '确认删除' : '确认'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 获取供应商数据用于日志记录
      final supplierData = await db.query(
        'suppliers',
        where: 'id = ? AND userId = ?',
        whereArgs: [id, userId],
      );
      
      // 只删除当前用户的供应商
      await db.delete('suppliers', where: 'id = ? AND userId = ?', whereArgs: [id, userId]);
      // 更新当前用户的采购记录，将删除的供应商ID设为0
      await db.update(
        'purchases',
        {'supplierId': 0},
        where: 'supplierId = ? AND userId = ?',
        whereArgs: [id, userId],
      );
      // 更新当前用户的产品记录，将删除的供应商ID设为null
      await db.update(
        'products',
        {'supplierId': null},
        where: 'supplierId = ? AND userId = ?',
        whereArgs: [id, userId],
      );
      // 更新当前用户的汇款记录，将删除的供应商ID设为0
      await db.update(
        'remittance',
        {'supplierId': 0},
        where: 'supplierId = ? AND userId = ?',
        whereArgs: [id, userId],
      );
      
      // 记录日志（不影响主业务逻辑）
      try {
        Map<String, dynamic>? oldData;
        if (supplierData.isNotEmpty) {
          oldData = Map<String, dynamic>.from(supplierData.first);
          // 添加级联操作信息
          if (totalRelatedRecords > 0) {
            oldData['cascade_info'] = {
              'operation': 'supplier_delete_update_relations',
              'affected_purchases': purchasesCount,
              'affected_products': productsCount,
              'affected_remittance': remittanceCount,
              'total_affected': totalRelatedRecords,
              'note': '关联记录的供应商已设为"未分配"或"未知供应商"',
            };
          }
        }
        await AuditLogService().logDelete(
          entityType: EntityType.supplier,
          userId: userId,
          username: username,
          entityId: id,
          entityName: name,
          oldData: oldData,
        );
      } catch (e) {
        print('记录删除日志失败: $e');
      }
      
      _fetchSuppliers();
      
      // 显示删除成功提示
      if (totalRelatedRecords > 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除供应商"$name"，$totalRelatedRecords 条关联记录的供应商已设为"未分配"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _viewSupplierRecords(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierRecordsScreen(supplierId: supplierId, supplierName: supplierName),
      ),
    );
  }

  void _viewSupplierTransactions(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierTransactionsScreen(supplierId: supplierId, supplierName: supplierName),
      ),
    );
  }

  void _viewSupplierDetail(int supplierId, String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierDetailScreen(supplierId: supplierId, supplierName: supplierName),
      ),
    );
  }

  /// 显示供应商详情对话框
  void _showSupplierDetailDialog(Map<String, dynamic> supplier) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    if (username == null) return;
    
    final userId = await DatabaseHelper().getCurrentUserId(username);
    if (userId == null) return;

    final supplierId = supplier['id'] as int;
    final supplierName = supplier['name'] as String;

    showDialog(
      context: context,
      builder: (context) => EntityDetailDialog(
        entityType: EntityType.supplier,
        entityTypeDisplayName: '供应商',
        entityId: supplierId,
        userId: userId,
        entityName: supplierName,
        recordData: supplier,
        themeColor: Colors.blue,
        actionButtons: [
          EntityActionButton(
            icon: Icons.receipt_long,
            label: '对账单',
            color: Colors.green,
            onPressed: () => _viewSupplierDetail(supplierId, supplierName),
          ),
          EntityActionButton(
            icon: Icons.account_balance_wallet,
            label: '往来记录',
            color: Colors.purple,
            onPressed: () => _viewSupplierTransactions(supplierId, supplierName),
          ),
          EntityActionButton(
            icon: Icons.list_alt,
            label: '采购记录',
            color: Colors.blue,
            onPressed: () => _viewSupplierRecords(supplierId, supplierName),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 添加手势检测器，点击空白处收起键盘
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('供应商', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
          actions: [
            IconButton(
              icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
              tooltip: _showDeleteButtons ? '取消删除模式' : '开启删除模式',
              onPressed: () {
                setState(() {
                  _showDeleteButtons = !_showDeleteButtons;
                });
              },
            ),
          ],
        ),
      body: Column(
        children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.business, color: Colors.blue[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '供应商列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredSuppliers.length} 家供应商',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
              child: _filteredSuppliers.isEmpty
                  ? SingleChildScrollView(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的供应商' : '暂无供应商',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加供应商',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      // 让列表也能点击收起键盘
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _filteredSuppliers.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final supplier = _filteredSuppliers[index];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _showSupplierDetailDialog(supplier),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                        supplier['name'].toString().isNotEmpty 
                                            ? supplier['name'].toString()[0].toUpperCase() 
                                            : '?',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[800],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          supplier['name'],
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if ((supplier['note'] ?? '').toString().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              supplier['note'],
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                                        icon: Icon(Icons.edit, color: Colors.blue),
                                        tooltip: '编辑',
                        onPressed: () => _editSupplier(supplier),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
                                      if (_showDeleteButtons)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: IconButton(
                                          icon: Icon(Icons.delete, color: Colors.red),
                                          tooltip: '删除',
                                          onPressed: () => _deleteSupplier(
                                            supplier['id'] as int, 
                                            supplier['name'] as String
                                          ),
                                          constraints: BoxConstraints(),
                                          padding: EdgeInsets.all(8),
                                        ),
                      ),
                    ],
                                  ),
                                ],
                              ),
                            ),
                  ),
                );
              },
            ),
          ),
            // 添加搜索栏和浮动按钮的容器
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 搜索框
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索供应商...',
                        prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                        suffixIcon: _isSearching
                            ? IconButton(
                                icon: Icon(Icons.clear, color: Colors.grey[600]),
                                onPressed: () {
                                  _searchController.clear();
                                  FocusScope.of(context).unfocus();
                                },
                              )
                            : null,
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      // 添加键盘相关设置
                      textInputAction: TextInputAction.search,
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  // 添加按钮
                  FloatingActionButton(
        onPressed: _addSupplier,
        child: Icon(Icons.add),
                    tooltip: '添加供应商',
                    backgroundColor: Colors.blue,
                    mini: false,
                  ),
                ],
              ),
            ),
            FooterWidget(),
          ],
        ),
      ),
    );
  }
}

class SupplierDialog extends StatefulWidget {
  final Map<String, dynamic>? supplier;

  SupplierDialog({this.supplier});

  @override
  _SupplierDialogState createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      _nameController.text = widget.supplier!['name'].toString();
      _noteController.text = (widget.supplier!['note'] ?? '').toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? '添加供应商' : '编辑供应商',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Form(
        key: _formKey,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            TextFormFieldWithCounter(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '供应商名称',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.blue),
              ),
              inputFormatters: [VisualLengthFormatter()],
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入供应商名称';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            TextFormFieldWithCounter(
              controller: _noteController,
              maxVisualLength: kMaxNoteVisualLength,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.note, color: Colors.blue),
              ),
              onChanged: (_) => setState(() {}),
            ),
        ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  final Map<String, dynamic> supplier = {
                    'name': _nameController.text.trim(),
                    'note': _noteController.text.trim(),
                };
                  // 确保ID使用原始类型
                  if (widget.supplier != null && widget.supplier!.containsKey('id')) {
                    // 保留原始ID类型，不进行转换
                    supplier['id'] = widget.supplier!['id'];
                  }
                Navigator.of(context).pop(supplier);
                }
              },
              child: Text('保存'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('取消'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}