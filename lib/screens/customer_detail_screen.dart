// lib/screens/customer_detail_screen.dart
// 客户详细对账单页面

import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import '../services/export_service.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;
  final String customerName;

  CustomerDetailScreen({required this.customerId, required this.customerName});

  @override
  _CustomerDetailScreenState createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  List<Map<String, dynamic>> _allRecords = [];
  bool _isLoading = true;
  bool _isDescending = true;
  bool _isSummaryExpanded = true; // 汇总信息是否展开
  String _viewMode = 'unified'; // 'unified' 或 'separated' 视图模式
  bool _groupByDate = false; // 是否按日期分组折叠
  Map<String, bool> _dateExpansionState = {}; // 记录每个日期的展开/折叠状态
  
  // 添加日期筛选相关变量
  DateTimeRange? _selectedDateRange;
  
  // 滚动控制器和指示器
  ScrollController? _summaryScrollController;
  double _summaryScrollPosition = 0.0;
  double _summaryScrollMaxExtent = 0.0;
  
  // 汇总数据
  double _totalSalesAmount = 0.0;      // 销售总额
  double _totalReturnsAmount = 0.0;    // 退货总额
  double _totalIncomeAmount = 0.0;     // 实收金额（正数进账）
  double _totalRefundAmount = 0.0;     // 退款金额（负数进账的绝对值）
  double _totalDiscountAmount = 0.0;   // 优惠金额
  double _accountBalance = 0.0;        // 应收余额（正数=客户欠我们，负数=我们欠客户）
  
  int _salesCount = 0;
  int _returnsCount = 0;
  int _incomeCount = 0;
  int _refundCount = 0;

  @override
  void initState() {
    super.initState();
    _summaryScrollController = ScrollController();
    _summaryScrollController!.addListener(_onSummaryScroll);
    _fetchAllRecords();
  }

  void _onSummaryScroll() {
    if (_summaryScrollController != null && _summaryScrollController!.hasClients) {
      setState(() {
        _summaryScrollPosition = _summaryScrollController!.offset;
        _summaryScrollMaxExtent = _summaryScrollController!.position.maxScrollExtent;
      });
    }
  }

  @override
  void dispose() {
    _summaryScrollController?.removeListener(_onSummaryScroll);
    _summaryScrollController?.dispose();
    super.dispose();
  }

  // 格式化数字显示：整数显示为整数，小数显示为小数
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    double value = number is double ? number : double.tryParse(number.toString()) ?? 0.0;
    if (value == value.floor()) {
      return value.toInt().toString();
    } else {
      return value.toString();
    }
  }

  // 格式化日期显示
  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      DateTime date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  // 格式化时间显示（仅显示时分）
  String _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      DateTime date = DateTime.parse(dateStr);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _fetchAllRecords() async {
    setState(() {
      _isLoading = true;
    });

    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        List<Map<String, dynamic>> allTransactions = [];
        
        // 获取产品信息（用于获取单位）
        final products = await db.query('products', where: 'userId = ?', whereArgs: [userId]);

        // 构建日期筛选条件
        String dateFilter = '';
        List<dynamic> salesParams = [userId, widget.customerId];
        List<dynamic> returnsParams = [userId, widget.customerId];
        List<dynamic> incomeParams = [userId, widget.customerId];
        
        if (_selectedDateRange != null) {
          dateFilter = 'AND saleDate >= ? AND saleDate <= ?';
          salesParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
          salesParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          
          returnsParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
          returnsParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          
          incomeParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
          incomeParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
        }

        // 获取销售记录
        final salesRecords = await db.rawQuery('''
          SELECT * FROM sales 
          WHERE userId = ? AND customerId = ? ${dateFilter.isNotEmpty ? dateFilter : ''}
        ''', salesParams);
        
        for (var sale in salesRecords) {
          final product = products.firstWhere(
            (p) => p['name'] == sale['productName'],
            orElse: () => {'unit': ''},
          );
          
          allTransactions.add({
            'type': 'sale',
            'typeName': '销售',
            'date': sale['saleDate'],
            'productName': sale['productName'],
            'quantity': sale['quantity'],
            'unit': product['unit'] ?? '',
            'amount': (sale['totalSalePrice'] as num).toDouble(),
            'discount': 0.0,
            'paymentMethod': null,
            'employeeName': null,
            'note': sale['note'] ?? '',
            'icon': Icons.add_shopping_cart,
            'color': Colors.green,
          });
        }

        // 获取退货记录
        final returnsRecords = await db.rawQuery('''
          SELECT * FROM returns 
          WHERE userId = ? AND customerId = ? ${dateFilter.isNotEmpty ? dateFilter.replaceAll('saleDate', 'returnDate') : ''}
        ''', returnsParams);
        
        for (var returnRecord in returnsRecords) {
          final product = products.firstWhere(
            (p) => p['name'] == returnRecord['productName'],
            orElse: () => {'unit': ''},
          );
          
          allTransactions.add({
            'type': 'return',
            'typeName': '退货',
            'date': returnRecord['returnDate'],
            'productName': returnRecord['productName'],
            'quantity': returnRecord['quantity'],
            'unit': product['unit'] ?? '',
            'amount': (returnRecord['totalReturnPrice'] as num).toDouble(),
            'discount': 0.0,
            'paymentMethod': null,
            'employeeName': null,
            'note': returnRecord['note'] ?? '',
            'icon': Icons.remove_shopping_cart,
            'color': Colors.orange,
          });
        }

        // 获取进账记录
        final incomeRecords = await db.rawQuery('''
          SELECT * FROM income 
          WHERE userId = ? AND customerId = ? ${dateFilter.isNotEmpty ? dateFilter.replaceAll('saleDate', 'incomeDate') : ''}
        ''', incomeParams);
        
        for (var income in incomeRecords) {
          // 查询员工名称
          String employeeName = '';
          if (income['employeeId'] != null && income['employeeId'] != 0) {
            final employeeResult = await db.query(
              'employees',
              columns: ['name'],
              where: 'id = ?',
              whereArgs: [income['employeeId']],
            );
            if (employeeResult.isNotEmpty) {
              employeeName = employeeResult.first['name'] as String;
            }
          }

          // 根据金额正负判断是收款还是退款
          final double amount = (income['amount'] as num).toDouble();
          final bool isRefund = amount < 0;
          
          allTransactions.add({
            'type': isRefund ? 'income_negative' : 'income_positive',
            'typeName': isRefund ? '退款' : '收款',
            'date': income['incomeDate'],
            'productName': null,
            'quantity': null,
            'unit': null,
            'amount': amount,
            'discount': (income['discount'] as num?)?.toDouble() ?? 0.0,
            'paymentMethod': income['paymentMethod'],
            'employeeName': employeeName,
            'note': income['note'] ?? '',
            'icon': isRefund ? Icons.money_off : Icons.payments,
            'color': isRefund ? Colors.red : Colors.blue,
          });
        }

        // 按日期排序
        allTransactions.sort((a, b) {
          DateTime dateA = DateTime.tryParse(a['date']) ?? DateTime.now();
          DateTime dateB = DateTime.tryParse(b['date']) ?? DateTime.now();
          return _isDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
        });

        // 计算汇总数据
        _calculateSummary(allTransactions);

        setState(() {
          _allRecords = allTransactions;
          _isLoading = false;
        });
      }
    }
  }

  void _calculateSummary(List<Map<String, dynamic>> records) {
    double salesAmount = 0.0;
    double returnsAmount = 0.0;
    double incomeAmount = 0.0;
    double refundAmount = 0.0;
    double discountAmount = 0.0;
    int salesCount = 0;
    int returnsCount = 0;
    int incomeCount = 0;
    int refundCount = 0;

    for (var record in records) {
      final type = record['type'];
      final amount = (record['amount'] as num).toDouble();
      final discount = (record['discount'] as num?)?.toDouble() ?? 0.0;

      if (type == 'sale') {
        salesAmount += amount;
        salesCount++;
      } else if (type == 'return') {
        returnsAmount += amount;
        returnsCount++;
      } else if (type == 'income_positive') {
        incomeAmount += amount;
        discountAmount += discount;
        incomeCount++;
      } else if (type == 'income_negative') {
        refundAmount += amount.abs();
        refundCount++;
      }
    }

    // 应收余额 = 销售总额 - 退货总额 - 实收金额 + 退款金额 - 优惠金额
    // 优惠金额是我们主动放弃的收入，应该从应收款中减去
    double balance = salesAmount - returnsAmount - incomeAmount + refundAmount - discountAmount;

    setState(() {
      _totalSalesAmount = salesAmount;
      _totalReturnsAmount = returnsAmount;
      _totalIncomeAmount = incomeAmount;
      _totalRefundAmount = refundAmount;
      _totalDiscountAmount = discountAmount;
      _accountBalance = balance;
      _salesCount = salesCount;
      _returnsCount = returnsCount;
      _incomeCount = incomeCount;
      _refundCount = refundCount;
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isDescending = !_isDescending;
      _fetchAllRecords();
    });
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == 'unified' ? 'separated' : 'unified';
    });
  }

  void _toggleGroupByDate() {
    setState(() {
      _groupByDate = !_groupByDate;
      // 初始化展开状态：默认展开前3天的记录
      if (_groupByDate && _dateExpansionState.isEmpty) {
        final dates = _groupRecordsByDate().keys.toList();
        for (int i = 0; i < dates.length; i++) {
          _dateExpansionState[dates[i]] = i < 3; // 前3天默认展开
        }
      }
    });
  }

  Future<void> _exportData() async {
    // 添加用户信息到CSV头部
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    // 添加用户信息和导出时间
    rows.add(['客户详细对账单 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    rows.add(['客户: ${widget.customerName}']);
    
    // 添加日期筛选信息
    String dateFilterInfo;
    if (_selectedDateRange != null) {
      dateFilterInfo = '日期筛选: 日期范围 (${_formatDate(_selectedDateRange!.start.toIso8601String())} 至 ${_formatDate(_selectedDateRange!.end.toIso8601String())})';
    } else {
      dateFilterInfo = '日期筛选: 所有日期';
    }
    rows.add([dateFilterInfo]);
    
    rows.add([]); // 空行
    
    // 添加汇总信息
    rows.add(['汇总信息']);
    rows.add(['销售总额', '+¥${_totalSalesAmount.toStringAsFixed(2)}']);
    rows.add(['退货总额', '-¥${_totalReturnsAmount.toStringAsFixed(2)}']);
    rows.add(['收款金额', '-¥${_totalIncomeAmount.toStringAsFixed(2)}']);
    rows.add(['退款金额', '+¥${_totalRefundAmount.toStringAsFixed(2)}']);
    rows.add(['优惠金额', '-¥${_totalDiscountAmount.toStringAsFixed(2)}']);
    rows.add(['应收余额', '${_accountBalance >= 0 ? '+' : ''}¥${_accountBalance.toStringAsFixed(2)}']);
    rows.add([]);
    rows.add(['计算公式: 应收余额 = 销售总额 - 退货总额 - 收款金额 + 退款金额 - 优惠金额']);
    
    rows.add([]); // 空行
    
    // 添加详细记录表头
    rows.add(['日期', '类型', '产品', '数量', '单位', '金额', '优惠', '付款方式', '经手人', '备注']);

    // 添加详细记录数据
    for (var record in _allRecords) {
      final type = record['type'];
      final amount = (record['amount'] as num).toDouble();
      
      // 根据类型决定金额显示
      String amountDisplay;
      if (type == 'sale') {
        amountDisplay = '+${amount.toStringAsFixed(2)}';
      } else if (type == 'return') {
        amountDisplay = '-${amount.toStringAsFixed(2)}';
      } else if (type == 'income_positive') {
        amountDisplay = '-${amount.toStringAsFixed(2)}';
      } else {
        amountDisplay = '+${amount.abs().toStringAsFixed(2)}';
      }
      
      rows.add([
        _formatDate(record['date']),
        record['typeName'],
        record['productName'] ?? '',
        record['quantity'] != null ? _formatNumber(record['quantity']) : '',
        record['unit'] ?? '',
        amountDisplay,
        record['discount'] != null && record['discount'] > 0 
            ? (record['discount'] as num).toStringAsFixed(2) 
            : '',
        record['paymentMethod'] ?? '',
        record['employeeName'] ?? '',
        record['note'] ?? '',
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);

    // 生成文件名
    String baseFileName = '${widget.customerName}_详细对账单';

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csv,
      baseFileName: baseFileName,
    );
  }

  // 按日期分组记录
  Map<String, List<Map<String, dynamic>>> _groupRecordsByDate() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    
    for (var record in _allRecords) {
      String dateKey = _formatDate(record['date']);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(record);
    }
    
    return grouped;
  }

  // 计算每日汇总
  Map<String, dynamic> _calculateDailySummary(List<Map<String, dynamic>> records) {
    double salesAmount = 0.0;
    double returnsAmount = 0.0;
    double incomeAmount = 0.0;
    double refundAmount = 0.0;
    double discountAmount = 0.0;
    int salesCount = 0;
    int returnsCount = 0;
    int incomeCount = 0;
    int refundCount = 0;

    for (var record in records) {
      final type = record['type'];
      final amount = (record['amount'] as num).toDouble();
      final discount = (record['discount'] as num?)?.toDouble() ?? 0.0;

      if (type == 'sale') {
        salesAmount += amount;
        salesCount++;
      } else if (type == 'return') {
        returnsAmount += amount;
        returnsCount++;
      } else if (type == 'income_positive') {
        incomeAmount += amount;
        discountAmount += discount;
        incomeCount++;
      } else if (type == 'income_negative') {
        refundAmount += amount.abs();
        refundCount++;
      }
    }

    // 当日净额 = 销售 - 退货 - 收款 + 退款 - 优惠
    double dailyNet = salesAmount - returnsAmount - incomeAmount + refundAmount - discountAmount;

    return {
      'salesAmount': salesAmount,
      'returnsAmount': returnsAmount,
      'incomeAmount': incomeAmount,
      'refundAmount': refundAmount,
      'discountAmount': discountAmount,
      'dailyNet': dailyNet,
      'salesCount': salesCount,
      'returnsCount': returnsCount,
      'incomeCount': incomeCount,
      'refundCount': refundCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.customerName}的详细对账单', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(_isDescending ? Icons.arrow_downward : Icons.arrow_upward),
            tooltip: _isDescending ? '最新在前' : '最早在前',
            onPressed: _toggleSortOrder,
          ),
          IconButton(
            icon: Icon(_viewMode == 'unified' ? Icons.view_agenda : Icons.view_stream),
            tooltip: _viewMode == 'unified' ? '切换到分组视图' : '切换到统一视图',
            onPressed: _toggleViewMode,
          ),
          IconButton(
            icon: Icon(_groupByDate ? Icons.calendar_view_day : Icons.view_list),
            tooltip: _groupByDate ? '取消日期分组' : '按日期分组',
            onPressed: _toggleGroupByDate,
          ),
          IconButton(
            icon: Icon(Icons.share),
            tooltip: '导出',
            onPressed: _exportData,
          ),
        ],
      ),
      body: Column(
        children: [
          // 日期筛选
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.date_range, color: Colors.blue[700], size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: InkWell(
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
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(primary: Colors.blue),
                            ),
                            child: child!,
                          );
                        },
                      );
                      
                      if (pickedRange != null) {
                        setState(() {
                          _selectedDateRange = pickedRange;
                          _fetchAllRecords();
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDateRange != null
                                  ? '${_formatDate(_selectedDateRange!.start.toIso8601String())} 至 ${_formatDate(_selectedDateRange!.end.toIso8601String())}'
                                  : '选择日期范围',
                              style: TextStyle(
                                color: _selectedDateRange != null ? Colors.black87 : Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (_selectedDateRange != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDateRange = null;
                                  _fetchAllRecords();
                                });
                              },
                              child: Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.clear, color: Colors.blue[700], size: 18),
                              ),
                            ),
                          Icon(Icons.arrow_drop_down, color: Colors.blue[700]),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 汇总信息卡片
          _buildSummaryCard(),

          // 提示信息
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _groupByDate 
                        ? '点击日期展开/折叠详细记录。应收余额 = 销售 - 退货 - 收款 + 退款 - 优惠'
                        : '横向和纵向滑动可查看完整表格。应收余额：正数=客户欠我们，负数=我们欠客户',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 表格标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  radius: 14,
                  child: Text(
                    widget.customerName.isNotEmpty 
                        ? widget.customerName[0].toUpperCase() 
                        : '?',
                    style: TextStyle(
                      color: Colors.blue[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '客户详细对账单',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '共 ${_allRecords.length} 条记录',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),

          // 数据表格
          _isLoading
              ? Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _allRecords.isEmpty
                  ? Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  '暂无交易记录',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _selectedDateRange != null 
                                      ? '该客户在选定日期范围内没有交易记录\n请尝试调整日期范围'
                                      : '该客户还没有任何交易记录\n可在销售、退货或进账页面添加记录',
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
                      ),
                    )
                  : Expanded(
                      child: _viewMode == 'unified' 
                          ? _buildUnifiedTable() 
                          : _buildSeparatedTables(),
                    ),
          FooterWidget(),
        ],
      ),
    );
  }

  // 汇总信息卡片（完全参考 customer_records_screen.dart）
  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 客户信息和汇总信息标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text(
                      widget.customerName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSummaryExpanded = !_isSummaryExpanded;
                    });
                  },
                  child: Row(
                    children: [
                      Text(
                        '汇总信息',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 16,
                        color: Colors.blue[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(height: 16, thickness: 1),
              
              // 单行显示，支持左右滑动
              Builder(
                builder: (context) {
                  // 在布局完成后检查滚动状态
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_summaryScrollController != null && _summaryScrollController!.hasClients) {
                      final newMaxExtent = _summaryScrollController!.position.maxScrollExtent;
                      final newPosition = _summaryScrollController!.offset;
                      if (newMaxExtent != _summaryScrollMaxExtent || newPosition != _summaryScrollPosition) {
                        setState(() {
                          _summaryScrollPosition = newPosition;
                          _summaryScrollMaxExtent = newMaxExtent;
                        });
                      }
                    }
                  });
                  
                  return SingleChildScrollView(
                    controller: _summaryScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(width: 8),
                        _buildSummaryItem('销售总额', '+¥${_totalSalesAmount.toStringAsFixed(2)}', Colors.green),
                        SizedBox(width: 16),
                        _buildSummaryItem('退货总额', '-¥${_totalReturnsAmount.toStringAsFixed(2)}', Colors.orange),
                        SizedBox(width: 16),
                        _buildSummaryItem('收款金额', '-¥${_totalIncomeAmount.toStringAsFixed(2)}', Colors.blue),
                        SizedBox(width: 16),
                        _buildSummaryItem('退款金额', '+¥${_totalRefundAmount.toStringAsFixed(2)}', Colors.red),
                        SizedBox(width: 16),
                        _buildSummaryItem('优惠金额', '¥${_totalDiscountAmount.toStringAsFixed(2)}', Colors.purple),
                        SizedBox(width: 16),
                        _buildSummaryItem(
                          '应收余额', 
                          '${_accountBalance >= 0 ? '+' : '-'}¥${_accountBalance.abs().toStringAsFixed(2)}', 
                          _accountBalance >= 0 ? Colors.red : Colors.green
                        ),
                        SizedBox(width: 8),
                      ],
                    ),
                  );
                },
              ),
              
              // 滚动指示器
              SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final containerWidth = constraints.maxWidth - 24;
                  final visibleRatio = _summaryScrollMaxExtent > 0 
                      ? containerWidth / (_summaryScrollMaxExtent + containerWidth)
                      : 0.0;
                  final scrollRatio = _summaryScrollMaxExtent > 0 ? _summaryScrollPosition / _summaryScrollMaxExtent : 0.0;
                  final indicatorLeft = _summaryScrollMaxExtent > 0
                      ? scrollRatio * (containerWidth - containerWidth * visibleRatio)
                      : 0.0;
                  
                  return Container(
                    height: 4,
                    margin: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.grey[300],
                    ),
                    child: Stack(
                      children: [
                        if (_summaryScrollMaxExtent > 0)
                          Positioned(
                            left: indicatorLeft.clamp(0.0, containerWidth - containerWidth * visibleRatio),
                            child: Container(
                              width: containerWidth * visibleRatio,
                              height: 4,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: Colors.blue[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // 统一表格视图
  Widget _buildUnifiedTable() {
    if (_groupByDate) {
      return _buildGroupedUnifiedTable();
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.grey[300],
            dataTableTheme: DataTableThemeData(
              headingRowColor: MaterialStateProperty.all(Colors.blue[50]),
              dataRowColor: MaterialStateProperty.resolveWith<Color>(
                (Set<MaterialState> states) {
                  if (states.contains(MaterialState.selected))
                    return Colors.blue[100]!;
                  return states.contains(MaterialState.hovered)
                      ? Colors.grey[100]!
                      : Colors.white;
                },
              ),
            ),
          ),
          child: DataTable(
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
            dataTextStyle: TextStyle(
              color: Colors.black87,
              fontSize: 13,
            ),
            horizontalMargin: 16,
            columnSpacing: 20,
            showCheckboxColumn: false,
            dividerThickness: 1,
            columns: [
              DataColumn(label: Text('日期')),
              DataColumn(label: Text('类型')),
              DataColumn(label: Text('产品')),
              DataColumn(label: Text('数量')),
              DataColumn(label: Text('金额')),
              DataColumn(label: Text('优惠')),
              DataColumn(label: Text('付款方式')),
              DataColumn(label: Text('经手人')),
              DataColumn(label: Text('备注')),
            ],
            rows: _allRecords.map((record) {
              final type = record['type'];
              final typeName = record['typeName'];
              final color = record['color'] as Color;
              final amount = (record['amount'] as num).toDouble();
              
              // 根据类型决定金额显示
              String amountDisplay;
              if (type == 'sale') {
                amountDisplay = '+¥${amount.toStringAsFixed(2)}';
              } else if (type == 'return') {
                amountDisplay = '-¥${amount.toStringAsFixed(2)}';
              } else if (type == 'income_positive') {
                amountDisplay = '-¥${amount.toStringAsFixed(2)}';
              } else {
                amountDisplay = '+¥${amount.abs().toStringAsFixed(2)}';
              }
              
              return DataRow(
                cells: [
                  DataCell(Text(_formatDate(record['date']))),
                  DataCell(
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withOpacity(0.5), width: 1),
                      ),
                      child: Text(
                        typeName,
                        style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(record['productName'] ?? '-')),
                  DataCell(Text(record['quantity'] != null 
                      ? '${_formatNumber(record['quantity'])} ${record['unit'] ?? ''}' 
                      : '-')),
                  DataCell(
                    Text(
                      amountDisplay,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  DataCell(Text(record['discount'] != null && record['discount'] > 0
                      ? '¥${(record['discount'] as num).toStringAsFixed(2)}'
                      : '-')),
                  DataCell(Text(record['paymentMethod'] ?? '-')),
                  DataCell(Text(record['employeeName'] ?? '-')),
                  DataCell(
                    record['note'].toString().isNotEmpty
                        ? Text(
                            record['note'],
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[700],
                            ),
                          )
                        : Text('-'),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // 分组表格视图
  Widget _buildSeparatedTables() {
    if (_groupByDate) {
      return _buildGroupedSeparatedTables();
    }
    
    // 分组数据
    final businessRecords = _allRecords.where((r) => r['type'] == 'sale' || r['type'] == 'return').toList();
    final paymentRecords = _allRecords.where((r) => r['type'] == 'income_positive' || r['type'] == 'income_negative').toList();
    
    // 计算业务记录汇总
    double businessTotal = 0.0;
    for (var record in businessRecords) {
      final amount = (record['amount'] as num).toDouble();
      if (record['type'] == 'sale') {
        businessTotal += amount;
      } else {
        businessTotal -= amount;
      }
    }
    
    // 计算收付款记录汇总
    double paymentTotal = 0.0;
    for (var record in paymentRecords) {
      final amount = (record['amount'] as num).toDouble();
      if (record['type'] == 'income_positive') {
        paymentTotal -= amount;
      } else {
        paymentTotal += amount.abs();
      }
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 业务记录表格
          if (businessRecords.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.shopping_cart, color: Colors.green[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '业务记录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Text(
                      '共 ${businessRecords.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.grey[300],
                  dataTableTheme: DataTableThemeData(
                    headingRowColor: MaterialStateProperty.all(Colors.green[50]),
                    dataRowColor: MaterialStateProperty.resolveWith<Color>(
                      (Set<MaterialState> states) {
                        if (states.contains(MaterialState.selected))
                          return Colors.green[100]!;
                        return states.contains(MaterialState.hovered)
                            ? Colors.grey[100]!
                            : Colors.white;
                      },
                    ),
                  ),
                ),
                child: DataTable(
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                  dataTextStyle: TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                  horizontalMargin: 16,
                  columnSpacing: 20,
                  showCheckboxColumn: false,
                  dividerThickness: 1,
                  columns: [
                    DataColumn(label: Text('日期')),
                    DataColumn(label: Text('类型')),
                    DataColumn(label: Text('产品')),
                    DataColumn(label: Text('数量')),
                    DataColumn(label: Text('金额')),
                    DataColumn(label: Text('备注')),
                  ],
                  rows: [
                    ...businessRecords.map((record) {
                      final type = record['type'];
                      final typeName = record['typeName'];
                      final color = record['color'] as Color;
                      final amount = (record['amount'] as num).toDouble();
                      
                      String amountDisplay = type == 'sale' 
                          ? '+¥${amount.toStringAsFixed(2)}' 
                          : '-¥${amount.toStringAsFixed(2)}';
                      
                      return DataRow(
                        cells: [
                          DataCell(Text(_formatDate(record['date']))),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: color.withOpacity(0.5), width: 1),
                              ),
                              child: Text(
                                typeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(record['productName'] ?? '-')),
                          DataCell(Text(record['quantity'] != null 
                              ? '${_formatNumber(record['quantity'])} ${record['unit'] ?? ''}' 
                              : '-')),
                          DataCell(
                            Text(
                              amountDisplay,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            record['note'].toString().isNotEmpty
                                ? Text(
                                    record['note'],
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[700],
                                    ),
                                  )
                                : Text('-'),
                          ),
                        ],
                      );
                    }).toList(),
                    // 业务记录汇总行
                    DataRow(
                      color: MaterialStateProperty.all(Colors.green[50]),
                      cells: [
                        DataCell(Text('')),
                        DataCell(
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue[300]!, width: 1),
                            ),
                            child: Text(
                              '小计',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(
                          Text(
                            '${businessTotal >= 0 ? '+' : '-'}¥${businessTotal.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: businessTotal >= 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
          ],
          
          // 收付款记录表格
          if (paymentRecords.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.blue[700], size: 20),
                  SizedBox(width: 8),
                  Text(
                    '收付款记录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Text(
                      '共 ${paymentRecords.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.grey[300],
                  dataTableTheme: DataTableThemeData(
                    headingRowColor: MaterialStateProperty.all(Colors.blue[50]),
                    dataRowColor: MaterialStateProperty.resolveWith<Color>(
                      (Set<MaterialState> states) {
                        if (states.contains(MaterialState.selected))
                          return Colors.blue[100]!;
                        return states.contains(MaterialState.hovered)
                            ? Colors.grey[100]!
                            : Colors.white;
                      },
                    ),
                  ),
                ),
                child: DataTable(
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                  dataTextStyle: TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                  horizontalMargin: 16,
                  columnSpacing: 20,
                  showCheckboxColumn: false,
                  dividerThickness: 1,
                  columns: [
                    DataColumn(label: Text('日期')),
                    DataColumn(label: Text('类型')),
                    DataColumn(label: Text('金额')),
                    DataColumn(label: Text('优惠')),
                    DataColumn(label: Text('付款方式')),
                    DataColumn(label: Text('经手人')),
                    DataColumn(label: Text('备注')),
                  ],
                  rows: [
                    ...paymentRecords.map((record) {
                      final type = record['type'];
                      final typeName = record['typeName'];
                      final color = record['color'] as Color;
                      final amount = (record['amount'] as num).toDouble();
                      
                      String amountDisplay = type == 'income_positive'
                          ? '-¥${amount.toStringAsFixed(2)}'
                          : '+¥${amount.abs().toStringAsFixed(2)}';
                      
                      return DataRow(
                        cells: [
                          DataCell(Text(_formatDate(record['date']))),
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: color.withOpacity(0.5), width: 1),
                              ),
                              child: Text(
                                typeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              amountDisplay,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(Text(record['discount'] != null && record['discount'] > 0
                              ? '¥${(record['discount'] as num).toStringAsFixed(2)}'
                              : '-')),
                          DataCell(Text(record['paymentMethod'] ?? '-')),
                          DataCell(Text(record['employeeName'] ?? '-')),
                          DataCell(
                            record['note'].toString().isNotEmpty
                                ? Text(
                                    record['note'],
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[700],
                                    ),
                                  )
                                : Text('-'),
                          ),
                        ],
                      );
                    }).toList(),
                    // 收付款记录汇总行
                    DataRow(
                      color: MaterialStateProperty.all(Colors.blue[50]),
                      cells: [
                        DataCell(Text('')),
                        DataCell(
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.purple[300]!, width: 1),
                            ),
                            child: Text(
                              '小计',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${paymentTotal >= 0 ? '+' : '-'}¥${paymentTotal.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              color: paymentTotal >= 0 ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                        DataCell(Text('')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
          ],
          
          // 空状态提示
          if (businessRecords.isEmpty && paymentRecords.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                    SizedBox(height: 16),
                    Text(
                      '暂无交易记录',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 按日期分组的统一表格视图
  Widget _buildGroupedUnifiedTable() {
    final groupedRecords = _groupRecordsByDate();
    final dates = groupedRecords.keys.toList();

    return ListView.builder(
      itemCount: dates.length,
      padding: EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final date = dates[index];
        final records = groupedRecords[date]!;
        final summary = _calculateDailySummary(records);
        final isExpanded = _dateExpansionState[date] ?? false;

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 2,
          child: ExpansionTile(
            initiallyExpanded: isExpanded,
            trailing: Icon(
              isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: Colors.blue[700],
            ),
            onExpansionChanged: (expanded) {
              setState(() {
                _dateExpansionState[date] = expanded;
              });
            },
            title: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blue[700]),
                SizedBox(width: 8),
                Text(
                  date,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${records.length}条',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (summary['salesCount'] > 0)
                    _buildSummaryChip('销售', summary['salesAmount'], Colors.green),
                  if (summary['returnsCount'] > 0)
                    _buildSummaryChip('退货', -summary['returnsAmount'], Colors.orange),
                  if (summary['incomeCount'] > 0)
                    _buildSummaryChip('收款', -summary['incomeAmount'], Colors.blue),
                  if (summary['refundCount'] > 0)
                    _buildSummaryChip('退款', summary['refundAmount'], Colors.red),
                  if (summary['discountAmount'] > 0)
                    _buildSummaryChip('优惠', -summary['discountAmount'], Colors.purple),
                  _buildSummaryChip('净额', summary['dailyNet'], 
                    summary['dailyNet'] >= 0 ? Colors.red : Colors.green),
                ],
              ),
            ),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
                    dataTextStyle: TextStyle(
                      color: Colors.black87,
                      fontSize: 12,
                    ),
                    horizontalMargin: 12,
                    columnSpacing: 16,
                    showCheckboxColumn: false,
                    dividerThickness: 1,
                    headingRowHeight: 40,
                    dataRowHeight: 48,
                    columns: [
                      DataColumn(label: Text('类型')),
                      DataColumn(label: Text('产品')),
                      DataColumn(label: Text('数量')),
                      DataColumn(label: Text('金额')),
                      DataColumn(label: Text('优惠')),
                      DataColumn(label: Text('付款方式')),
                      DataColumn(label: Text('经手人')),
                      DataColumn(label: Text('备注')),
                    ],
                    rows: records.map((record) {
                      final type = record['type'];
                      final typeName = record['typeName'];
                      final color = record['color'] as Color;
                      final amount = (record['amount'] as num).toDouble();
                      
                      String amountDisplay;
                      if (type == 'sale') {
                        amountDisplay = '+¥${amount.toStringAsFixed(2)}';
                      } else if (type == 'return') {
                        amountDisplay = '-¥${amount.toStringAsFixed(2)}';
                      } else if (type == 'income_positive') {
                        amountDisplay = '-¥${amount.toStringAsFixed(2)}';
                      } else {
                        amountDisplay = '+¥${amount.abs().toStringAsFixed(2)}';
                      }
                      
                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: color.withOpacity(0.5), width: 1),
                              ),
                              child: Text(
                                typeName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(record['productName'] ?? '-', style: TextStyle(fontSize: 12))),
                          DataCell(Text(record['quantity'] != null 
                              ? '${_formatNumber(record['quantity'])} ${record['unit'] ?? ''}' 
                              : '-', style: TextStyle(fontSize: 12))),
                          DataCell(
                            Text(
                              amountDisplay,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(Text(record['discount'] != null && record['discount'] > 0
                              ? '¥${(record['discount'] as num).toStringAsFixed(2)}'
                              : '-', style: TextStyle(fontSize: 12))),
                          DataCell(Text(record['paymentMethod'] ?? '-', style: TextStyle(fontSize: 12))),
                          DataCell(Text(record['employeeName'] ?? '-', style: TextStyle(fontSize: 12))),
                          DataCell(
                            record['note'].toString().isNotEmpty
                                ? Text(
                                    record['note'],
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[700],
                                      fontSize: 11,
                                    ),
                                  )
                                : Text('-', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 按日期分组的分组表格视图
  Widget _buildGroupedSeparatedTables() {
    final groupedRecords = _groupRecordsByDate();
    final dates = groupedRecords.keys.toList();

    return ListView.builder(
      itemCount: dates.length,
      padding: EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final date = dates[index];
        final records = groupedRecords[date]!;
        final summary = _calculateDailySummary(records);
        final isExpanded = _dateExpansionState[date] ?? false;

        // 分组业务记录和收付款记录
        final businessRecords = records.where((r) => r['type'] == 'sale' || r['type'] == 'return').toList();
        final paymentRecords = records.where((r) => r['type'] == 'income_positive' || r['type'] == 'income_negative').toList();

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 2,
          child: ExpansionTile(
            initiallyExpanded: isExpanded,
            trailing: Icon(
              isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: Colors.blue[700],
            ),
            onExpansionChanged: (expanded) {
              setState(() {
                _dateExpansionState[date] = expanded;
              });
            },
            title: Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blue[700]),
                SizedBox(width: 8),
                Text(
                  date,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.blue[800],
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${records.length}条',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (summary['salesCount'] > 0)
                    _buildSummaryChip('销售', summary['salesAmount'], Colors.green),
                  if (summary['returnsCount'] > 0)
                    _buildSummaryChip('退货', -summary['returnsAmount'], Colors.orange),
                  if (summary['incomeCount'] > 0)
                    _buildSummaryChip('收款', -summary['incomeAmount'], Colors.blue),
                  if (summary['refundCount'] > 0)
                    _buildSummaryChip('退款', summary['refundAmount'], Colors.red),
                  if (summary['discountAmount'] > 0)
                    _buildSummaryChip('优惠', -summary['discountAmount'], Colors.purple),
                  _buildSummaryChip('净额', summary['dailyNet'], 
                    summary['dailyNet'] >= 0 ? Colors.red : Colors.green),
                ],
              ),
            ),
            children: [
              Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 业务记录
                    if (businessRecords.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.shopping_cart, size: 14, color: Colors.green[700]),
                            SizedBox(width: 6),
                            Text(
                              '业务记录',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                          dataTextStyle: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                          ),
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          showCheckboxColumn: false,
                          dividerThickness: 1,
                          headingRowHeight: 36,
                          dataRowHeight: 44,
                          columns: [
                            DataColumn(label: Text('类型')),
                            DataColumn(label: Text('产品')),
                            DataColumn(label: Text('数量')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: businessRecords.map((record) {
                            final type = record['type'];
                            final typeName = record['typeName'];
                            final color = record['color'] as Color;
                            final amount = (record['amount'] as num).toDouble();
                            
                            String amountDisplay = type == 'sale' 
                                ? '+¥${amount.toStringAsFixed(2)}' 
                                : '-¥${amount.toStringAsFixed(2)}';
                            
                            return DataRow(
                              cells: [
                                DataCell(
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: color.withOpacity(0.5), width: 1),
                                    ),
                                    child: Text(
                                      typeName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['productName'] ?? '-', style: TextStyle(fontSize: 12))),
                                DataCell(Text(record['quantity'] != null 
                                    ? '${_formatNumber(record['quantity'])} ${record['unit'] ?? ''}' 
                                    : '-', style: TextStyle(fontSize: 12))),
                                DataCell(
                                  Text(
                                    amountDisplay,
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  record['note'].toString().isNotEmpty
                                      ? Text(
                                          record['note'],
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[700],
                                            fontSize: 11,
                                          ),
                                        )
                                      : Text('-', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    
                    // 收付款记录
                    if (paymentRecords.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet, size: 14, color: Colors.blue[700]),
                            SizedBox(width: 6),
                            Text(
                              '收付款记录',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingTextStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                          dataTextStyle: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                          ),
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          showCheckboxColumn: false,
                          dividerThickness: 1,
                          headingRowHeight: 36,
                          dataRowHeight: 44,
                          columns: [
                            DataColumn(label: Text('类型')),
                            DataColumn(label: Text('金额')),
                            DataColumn(label: Text('优惠')),
                            DataColumn(label: Text('付款方式')),
                            DataColumn(label: Text('经手人')),
                            DataColumn(label: Text('备注')),
                          ],
                          rows: paymentRecords.map((record) {
                            final type = record['type'];
                            final typeName = record['typeName'];
                            final color = record['color'] as Color;
                            final amount = (record['amount'] as num).toDouble();
                            
                            String amountDisplay = type == 'income_positive'
                                ? '-¥${amount.toStringAsFixed(2)}'
                                : '+¥${amount.abs().toStringAsFixed(2)}';
                            
                            return DataRow(
                              cells: [
                                DataCell(
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: color.withOpacity(0.5), width: 1),
                                    ),
                                    child: Text(
                                      typeName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    amountDisplay,
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                DataCell(Text(record['discount'] != null && record['discount'] > 0
                                    ? '¥${(record['discount'] as num).toStringAsFixed(2)}'
                                    : '-', style: TextStyle(fontSize: 12))),
                                DataCell(Text(record['paymentMethod'] ?? '-', style: TextStyle(fontSize: 12))),
                                DataCell(Text(record['employeeName'] ?? '-', style: TextStyle(fontSize: 12))),
                                DataCell(
                                  record['note'].toString().isNotEmpty
                                      ? Text(
                                          record['note'],
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[700],
                                            fontSize: 11,
                                          ),
                                        )
                                      : Text('-', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 构建汇总小标签
  Widget _buildSummaryChip(String label, double amount, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label ${amount >= 0 ? '+' : ''}¥${amount.abs().toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
