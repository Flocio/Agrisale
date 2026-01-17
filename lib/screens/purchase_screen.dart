// lib/screens/purchase_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseScreen extends StatefulWidget {
  @override
  _PurchaseScreenState createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _showDeleteButtons = false;
  
  // 添加搜索相关的状态变量
  List<Map<String, dynamic>> _filteredPurchases = [];
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // 添加高级搜索相关变量
  bool _showAdvancedSearch = false;
  String? _selectedProductFilter;
  String? _selectedSupplierFilter;
  DateTimeRange? _selectedDateRange;
  final ValueNotifier<List<String>> _activeFilters = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _fetchData();
    
    // 添加搜索框文本监听
    _searchController.addListener(() {
      _filterPurchases();
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _activeFilters.dispose();
    super.dispose();
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

  // 重置所有过滤条件
  void _resetFilters() {
    setState(() {
      _selectedProductFilter = null;
      _selectedSupplierFilter = null;
      _selectedDateRange = null;
      _searchController.clear();
      _activeFilters.value = [];
      _filteredPurchases = List.from(_purchases);
      _isSearching = false;
      _showAdvancedSearch = false;
    });
  }

  // 更新搜索条件并显示活跃的过滤条件
  void _updateActiveFilters() {
    List<String> filters = [];
    
    if (_selectedProductFilter != null) {
      filters.add('产品: $_selectedProductFilter');
    }
    
    if (_selectedSupplierFilter != null) {
      filters.add('供应商: $_selectedSupplierFilter');
    }
    
    if (_selectedDateRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end);
      filters.add('日期: $startDate 至 $endDate');
    }
    
    _activeFilters.value = filters;
  }

  // 添加过滤采购记录的方法 - 增强版
  void _filterPurchases() {
    final searchText = _searchController.text.trim();
    final searchTerms = searchText.toLowerCase().split(' ').where((term) => term.isNotEmpty).toList();
    
    setState(() {
      // 开始筛选
      List<Map<String, dynamic>> result = List.from(_purchases);
      bool hasFilters = false;
      
      // 关键词搜索
      if (searchTerms.isNotEmpty) {
        hasFilters = true;
        result = result.where((purchase) {
          final productName = purchase['productName'].toString().toLowerCase();
          final supplierName = _suppliers
              .firstWhere(
                (s) => s['id'] == purchase['supplierId'],
                orElse: () => {'name': '未知供应商'},
              )['name']
              .toString()
              .toLowerCase();
          final date = purchase['purchaseDate'].toString().toLowerCase();
          final note = (purchase['note'] ?? '').toString().toLowerCase();
          final quantity = purchase['quantity'].toString().toLowerCase();
          final price = purchase['totalPurchasePrice'].toString().toLowerCase();
          
          // 检查所有搜索词是否都匹配
          return searchTerms.every((term) =>
            productName.contains(term) ||
            supplierName.contains(term) ||
            date.contains(term) ||
            note.contains(term) ||
            quantity.contains(term) ||
            price.contains(term)
          );
        }).toList();
      }
      
      // 产品筛选
      if (_selectedProductFilter != null) {
        hasFilters = true;
        result = result.where((purchase) => 
          purchase['productName'] == _selectedProductFilter).toList();
      }
      
      // 供应商筛选
      if (_selectedSupplierFilter != null) {
        hasFilters = true;
        final selectedSupplierId = _suppliers
            .firstWhere(
              (s) => s['name'] == _selectedSupplierFilter,
              orElse: () => {'id': -1},
            )['id'];
        
        result = result.where((purchase) => 
          purchase['supplierId'] == selectedSupplierId).toList();
      }
      
      // 日期范围筛选
      if (_selectedDateRange != null) {
        hasFilters = true;
        result = result.where((purchase) {
          final purchaseDate = DateTime.parse(purchase['purchaseDate']);
          return purchaseDate.isAfter(_selectedDateRange!.start.subtract(Duration(days: 1))) &&
                 purchaseDate.isBefore(_selectedDateRange!.end.add(Duration(days: 1)));
        }).toList();
      }
      
      _isSearching = hasFilters;
      _filteredPurchases = result;
      _updateActiveFilters();
    });
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 只获取当前用户的数据
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        final purchases = await db.query('purchases', where: 'userId = ?', whereArgs: [userId], orderBy: 'id DESC');
        
        setState(() {
          _products = products;
          _suppliers = suppliers;
          _purchases = purchases;
          _filteredPurchases = purchases; // 初始时过滤列表等于全部列表
        });
      }
    }
  }

  Future<void> _addPurchase() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchaseDialog(products: _products, suppliers: _suppliers),
    );
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          final product = _products.firstWhere((p) => p['name'] == result['productName']);
          final quantity = result['quantity'] as double;
          
          // 如果是负数（采购退货），检查库存是否足够
          if (quantity < 0) {
            final currentStock = product['stock'] as double;
            if (currentStock < quantity.abs()) {
              _showErrorDialog('库存不足！当前库存: ${_formatNumber(currentStock)} ${product['unit']}，无法退货 ${_formatNumber(quantity.abs())} ${product['unit']}');
              return;
            }
          }
          
          // 添加userId到采购记录
          result['userId'] = userId;
          await db.insert('purchases', result);

          // Update product stock - 采购为正数增加库存，退货为负数减少库存
          final newStock = product['stock'] + quantity;
          await db.update(
            'products',
            {'stock': newStock},
            where: 'id = ? AND userId = ?',
            whereArgs: [product['id'], userId],
          );

          _fetchData();
        }
      }
    }
  }

  Future<void> _editPurchase(Map<String, dynamic> purchase) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PurchaseDialog(
        products: _products,
        suppliers: _suppliers,
        existingPurchase: purchase,
      ),
    );
    
    if (result != null) {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          final oldProductName = purchase['productName'] as String;
          final newProductName = result['productName'] as String;
          final oldQuantity = purchase['quantity'] as double;
          final newQuantity = result['quantity'] as double;
          
          // 检查是否更改了产品
          final isProductChanged = oldProductName != newProductName;
          
          if (isProductChanged) {
            // 产品更改：需要分别处理两个产品的库存
            final oldProduct = _products.firstWhere((p) => p['name'] == oldProductName);
            final newProduct = _products.firstWhere((p) => p['name'] == newProductName);
            
            // 检查原产品库存是否足够恢复（如果原数量为正数，恢复时需要减少库存）
            if (oldQuantity > 0) {
              final oldProductStock = oldProduct['stock'] as double;
              if (oldProductStock < oldQuantity) {
                _showErrorDialog('无法更改产品！原产品 ${oldProduct['name']} 当前库存: ${_formatNumber(oldProductStock)} ${oldProduct['unit']}，小于原采购数量 ${_formatNumber(oldQuantity)} ${oldProduct['unit']}');
                return;
              }
            }
            
            // 检查新产品库存是否足够（如果新数量为负，即采购退货）
            if (newQuantity < 0) {
              final newProductStock = newProduct['stock'] as double;
              if (newProductStock < newQuantity.abs()) {
                _showErrorDialog('库存不足！${newProduct['name']} 当前库存: ${_formatNumber(newProductStock)} ${newProduct['unit']}，无法退货 ${_formatNumber(newQuantity.abs())} ${newProduct['unit']}');
                return;
              }
            }
            
            // 恢复原产品库存（减去原数量）
            final oldProductNewStock = oldProduct['stock'] - oldQuantity;
            await db.update(
              'products',
              {'stock': oldProductNewStock},
              where: 'id = ? AND userId = ?',
              whereArgs: [oldProduct['id'], userId],
            );
            
            // 更新新产品库存（加上新数量）
            final newProductNewStock = newProduct['stock'] + newQuantity;
            await db.update(
              'products',
              {'stock': newProductNewStock},
              where: 'id = ? AND userId = ?',
              whereArgs: [newProduct['id'], userId],
            );
          } else {
            // 产品未更改：只需要处理数量差值
            final product = _products.firstWhere((p) => p['name'] == newProductName);
            final quantityDiff = newQuantity - oldQuantity;
            
            // 如果数量差为负（减少库存），需要检查库存是否足够
            if (quantityDiff < 0) {
              final currentStock = product['stock'] as double;
              if (currentStock < quantityDiff.abs()) {
                _showErrorDialog('库存不足！当前库存: ${_formatNumber(currentStock)} ${product['unit']}，无法减少 ${_formatNumber(quantityDiff.abs())} ${product['unit']}');
                return;
              }
            }
            
            // 更新产品库存 - 加上数量差值
            final newStock = product['stock'] + quantityDiff;
            await db.update(
              'products',
              {'stock': newStock},
              where: 'id = ? AND userId = ?',
              whereArgs: [product['id'], userId],
            );
          }
          
          // 更新采购记录
          await db.update(
            'purchases',
            {
              'productName': result['productName'],
              'quantity': result['quantity'],
              'supplierId': result['supplierId'],
              'purchaseDate': result['purchaseDate'],
              'totalPurchasePrice': result['totalPurchasePrice'],
              'note': result['note'],
            },
            where: 'id = ? AND userId = ?',
            whereArgs: [purchase['id'], userId],
          );

          _fetchData();
        }
      }
    }
  }

  void _showNoteDialog(Map<String, dynamic> purchase) {
    final _noteController = TextEditingController(text: purchase['note']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('备注'),
        content: TextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: '编辑备注',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          maxLines: null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  final db = await DatabaseHelper().database;
                  final prefs = await SharedPreferences.getInstance();
                  final username = prefs.getString('current_username');
                  
                  if (username != null) {
                    final userId = await DatabaseHelper().getCurrentUserId(username);
                    if (userId != null) {
                      await db.update(
                        'purchases',
                        {'note': _noteController.text},
                        where: 'id = ? AND userId = ?',
                        whereArgs: [purchase['id'], userId],
                      );
                      Navigator.of(context).pop();
                      _fetchData(); // Refresh data
                    }
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
      ),
    );
  }

  Future<void> _deletePurchase(Map<String, dynamic> purchase) async {
    final supplier = _suppliers.firstWhere(
          (s) => s['id'] == purchase['supplierId'],
      orElse: () => {'name': '未知供应商'},
    );
    final product = _products.firstWhere(
      (p) => p['name'] == purchase['productName'],
      orElse: () => {'unit': ''},
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text(
          '您确定要删除以下采购记录吗？\n\n'
              '产品名称: ${purchase['productName']}\n'
              '数量: ${_formatNumber(purchase['quantity'])} ${product['unit']}\n'
              '供应商: ${supplier['name']}\n'
              '日期: ${purchase['purchaseDate']}',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('确认'),
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
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // Rollback stock - 删除采购记录时反向操作库存
          // 如果原记录是正数采购，删除时减少库存；如果是负数退货，删除时增加库存
          final quantity = purchase['quantity'] as double;
          final newStock = (product['stock'] as double) - quantity;
          
          // 检查删除后库存是否会变负
          if (newStock < 0) {
            _showErrorDialog('无法删除！删除此采购记录后库存将变为负数 (${_formatNumber(newStock)} ${product['unit']})。\n\n请先调整其他相关记录。');
            return;
          }
          
          // 只删除当前用户的采购记录
          await db.delete('purchases', where: 'id = ? AND userId = ?', whereArgs: [purchase['id'], userId]);

          await db.update(
            'products',
            {'stock': newStock},
            where: 'id = ? AND userId = ?',
            whereArgs: [product['id'], userId],
          );

          _fetchData();
        }
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('错误'),
        content: Text(message),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  // 显示高级搜索对话框
  void _showAdvancedSearchDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,  // 添加此行以支持更大的高度
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(  // 添加滚动视图
              child: Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '高级搜索',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _resetFilters();
                          },
                          child: Text('重置所有'),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    
                    // 产品筛选
                    Text('按产品筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedProductFilter,
                        hint: Text('选择产品'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部产品'),
                          ),
                          ..._products.map((product) => DropdownMenuItem<String?>(
                            value: product['name'],
                            child: Text(product['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedProductFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 供应商筛选
                    Text('按供应商筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedSupplierFilter,
                        hint: Text('选择供应商'),
                        underline: SizedBox(),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('全部供应商'),
                          ),
                          ..._suppliers.map((supplier) => DropdownMenuItem<String?>(
                            value: supplier['name'],
                            child: Text(supplier['name']),
                          )).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedSupplierFilter = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 16),
                    
                    // 日期范围筛选
                    Text('按日期筛选:', style: TextStyle(fontWeight: FontWeight.w500)),
                    SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final initialDateRange = _selectedDateRange ??
                            DateTimeRange(
                              start: now.subtract(Duration(days: 30)),
                              end: now,
                            );
                        
                        final pickedRange = await showDateRangePicker(
                          context: context,
                          initialDateRange: initialDateRange,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.green,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedDateRange != null
                                  ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} 至 ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                                  : '选择日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null
                                    ? Colors.black
                                    : Colors.grey.shade600,
                              ),
                            ),
                            Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // 确认按钮
                    Padding(  // 添加底部内边距
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,  // 设定按钮高度
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _filterPurchases();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            '应用筛选',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
          title: Text('采购', style: TextStyle(
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
          Expanded(
              child: _filteredPurchases.isEmpty
                  ? SingleChildScrollView(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart, size: 64, color: Colors.grey[400]),
                          SizedBox(height: 16),
                          Text(
                            _isSearching ? '没有匹配的采购记录' : '暂无采购记录',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '点击下方 + 按钮添加采购记录',
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
                      itemCount: _filteredPurchases.length,
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemBuilder: (context, index) {
                        final purchase = _filteredPurchases[index];
                final supplier = _suppliers.firstWhere(
                      (s) => s['id'] == purchase['supplierId'],
                  orElse: () => {'name': '未知供应商'},
                );
                final product = _products.firstWhere(
                      (p) => p['name'] == purchase['productName'],
                  orElse: () => {'unit': ''},
                );
                        
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          // 添加采购/退货标识
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: (purchase['quantity'] as double) >= 0 ? Colors.green[100] : Colors.red[100],
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              (purchase['quantity'] as double) >= 0 ? '采购' : '退货',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: (purchase['quantity'] as double) >= 0 ? Colors.green[800] : Colors.red[800],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        purchase['productName'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          purchase['purchaseDate'],
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.edit, color: Colors.orange),
                                              tooltip: '编辑',
                                              onPressed: () => _editPurchase(purchase),
                                              padding: EdgeInsets.zero,
                                              constraints: BoxConstraints(),
                                              iconSize: 18,
                                            ),
                                            if (_showDeleteButtons)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8),
                                                child: IconButton(
                                                  icon: Icon(Icons.delete, color: Colors.red),
                                                  tooltip: '删除',
                                                  onPressed: () => _deletePurchase(purchase),
                                                  padding: EdgeInsets.zero,
                                                  constraints: BoxConstraints(),
                                                  iconSize: 18,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.business, 
                                         size: 14, 
                                         color: Colors.blue[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '供应商: ${supplier['name']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2, 
                                         size: 14, 
                                         color: (purchase['quantity'] as double) >= 0 ? Colors.green[700] : Colors.red[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '数量: ${(purchase['quantity'] as double) >= 0 ? '' : '-'}${_formatNumber((purchase['quantity'] as double).abs())} ${product['unit']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        // 退货记录的“数量”文字也保持和采购一致：黑色细体
                                        color: Colors.black87,
                                        fontWeight: FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.attach_money, 
                                         size: 14, 
                                         color: Colors.amber[700]),
                                    SizedBox(width: 4),
                                    Text(
                                      '总进价: ${purchase['totalPurchasePrice']}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                                if (purchase['note'] != null && purchase['note'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Row(
                                      children: [
                                        Icon(Icons.note, 
                                             size: 14, 
                                             color: Colors.purple),
                                        SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '备注: ${purchase['note']}',
                                            style: TextStyle(
                                              // 备注字体与“供应商/数量/总进价”一致：同字号、黑色、非斜体
                                              fontSize: 13,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(height: 4),
                              ],
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
              child: Column(
                children: [
                  // 活跃过滤条件显示
                  ValueListenableBuilder<List<String>>(
                    valueListenable: _activeFilters,
                    builder: (context, filters, child) {
                      if (filters.isEmpty) return SizedBox.shrink();
                      
                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[100]!)
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.filter_list, size: 16, color: Colors.green),
                            SizedBox(width: 4),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: filters.map((filter) {
                                    return Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Chip(
                                        label: Text(filter, style: TextStyle(fontSize: 12)),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                        backgroundColor: Colors.green[100],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.clear, size: 16, color: Colors.green),
                              onPressed: _resetFilters,
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      // 搜索框
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索采购记录...',
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
                      SizedBox(width: 8),
                      // 高级搜索按钮
                      IconButton(
                        onPressed: _showAdvancedSearchDialog,
                        icon: Icon(
                          Icons.tune,
                          color: _showAdvancedSearch ? Colors.green : Colors.grey[600],
                          size: 20,
                      ),
                        tooltip: '高级搜索',
                      ),
                      SizedBox(width: 8),
                      // 添加按钮
                      FloatingActionButton(
                        onPressed: _addPurchase,
                        child: Icon(Icons.add),
                        tooltip: '添加采购',
                        backgroundColor: Colors.green,
                        mini: false,
                        ),
                    ],
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

class PurchaseDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> suppliers;
  final Map<String, dynamic>? existingPurchase; // 添加此参数用于编辑模式

  PurchaseDialog({
    required this.products,
    required this.suppliers,
    this.existingPurchase,
  });

  @override
  _PurchaseDialogState createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  String? _selectedProduct;
  String? _selectedSupplier;
  final _quantityController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  double _totalPurchasePrice = 0.0;
  bool _isEditMode = false;
  String? _missingProductName; // 记录不存在的产品名称
  String? _missingSupplierInfo; // 记录已删除的供应商信息

  @override
  void initState() {
    super.initState();
    // 如果是编辑模式，预填充数据
    if (widget.existingPurchase != null) {
      _isEditMode = true;
      final purchase = widget.existingPurchase!;
      final productName = purchase['productName'] as String;
      
      // 检查产品是否存在于当前产品列表中
      final productExists = widget.products.any((p) => p['name'] == productName);
      if (productExists) {
        _selectedProduct = productName;
      } else {
        // 产品不存在，记录产品名称以便显示警告
        _selectedProduct = null;
        _missingProductName = productName;
      }
      
      // 检查供应商是否存在
      final supplierId = purchase['supplierId'];
      if (supplierId != null && supplierId != 0) {
        final supplierIdStr = supplierId.toString();
        final supplierExists = widget.suppliers.any((s) => s['id'].toString() == supplierIdStr);
        if (supplierExists) {
          _selectedSupplier = supplierIdStr;
        } else {
          _selectedSupplier = null;
          _missingSupplierInfo = '原供应商(ID: $supplierIdStr)已被删除';
        }
      } else {
        // supplierId 为 0 或 null，表示供应商已被删除
        _selectedSupplier = null;
        if (supplierId == 0) {
          _missingSupplierInfo = '原供应商已被删除';
        }
      }
      
      _quantityController.text = purchase['quantity'].toString();
      _noteController.text = purchase['note'] ?? '';
      _selectedDate = DateTime.parse(purchase['purchaseDate']);
      
      // 根据总价和数量计算单价
      final quantity = purchase['quantity'] as double;
      final totalPrice = purchase['totalPurchasePrice'] as double;
      if (quantity != 0) {
        final unitPrice = totalPrice / quantity;
        _purchasePriceController.text = unitPrice.abs().toString();
      }
      _totalPurchasePrice = totalPrice;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate)
      setState(() {
        _selectedDate = picked;
      });
  }

  void _calculateTotalPrice() {
    final purchasePrice = double.tryParse(_purchasePriceController.text) ?? 0.0;
    final quantity = double.tryParse(_quantityController.text) ?? 0.0;
    setState(() {
      _totalPurchasePrice = purchasePrice * quantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    String unit = '';
    if (_selectedProduct != null) {
      final product = widget.products.firstWhere(
        (p) => p['name'] == _selectedProduct,
        orElse: () => <String, dynamic>{'unit': ''},
      );
      unit = product['unit'] ?? '';
    }

    final int? selectedSupplierId = int.tryParse(_selectedSupplier ?? '');
    final List<Map<String, dynamic>> filteredProducts = selectedSupplierId != null
        ? widget.products.where((p) {
            final dynamic raw = p['supplierId'];
            final int? sid = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
            return sid == selectedSupplierId;
          }).toList()
        : widget.products;

    return AlertDialog(
      title: Text(
        _isEditMode ? '编辑采购/退货' : '添加采购/退货',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 产品不存在警告
            if (_missingProductName != null)
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
                        '原产品"$_missingProductName"已不存在，请重新选择产品',
                        style: TextStyle(color: Colors.orange[800], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
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
            // 先选择供应商（手动选择），再选择产品（产品列表按供应商过滤）
            DropdownButtonFormField<String>(
              value: _selectedSupplier,
              decoration: InputDecoration(
                labelText: '选择供应商',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.business, color: Colors.green),
              ),
              isExpanded: true,
              items: widget.suppliers.map((supplier) {
                return DropdownMenuItem<String>(
                  value: supplier['id'].toString(),
                  child: Text(supplier['name']),
                );
              }).toList(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请选择供应商';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _selectedSupplier = value;
                  _missingSupplierInfo = null; // 用户选择后清除警告

                  // 如果当前已选产品不属于该供应商，则清空产品选择
                  if (_selectedProduct != null) {
                    final p = widget.products.firstWhere(
                      (p) => p['name'] == _selectedProduct,
                      orElse: () => <String, dynamic>{},
                    );
                    if (p.isEmpty) {
                      _selectedProduct = null;
                    } else {
                      final dynamic raw = p['supplierId'];
                      final int? sid = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
                      final int? selectedSid = int.tryParse(_selectedSupplier ?? '');
                      // sid 为 null/0 代表未分配供应商；或者 sid != selectedSid，都必须清空产品
                      if (selectedSid != null && (sid == null || sid == 0 || sid != selectedSid)) {
                        _selectedProduct = null;
                      }
                    }
                  }
                });
              },
            ),
            SizedBox(height: 16),

            DropdownButtonFormField<String>(
              value: _selectedProduct,
                decoration: InputDecoration(
                  labelText: '选择产品',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.inventory, color: Colors.green),
                ),
                isExpanded: true,
              items: filteredProducts.map((product) {
                return DropdownMenuItem<String>(
                  value: product['name'],
                  child: Text(product['name']),
                );
              }).toList(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请选择产品';
                  }
                  return null;
                },
              onChanged: (value) {
                setState(() {
                  _selectedProduct = value;
                  // 保留原有行为：如果用户未先选供应商，则根据产品自动同步供应商
                  if (_selectedSupplier == null && value != null) {
                    final product = widget.products.firstWhere(
                      (p) => p['name'] == value,
                      orElse: () => <String, dynamic>{},
                    );
                    if (product.isNotEmpty && product['supplierId'] != null && product['supplierId'] != 0) {
                      _selectedSupplier = product['supplierId'].toString();
                    }
                  }
                });
              },
            ),
              SizedBox(height: 16),
              
              // “正数/负数含义”提示放在供应商框和数量/进价之间
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '正数表示采购入库，负数表示采购退货',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _quantityController,
                          decoration: InputDecoration(
                            labelText: '数量',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: Icon(Icons.format_list_numbered, color: Colors.green),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入数量';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) == 0) {
                              return '数量不能为0';
                            }
                            return null;
                          },
                          onChanged: (value) => _calculateTotalPrice(),
                        ),
                        SizedBox(height: 6),
                        Center(
                          child: Text(
                            unit.isNotEmpty ? '单位：$unit' : '单位：',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: _purchasePriceController,
                          decoration: InputDecoration(
                            labelText: '进价',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入进价';
                            }
                            if (double.tryParse(value) == null) {
                              return '请输入有效数字';
                            }
                            if (double.parse(value) < 0) {
                              return '进价不能为负数';
                            }
                            return null;
                          },
                          onChanged: (value) => _calculateTotalPrice(),
                        ),
                        SizedBox(height: 6),
                        Center(
                          child: Text(
                            unit.isNotEmpty ? '元 / $unit' : '元 / 单位',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // i. 自动显示总进价（绿色框）
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[100]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '总进价:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      // 仅修正显示：负数金额必须显示为 -¥{数字}
                      _totalPurchasePrice < 0
                          ? '-¥${_totalPurchasePrice.abs()}'
                          : '¥$_totalPurchasePrice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
              ],
            ),
              ),

              SizedBox(height: 16),

              // ii. 采购日期
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: '采购日期',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 16),

              // iii. 备注
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  prefixIcon: Icon(Icons.note, color: Colors.green),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  // 额外健壮性校验：产品必须已分配供应商，且与所选供应商一致
                  final int? selectedSid = int.tryParse(_selectedSupplier ?? '');
                  if (_selectedProduct != null && selectedSid != null) {
                    final Map<String, dynamic> p = widget.products.firstWhere(
                      (p) => p['name'] == _selectedProduct,
                      orElse: () => <String, dynamic>{},
                    );
                    
                    if (p.isEmpty) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('保存失败'),
                          content: Text('所选产品不存在，请刷新页面后重试。'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('确定'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                    
                    final dynamic raw = p['supplierId'];
                    final int? productSid =
                        raw is int ? raw : int.tryParse(raw?.toString() ?? '');

                    if (productSid == null || productSid == 0) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('保存失败'),
                          content: Text('该产品未分配供应商，请先为产品分配供应商，或选择其他产品。'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('确定'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    if (productSid != selectedSid) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('保存失败'),
                          content: Text('所选产品与供应商不匹配，请重新选择正确的供应商或产品。'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text('确定'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                  }

                final purchase = {
                  'productName': _selectedProduct,
                  'quantity': double.tryParse(_quantityController.text) ?? 0.0,
                    'supplierId': int.tryParse(_selectedSupplier ?? '') ?? 0,
                  'purchaseDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  'totalPurchasePrice': _totalPurchasePrice,
                    'note': _noteController.text,
                };
                Navigator.of(context).pop(purchase);
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
}