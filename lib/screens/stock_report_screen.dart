// lib/screens/stock_report_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import 'product_detail_screen.dart'; // 导入产品详情屏幕
import 'package:shared_preferences/shared_preferences.dart';

class StockReportScreen extends StatefulWidget {
  @override
  _StockReportScreenState createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  List<Map<String, dynamic>> _suppliers = []; // 添加供应商列表
  TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  int? _selectedSupplierId; // 选中的供应商ID，null表示所有供应商

  @override
  void initState() {
    super.initState();
    _fetchData();
    
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
    if (supplierId == null) return '未分配';
    final supplier = _suppliers.firstWhere(
      (s) => s['id'] == supplierId,
      orElse: () => {'name': '未知'},
    );
    return supplier['name'] as String;
  }

  Future<void> _fetchData() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        // 获取当前用户的产品和供应商
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _products = products;
          _filteredProducts = products;
          _suppliers = suppliers;
        });
      }
    }
  }

  // 添加过滤产品的方法
  void _filterProducts() {
    final searchText = _searchController.text.trim().toLowerCase();
    
    setState(() {
      _filteredProducts = _products.where((product) {
        // 供应商筛选
        if (_selectedSupplierId != null) {
          if (_selectedSupplierId == -1) {
            // "未分配供应商" - supplierId 为 null 或 0
            if (product['supplierId'] != null && product['supplierId'] != 0) {
              return false;
            }
          } else if (product['supplierId'] != _selectedSupplierId) {
            return false;
          }
        }
        
        // 搜索文本筛选
        if (searchText.isNotEmpty) {
          final name = product['name'].toString().toLowerCase();
          final description = (product['description'] ?? '').toString().toLowerCase();
          if (!name.contains(searchText) && !description.contains(searchText)) {
            return false;
          }
        }
        
        return true;
      }).toList();
      
      // 判断是否有筛选条件
      _isSearching = searchText.isNotEmpty || _selectedSupplierId != null;
    });
  }
  
  // 显示供应商筛选对话框
  Future<void> _showSupplierFilterDialog() async {
    // 创建选项列表：第一个是"所有供应商"，第二个是"未分配供应商"，后面是所有供应商
    // 使用 -1 表示"未分配供应商"
    final List<MapEntry<int?, String>> supplierOptions = [
      MapEntry<int?, String>(null, '所有供应商'),
      MapEntry<int?, String>(-1, '未分配供应商'),
      ..._suppliers.map((s) => MapEntry<int?, String>(s['id'] as int, s['name'] as String)),
    ];
    
    // 找到当前选中项的索引
    int currentIndex = supplierOptions.indexWhere((entry) => entry.key == _selectedSupplierId);
    if (currentIndex < 0) {
      currentIndex = 0; // 默认选中"所有供应商"
    }
    
    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择供应商'),
          content: SizedBox(
            height: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: StatefulBuilder(
                    builder: (context, setStateDialog) {
                      return CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: currentIndex),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          setStateDialog(() {
                            tempIndex = index;
                          });
                        },
                        children: supplierOptions
                            .map((entry) => Center(child: Text(entry.value)))
                            .toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null && selectedIndex >= 0 && selectedIndex < supplierOptions.length) {
      final selectedEntry = supplierOptions[selectedIndex];
      if (selectedEntry.key != _selectedSupplierId) {
        setState(() {
          _selectedSupplierId = selectedEntry.key;
        });
        _filterProducts();
      }
    }
  }

  void _showDescriptionDialog(String productName, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('产品信息'),
        content: Text(
          '产品名称: $productName\n描述: ${description.isNotEmpty ? description : '无描述'}',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'),
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
          title: Text('库存统计', style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
        ),
      body: Column(
        children: <Widget>[
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
                            _isSearching ? '没有匹配的产品' : '暂无产品库存信息',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isSearching ? '请尝试其他搜索条件' : '请先添加产品',
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
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // 库存图标
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.green[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2,
                                    color: Colors.green,
                                    size: 24,
                                  ),
                                ),
                                SizedBox(width: 16),
                                // 产品信息
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
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            '库存: ',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          Text(
                                            '${_formatNumber(product['stock'])} ${product['unit']}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // 供应商信息
                                      SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            '供应商: ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          Text(
                                            _getSupplierName(product['supplierId']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      // 备注信息（仅在有时显示）
                                      if ((product['description'] ?? '').isNotEmpty) ...[
                                        SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              '备注: ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.purple,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                product['description'] ?? '',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // 详情图标
                                Padding(
                                  padding: EdgeInsets.only(right: 28),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProductDetailScreen(
                                            product: product,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.table_chart,
                                        color: Colors.purple[400],
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                );
              },
            ),
          ),
            // 搜索栏移至底部
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
                    flex: 3,
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
                                  setState(() {
                                    _selectedSupplierId = null;
                                  });
                                  _filterProducts();
                                  FocusScope.of(context).unfocus();
                                },
                              )
                            : null,
                        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(width: 1, color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(width: 1, color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(width: 1, color: Colors.green),
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
                  // 筛选按钮（绿色漏斗icon，正方形区域）
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey[100]!,
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _showSupplierFilterDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Center(
                          child: Icon(
                            Icons.filter_alt,
                            color: Colors.green[400],
                            size: 32,
                          ),
                        ),
                      ),
                    ),
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