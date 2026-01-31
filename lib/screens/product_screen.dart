// lib/screens/product_screen.dart

import 'package:flutter/material.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart'; // 确保路径正确
import '../widgets/entity_detail_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audit_log_service.dart';
import '../models/audit_log.dart';

class ProductScreen extends StatefulWidget {
  @override
  _ProductScreenState createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = []; // 添加供应商列表
  bool _showDeleteButtons = false;

  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredProducts = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加供应商筛选
  String? _selectedSupplierFilter;

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 添加过滤产品的方法
  void _filterProducts() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      List<Map<String, dynamic>> result = List.from(_products);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchText.isNotEmpty) {
        hasFilters = true;
        result = result.where((product) {
          final name = product['name'].toString().toLowerCase();
          final description = (product['description'] ?? '').toString().toLowerCase();
          return name.contains(searchText) || description.contains(searchText);
        }).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null && _selectedSupplierFilter != '全部供应商') {
        hasFilters = true;
        final selectedSupplierId = _suppliers
            .firstWhere(
              (s) => s['name'] == _selectedSupplierFilter,
              orElse: () => {'id': -1},
            )['id'];
        
        if (selectedSupplierId == -1) {
          // "未分配供应商"
          result = result.where((product) => 
            product['supplierId'] == null || product['supplierId'] == 0).toList();
        } else {
          result = result.where((product) => 
            product['supplierId'] == selectedSupplierId).toList();
      }
      }
      
      _isSearching = hasFilters;
      _filteredProducts = result;
    });
  }

  Future<void> _fetchProducts() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _products = products;
          _suppliers = suppliers;
          _filterProducts(); // 使用过滤方法代替直接赋值
        });
      }
    }
  }

  Future<void> _addProduct() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(suppliers: _suppliers),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下产品名称是否已存在
          final existingProduct = await db.query(
            'products',
            where: 'userId = ? AND name = ?',
            whereArgs: [userId, result['name']],
          );

          if (existingProduct.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // 添加userId到产品数据
            result['userId'] = userId;
            final insertedId = await db.insert('products', result);
            
            // 记录日志
            await AuditLogService().logCreate(
              entityType: EntityType.product,
              userId: userId,
              username: username,
              entityId: insertedId,
              entityName: result['name'],
              newData: {...result, 'id': insertedId},
            );
            
            _fetchProducts();
          }
        }
      }
    }
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductDialog(product: product, suppliers: _suppliers),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 检查当前用户下产品名称是否已存在（排除当前编辑的产品）
          final existingProduct = await db.query(
            'products',
            where: 'userId = ? AND name = ? AND id != ?',
            whereArgs: [userId, result['name'], product['id']],
          );

          if (existingProduct.isNotEmpty) {
            // 显示提示信息
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result['name']} 已存在'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            final oldProductName = product['name'] as String;
            final newProductName = result['name'] as String;
            final oldSupplierId = product['supplierId'];
            final newSupplierId = result['supplierId'];
            
            // 检查供应商是否发生变化
            bool supplierChanged = (oldSupplierId != newSupplierId) && 
                (oldSupplierId != null && oldSupplierId != 0);
            bool shouldSyncSupplier = false;
            
            if (supplierChanged) {
              // 查询该产品的采购记录数量
              final purchaseCount = (await db.rawQuery(
                'SELECT COUNT(*) as count FROM purchases WHERE productName = ? AND userId = ? AND supplierId = ?',
                [oldProductName, userId, oldSupplierId],
              )).first['count'] as int;
              
              if (purchaseCount > 0) {
                // 获取供应商名称用于显示
                final oldSupplierName = _getSupplierName(oldSupplierId is int ? oldSupplierId : int.tryParse(oldSupplierId.toString()));
                final newSupplierName = newSupplierId != null && newSupplierId != 0
                    ? _getSupplierName(newSupplierId is int ? newSupplierId : int.tryParse(newSupplierId.toString()))
                    : '未分配';
                
                // 弹出对话框询问用户是否同步修改采购记录的供应商
                // 返回值: true=同步修改, false=不修改, null=取消整个操作
                final bool nameAlsoChanged = oldProductName != newProductName;
                final syncChoice = await showDialog<bool?>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(Icons.sync, color: Colors.blue, size: 24),
                        SizedBox(width: 8),
                        Expanded(child: Text('同步供应商信息')),
                      ],
                    ),
                    content: Text(
                      '检测到产品"$oldProductName"${nameAlsoChanged ? '（将修改为"$newProductName"）' : ''}的供应商从"$oldSupplierName"变更为"$newSupplierName"。\n\n'
                      '该产品有 $purchaseCount 条采购记录关联到原供应商"$oldSupplierName"。\n\n'
                      '是否将这些采购记录的供应商也同步修改为"$newSupplierName"？'
                      '${nameAlsoChanged ? '\n\n（注：产品名称修改将自动同步到所有相关记录）' : ''}',
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    actions: [
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text('同步修改'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text('不修改'),
                          ),
                          Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            style: TextButton.styleFrom(foregroundColor: Colors.grey),
                            child: Text('取消'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                
                // 如果用户选择取消，终止整个编辑操作
                if (syncChoice == null) {
                  return;
                }
                shouldSyncSupplier = syncChoice;
              }
            }
            
            // 确保userId不变
            result['userId'] = userId;
            
            // 准备日志数据
            final oldData = Map<String, dynamic>.from(product);
            // 构建 newData 时保持与 oldData 相同的字段顺序
            final newData = {
              'id': product['id'],
              'userId': userId,
              'name': result['name'],
              'description': result['description'],
              'stock': result['stock'],
              'unit': result['unit'],
              'supplierId': result['supplierId'],
              'created_at': product['created_at'],
              'updated_at': product['updated_at'],
            };
            
            // 统计级联更新数量
            int affectedPurchases = 0;
            int affectedSales = 0;
            int affectedReturns = 0;
            int supplierSyncedPurchases = 0;
            
            await db.update('products', result, where: 'id = ? AND userId = ?', whereArgs: [product['id'], userId]);
            
            // 如果产品名称发生变化，同步更新 purchases/sales/returns 表中的 productName
            if (oldProductName != newProductName) {
              affectedPurchases = await db.update(
                'purchases',
                {'productName': newProductName},
                where: 'productName = ? AND userId = ?',
                whereArgs: [oldProductName, userId],
              );
              affectedSales = await db.update(
                'sales',
                {'productName': newProductName},
                where: 'productName = ? AND userId = ?',
                whereArgs: [oldProductName, userId],
              );
              affectedReturns = await db.update(
                'returns',
                {'productName': newProductName},
                where: 'productName = ? AND userId = ?',
                whereArgs: [oldProductName, userId],
              );
            }
            
            // 如果用户选择同步修改供应商，更新采购记录的供应商
            if (shouldSyncSupplier) {
              // 使用新的产品名称（可能已经改变）
              final productNameToUse = newProductName;
              supplierSyncedPurchases = await db.update(
                'purchases',
                {'supplierId': newSupplierId},
                where: 'productName = ? AND userId = ? AND supplierId = ?',
                whereArgs: [productNameToUse, userId, oldSupplierId],
              );
            }
            
            // 构建级联操作信息
            if (oldProductName != newProductName || supplierChanged) {
              final cascadeInfo = <String, dynamic>{};
              
              if (oldProductName != newProductName) {
                cascadeInfo['operation'] = 'product_name_sync';
                cascadeInfo['old_product_name'] = oldProductName;
                cascadeInfo['new_product_name'] = newProductName;
                cascadeInfo['affected_purchases'] = affectedPurchases;
                cascadeInfo['affected_sales'] = affectedSales;
                cascadeInfo['affected_returns'] = affectedReturns;
                cascadeInfo['total_affected'] = affectedPurchases + affectedSales + affectedReturns;
                
                // 如果同时有供应商同步
                if (shouldSyncSupplier) {
                  cascadeInfo['supplier_sync'] = {
                    'old_supplier': _getSupplierName(oldSupplierId is int ? oldSupplierId : int.tryParse(oldSupplierId.toString())),
                    'new_supplier': newSupplierId != null && newSupplierId != 0
                        ? _getSupplierName(newSupplierId is int ? newSupplierId : int.tryParse(newSupplierId.toString()))
                        : '未分配',
                    'updated_purchases': supplierSyncedPurchases,
                  };
                } else if (supplierChanged) {
                  // 供应商变更但用户选择不同步
                  cascadeInfo['supplier_no_sync'] = {
                    'old_supplier': _getSupplierName(oldSupplierId is int ? oldSupplierId : int.tryParse(oldSupplierId.toString())),
                    'new_supplier': newSupplierId != null && newSupplierId != 0
                        ? _getSupplierName(newSupplierId is int ? newSupplierId : int.tryParse(newSupplierId.toString()))
                        : '未分配',
                    'skipped_purchases': (await db.rawQuery(
                      'SELECT COUNT(*) as count FROM purchases WHERE productName = ? AND userId = ? AND supplierId = ?',
                      [newProductName, userId, oldSupplierId],
                    )).first['count'] as int,
                    'note': '用户选择不同步采购记录的供应商',
                  };
                }
              } else if (shouldSyncSupplier) {
                // 只有供应商同步
                cascadeInfo['operation'] = 'product_supplier_sync';
                cascadeInfo['old_supplier'] = _getSupplierName(oldSupplierId is int ? oldSupplierId : int.tryParse(oldSupplierId.toString()));
                cascadeInfo['new_supplier'] = newSupplierId != null && newSupplierId != 0
                    ? _getSupplierName(newSupplierId is int ? newSupplierId : int.tryParse(newSupplierId.toString()))
                    : '未分配';
                cascadeInfo['updated_purchases'] = supplierSyncedPurchases;
              } else if (supplierChanged) {
                // 供应商变更但用户选择不同步
                cascadeInfo['operation'] = 'product_supplier_no_sync';
                cascadeInfo['old_supplier'] = _getSupplierName(oldSupplierId is int ? oldSupplierId : int.tryParse(oldSupplierId.toString()));
                cascadeInfo['new_supplier'] = newSupplierId != null && newSupplierId != 0
                    ? _getSupplierName(newSupplierId is int ? newSupplierId : int.tryParse(newSupplierId.toString()))
                    : '未分配';
                cascadeInfo['skipped_purchases'] = (await db.rawQuery(
                  'SELECT COUNT(*) as count FROM purchases WHERE productName = ? AND userId = ? AND supplierId = ?',
                  [newProductName, userId, oldSupplierId],
                )).first['count'] as int;
                cascadeInfo['note'] = '用户选择不同步采购记录的供应商';
              }
              
              oldData['cascade_info'] = cascadeInfo;
            }
            
            // 记录日志
            await AuditLogService().logUpdate(
              entityType: EntityType.product,
              userId: userId,
              username: username,
              entityId: product['id'] as int,
              entityName: newProductName,
              oldData: oldData,
              newData: newData,
            );
            
            // 显示操作结果提示
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            String successMessage = '产品已更新';
            if (oldProductName != newProductName && shouldSyncSupplier) {
              successMessage = '产品已更新，名称和供应商已同步到相关记录';
            } else if (oldProductName != newProductName) {
              successMessage = '产品已更新，名称已同步到相关记录';
            } else if (shouldSyncSupplier) {
              successMessage = '产品已更新，供应商已同步到采购记录';
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(successMessage),
                behavior: SnackBarBehavior.floating,
              ),
            );
            
            _fetchProducts();
          }
        }
      }
    }
  }

  /// 显示产品详情对话框
  void _showProductDetailDialog(Map<String, dynamic> product) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    if (username == null) return;
    
    final userId = await DatabaseHelper().getCurrentUserId(username);
    if (userId == null) return;

    // 获取供应商名称
    String? supplierName;
    final supplierId = product['supplierId'];
    if (supplierId != null && supplierId != 0) {
      final supplier = _suppliers.firstWhere(
        (s) => s['id'] == supplierId,
        orElse: () => {'name': '未知供应商'},
      );
      supplierName = supplier['name'] as String?;
    }
    
    // 构建带有供应商名称的数据
    final recordData = Map<String, dynamic>.from(product);
    if (supplierName != null) {
      recordData['supplierName'] = supplierName;
    }

    showDialog(
      context: context,
      builder: (context) => EntityDetailDialog(
        entityType: EntityType.product,
        entityTypeDisplayName: '产品',
        entityId: product['id'] as int,
        userId: userId,
        entityName: product['name'] as String,
        recordData: recordData,
        themeColor: Colors.green,
        actionButtons: [], // 产品没有操作按钮
      ),
    );
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username == null) return;
    final userId = await DatabaseHelper().getCurrentUserId(username);
    if (userId == null) return;
    
    final productName = product['name'] as String;
    
    // 查询该产品相关的记录数量
    final purchaseCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM purchases WHERE productName = ? AND userId = ?',
      [productName, userId],
    )).first['count'] as int;
    
    final salesCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM sales WHERE productName = ? AND userId = ?',
      [productName, userId],
    )).first['count'] as int;
    
    final returnsCount = (await db.rawQuery(
      'SELECT COUNT(*) as count FROM returns WHERE productName = ? AND userId = ?',
      [productName, userId],
    )).first['count'] as int;
    
    final totalRelatedRecords = purchaseCount + salesCount + returnsCount;
    
    // 构建警告消息
    String warningMessage = '您确定要删除以下产品吗？\n\n'
        '产品名称: ${product['name']}\n'
        '描述: ${product['description'] ?? '无描述'}\n'
        '库存: ${_formatNumber(product['stock'])} ${product['unit']}';
    
    if (totalRelatedRecords > 0) {
      warningMessage += '\n\n⚠️ 警告：删除此产品将同时删除以下关联记录：';
      if (purchaseCount > 0) {
        warningMessage += '\n• 采购记录: $purchaseCount 条';
      }
      if (salesCount > 0) {
        warningMessage += '\n• 销售记录: $salesCount 条';
      }
      if (returnsCount > 0) {
        warningMessage += '\n• 退货记录: $returnsCount 条';
      }
      warningMessage += '\n\n此操作不可恢复，请谨慎操作！';
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
          // 保持原来的确认/取消按钮位置
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
      // 获取产品数据用于日志记录
      final productData = Map<String, dynamic>.from(product);
      
      // 级联删除所有相关记录
      final deletedPurchases = await db.delete('purchases', where: 'productName = ? AND userId = ?', whereArgs: [productName, userId]);
      final deletedSales = await db.delete('sales', where: 'productName = ? AND userId = ?', whereArgs: [productName, userId]);
      final deletedReturns = await db.delete('returns', where: 'productName = ? AND userId = ?', whereArgs: [productName, userId]);
      // 删除产品本身
      await db.delete('products', where: 'id = ? AND userId = ?', whereArgs: [product['id'], userId]);
      
      // 记录日志
      if (totalRelatedRecords > 0) {
        productData['cascade_info'] = {
          'operation': 'product_cascade_delete',
          'deleted_purchases': deletedPurchases,
          'deleted_sales': deletedSales,
          'deleted_returns': deletedReturns,
          'total_deleted': deletedPurchases + deletedSales + deletedReturns,
        };
      }
      await AuditLogService().logDelete(
        entityType: EntityType.product,
        userId: userId,
        username: username,
        entityId: product['id'] as int,
        entityName: productName,
        oldData: productData,
      );
      
      _fetchProducts();
      
      // 显示删除成功提示
      if (totalRelatedRecords > 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除产品"$productName"及其 $totalRelatedRecords 条关联记录'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
          title: Text('产品', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
          actions: [
            IconButton(
              icon: Icon(_showDeleteButtons ? Icons.cancel : Icons.delete),
              tooltip: _showDeleteButtons ? '取消' : '显示删除按钮',
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
                  Icon(Icons.shopping_bag, color: Colors.green[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '产品列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Spacer(),
                  Text(
                    '共 ${_filteredProducts.length} 个品种',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // 添加供应商筛选下拉框
            if (_suppliers.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.filter_list, size: 18, color: Colors.green[700]),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSupplierFilter,
                            hint: Text('按供应商筛选', style: TextStyle(fontSize: 14)),
                            isExpanded: true,
                            icon: Icon(Icons.arrow_drop_down, color: Colors.green),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedSupplierFilter = newValue;
                                _filterProducts();
                              });
                            },
                            items: [
                              DropdownMenuItem<String>(
                                value: null,
                                child: Text('全部供应商'),
                              ),
                              DropdownMenuItem<String>(
                                value: '未分配供应商',
                                child: Text('未分配供应商', style: TextStyle(color: Colors.grey[600])),
                              ),
                              ..._suppliers.map<DropdownMenuItem<String>>((supplier) {
                                return DropdownMenuItem<String>(
                                  value: supplier['name'],
                                  child: Text(supplier['name']),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          Expanded(
              child: _filteredProducts.isEmpty
                  ? SingleChildScrollView(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                    children: [
                          Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的产品' : '暂无产品',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加产品',
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
                      itemCount: _filteredProducts.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _showProductDetailDialog(product),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: Text(
                                        product['name'].substring(0, 1),
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[800],
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
                                          product['name'], 
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Text(
                                                '库存: ${_formatNumber(product['stock'])} ${product['unit']}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                              ),
                                              // 显示供应商信息
                                              if (product['supplierId'] != null && product['supplierId'] != 0) ...[
                                                SizedBox(width: 8),
                                                Icon(Icons.business, size: 12, color: Colors.blue[700]),
                                                SizedBox(width: 2),
                                                Expanded(
                                                  child: Text(
                                                    _getSupplierName(product['supplierId']),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.blue[700],
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // 无论是否有备注，都保留相同高度的区域
                                        Container(
                                          height: 18, // 设置固定高度
                                          child: (product['description'] ?? '').toString().isNotEmpty
                                            ? Text(
                                                product['description'],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                      ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              )
                                            : null, // 无备注时不显示内容，但保留高度
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 编辑按钮
                      IconButton(
                                    icon: Icon(Icons.edit, color: Colors.green),
                                    tooltip: '编辑',
                                    onPressed: () => _editProduct(product),
                                    constraints: BoxConstraints(),
                                    padding: EdgeInsets.all(8),
                                  ),
                                  // 删除按钮（仅在删除模式下显示）
                                  if (_showDeleteButtons)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        tooltip: '删除',
                        onPressed: () => _deleteProduct(product),
                                        constraints: BoxConstraints(),
                                        padding: EdgeInsets.all(8),
                                      ),
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
                        hintText: '搜索产品...',
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
                          borderSide: BorderSide(color: Colors.green),
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
        onPressed: _addProduct,
        child: Icon(Icons.add),
                    tooltip: '添加产品',
                    backgroundColor: Colors.green,
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

  // 格式化数字显示，如果是整数则不显示小数点，如果是小数则显示小数部分
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }
  
  // 获取供应商名称
  String _getSupplierName(int? supplierId) {
    if (supplierId == null || supplierId == 0) return '未分配';
    final supplier = _suppliers.firstWhere(
      (s) => s['id'] == supplierId,
      orElse: () => {'name': '未知'},
    );
    return supplier['name'];
  }
}

class ProductDialog extends StatefulWidget {
  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> suppliers;

  ProductDialog({this.product, required this.suppliers});

  @override
  _ProductDialogState createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _selectedUnit = '斤'; // 默认单位
  String? _selectedSupplierId; // 选中的供应商ID
  String? _missingSupplierInfo; // 记录已删除的供应商信息用于显示警告

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!['name'];
      _descriptionController.text = widget.product!['description'] ?? '';
      _stockController.text = widget.product!['stock'].toString();
      _selectedUnit = widget.product!['unit'];
      // 加载供应商ID
      if (widget.product!['supplierId'] != null && widget.product!['supplierId'] != 0) {
        final supplierId = widget.product!['supplierId'].toString();
        // 检查供应商是否存在于当前供应商列表中
        final supplierExists = widget.suppliers.any((s) => s['id'].toString() == supplierId);
        if (supplierExists) {
          _selectedSupplierId = supplierId;
        } else {
          // 供应商已被删除，设为null并记录警告信息
          _selectedSupplierId = null;
          _missingSupplierInfo = '原供应商(ID: $supplierId)已被删除';
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.product == null ? '添加产品' : '编辑产品',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
          children: [
              TextFormField(
              controller: _nameController,
                decoration: InputDecoration(
                  labelText: '产品名称',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.shopping_bag, color: Colors.green),
            ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入产品名称';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              // 供应商已删除警告
              if (_missingSupplierInfo != null)
                Container(
                  margin: EdgeInsets.only(bottom: 16),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_missingSupplierInfo，请重新选择供应商',
                          style: TextStyle(color: Colors.orange[800], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              // 添加供应商选择
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedSupplierId != null ? Colors.black : Colors.grey[400]!,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.business, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSupplierId,
                          hint: Text('选择供应商（可选）', style: TextStyle(fontSize: 14)),
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.green),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupplierId = newValue;
                              // 用户选择后清除警告
                              _missingSupplierInfo = null;
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text('未分配供应商', style: TextStyle(color: Colors.grey[600])),
                            ),
                            ...widget.suppliers.map<DropdownMenuItem<String>>((supplier) {
                              return DropdownMenuItem<String>(
                                value: supplier['id'].toString(),
                                child: Text(supplier['name']),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
              controller: _stockController,
                      decoration: InputDecoration(
                        labelText: '库存',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        prefixIcon: Icon(Icons.inventory, color: Colors.green),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入库存';
                        }
                        if (double.tryParse(value) == null) {
                          return '请输入有效数字';
                        }
                        if (double.parse(value) < 0) {
                          return '库存不能为负数';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[400]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
              value: _selectedUnit,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: Colors.green),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedUnit = newValue!;
                });
              },
              items: <String>['斤', '公斤', '袋', '件', '瓶']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
            ),
              SizedBox(height: 16),
              TextFormField(
              controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.description, color: Colors.green),
            ),
                maxLines: 2,
              ),
          ],
          ),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      actions: [
        // 保持原来的保存/取消按钮位置
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                final product = {
                    'name': _nameController.text.trim(),
                    'description': _descriptionController.text.trim(),
                  'stock': double.tryParse(_stockController.text) ?? 0.0,
                  'unit': _selectedUnit,
                  'supplierId': _selectedSupplierId != null ? int.tryParse(_selectedSupplierId!) : null,
                };
                  if (widget.product != null) {
                    product['id'] = widget.product!['id'];
                  }
                Navigator.of(context).pop(product);
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
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}