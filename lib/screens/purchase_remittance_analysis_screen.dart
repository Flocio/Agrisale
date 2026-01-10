import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';
import '../services/export_service.dart';

class PurchaseRemittanceAnalysisScreen extends StatefulWidget {
  @override
  _PurchaseRemittanceAnalysisScreenState createState() => _PurchaseRemittanceAnalysisScreenState();
}

class _PurchaseRemittanceAnalysisScreenState extends State<PurchaseRemittanceAnalysisScreen> {
  List<Map<String, dynamic>> _analysisData = [];
  bool _isLoading = false;
  bool _isDescending = true;
  String _sortColumn = 'date';
  
  // 筛选条件
  DateTimeRange? _selectedDateRange;
  String? _selectedSupplier;
  List<Map<String, dynamic>> _suppliers = [];
  
  // 汇总数据
  double _totalPurchases = 0.0;
  double _totalRemittances = 0.0;
  double _totalDifference = 0.0;
  
  // 汇总统计卡片是否展开（默认展开）
  bool _isSummaryExpanded = true;
  
  // 表头固定时：需要两个横向滚动控制器（一个 controller 不能同时绑定两个 ScrollView）
  final ScrollController _headerHorizontalScrollController = ScrollController();
  final ScrollController _dataHorizontalScrollController = ScrollController();
  bool _isSyncingFromHeader = false;
  bool _isSyncingFromData = false;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
    _fetchAnalysisData();
    
    // 同步表头和数据的水平滚动（保持对齐）
    _headerHorizontalScrollController.addListener(_onHeaderHorizontalScroll);
    _dataHorizontalScrollController.addListener(_onDataHorizontalScroll);
  }
  
  void _onHeaderHorizontalScroll() {
    if (_isSyncingFromData) return;
    if (!_dataHorizontalScrollController.hasClients) return;
    _isSyncingFromHeader = true;
    final max = _dataHorizontalScrollController.position.maxScrollExtent;
    final target = _headerHorizontalScrollController.offset.clamp(0.0, max);
    if (_dataHorizontalScrollController.offset != target) {
      _dataHorizontalScrollController.jumpTo(target);
    }
    _isSyncingFromHeader = false;
  }

  void _onDataHorizontalScroll() {
    if (_isSyncingFromHeader) return;
    if (!_headerHorizontalScrollController.hasClients) return;
    _isSyncingFromData = true;
    final max = _headerHorizontalScrollController.position.maxScrollExtent;
    final target = _dataHorizontalScrollController.offset.clamp(0.0, max);
    if (_headerHorizontalScrollController.offset != target) {
      _headerHorizontalScrollController.jumpTo(target);
    }
    _isSyncingFromData = false;
  }
  
  @override
  void dispose() {
    _headerHorizontalScrollController.removeListener(_onHeaderHorizontalScroll);
    _dataHorizontalScrollController.removeListener(_onDataHorizontalScroll);
    _headerHorizontalScrollController.dispose();
    _dataHorizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchSuppliers() async {
    final db = await DatabaseHelper().database;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final userId = await DatabaseHelper().getCurrentUserId(username);
      if (userId != null) {
        final suppliers = await db.query('suppliers', where: 'userId = ?', whereArgs: [userId]);
        setState(() {
          _suppliers = suppliers;
        });
      }
    }
  }

  Future<void> _fetchAnalysisData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper().database;
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('current_username');
      
      if (username != null) {
        final userId = await DatabaseHelper().getCurrentUserId(username);
        if (userId != null) {
          // 构建供应商筛选条件
          String supplierFilter = '';
          List<dynamic> baseParams = [userId];
          
          // 日期筛选参数
          List<dynamic> dateParams = [];
          if (_selectedDateRange != null) {
            dateParams.add(_selectedDateRange!.start.toIso8601String().split('T')[0]);
            dateParams.add(_selectedDateRange!.end.toIso8601String().split('T')[0]);
          }
          
          if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
            supplierFilter = 'AND s.name = ?';
          }

          // 查询采购数据（按日期和供应商分组）
          String purchaseDateFilter = '';
          List<dynamic> purchaseParams = List.from(baseParams);
          if (_selectedDateRange != null) {
            purchaseDateFilter = 'AND DATE(p.purchaseDate) >= ? AND DATE(p.purchaseDate) <= ?';
            purchaseParams.addAll(dateParams);
          }
          if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
            purchaseParams.add(_selectedSupplier!);
          }
          
          final purchasesQuery = '''
            SELECT 
              DATE(p.purchaseDate) as date,
              s.name as supplierName,
              s.id as supplierId,
              SUM(p.totalPurchasePrice) as totalPurchases
            FROM purchases p
            LEFT JOIN suppliers s ON p.supplierId = s.id
            WHERE p.userId = ? $purchaseDateFilter $supplierFilter
            GROUP BY DATE(p.purchaseDate), p.supplierId
          ''';
          
          final purchasesData = await db.rawQuery(purchasesQuery, purchaseParams);

          // 查询汇款数据（按日期和供应商分组）
          String remittanceDateFilter = '';
          List<dynamic> remittanceParams = List.from(baseParams);
          if (_selectedDateRange != null) {
            remittanceDateFilter = 'AND DATE(r.remittanceDate) >= ? AND DATE(r.remittanceDate) <= ?';
            remittanceParams.addAll(dateParams);
          }
          if (_selectedSupplier != null && _selectedSupplier != '所有供应商') {
            remittanceParams.add(_selectedSupplier!);
          }
          
          final remittanceQuery = '''
            SELECT 
              DATE(r.remittanceDate) as date,
              s.name as supplierName,
              s.id as supplierId,
              SUM(r.amount) as totalRemittances
            FROM remittance r
            LEFT JOIN suppliers s ON r.supplierId = s.id
            WHERE r.userId = ? $remittanceDateFilter $supplierFilter
            GROUP BY DATE(r.remittanceDate), r.supplierId
          ''';
          
          final remittanceData = await db.rawQuery(remittanceQuery, remittanceParams);

          // 合并数据
          Map<String, Map<String, dynamic>> combinedData = {};
          
          // 处理采购数据
          for (var purchase in purchasesData) {
            String key = '${purchase['date']}_${purchase['supplierId'] ?? 'null'}';
            combinedData[key] = {
              'date': purchase['date'],
              'supplierName': purchase['supplierName'] ?? '未指定供应商',
              'supplierId': purchase['supplierId'],
              'totalPurchases': (purchase['totalPurchases'] as num?)?.toDouble() ?? 0.0,
              'totalRemittances': 0.0,
            };
          }
          
          // 处理汇款数据
          for (var remittance in remittanceData) {
            String key = '${remittance['date']}_${remittance['supplierId'] ?? 'null'}';
            if (combinedData.containsKey(key)) {
              combinedData[key]!['totalRemittances'] = (remittance['totalRemittances'] as num?)?.toDouble() ?? 0.0;
            } else {
              combinedData[key] = {
                'date': remittance['date'],
                'supplierName': remittance['supplierName'] ?? '未指定供应商',
                'supplierId': remittance['supplierId'],
                'totalPurchases': 0.0,
                'totalRemittances': (remittance['totalRemittances'] as num?)?.toDouble() ?? 0.0,
              };
            }
          }

          // 计算差值
          List<Map<String, dynamic>> analysisData = [];
          for (var data in combinedData.values) {
            double totalPurchases = data['totalPurchases'];
            double totalRemittances = data['totalRemittances'];
            double difference = totalPurchases - totalRemittances;
            
            analysisData.add({
              'date': data['date'],
              'supplierName': data['supplierName'],
              'supplierId': data['supplierId'],
              'totalPurchases': totalPurchases,
              'totalRemittances': totalRemittances,
              'difference': difference,
            });
          }

          // 排序
          _sortData(analysisData);
          
          // 计算汇总
          _calculateSummary(analysisData);

          setState(() {
            _analysisData = analysisData;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('无法获取用户信息')),
            );
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('用户未登录')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('数据加载失败: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      print('采购汇款分析数据加载错误: $e');
    }
  }

  void _sortData(List<Map<String, dynamic>> data) {
    data.sort((a, b) {
      dynamic aValue = a[_sortColumn];
      dynamic bValue = b[_sortColumn];
      
      if (aValue == null && bValue == null) return 0;
      if (aValue == null) return _isDescending ? 1 : -1;
      if (bValue == null) return _isDescending ? -1 : 1;
      
      int comparison;
      if (aValue is String && bValue is String) {
        comparison = aValue.compareTo(bValue);
      } else if (aValue is num && bValue is num) {
        comparison = aValue.compareTo(bValue);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }
      
      return _isDescending ? -comparison : comparison;
    });
  }

  void _calculateSummary(List<Map<String, dynamic>> data) {
    double totalPurchases = 0.0;
    double totalRemittances = 0.0;
    double totalDifference = 0.0;

    for (var item in data) {
      totalPurchases += item['totalPurchases'];
      totalRemittances += item['totalRemittances'];
      totalDifference += item['difference'];
    }

    setState(() {
      _totalPurchases = totalPurchases;
      _totalRemittances = totalRemittances;
      _totalDifference = totalDifference;
    });
  }

  void _onSort(String columnName) {
    setState(() {
      if (_sortColumn == columnName) {
        _isDescending = !_isDescending;
      } else {
        _sortColumn = columnName;
        _isDescending = true;
      }
      _sortData(_analysisData);
    });
  }

  Future<void> _exportToCSV() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username') ?? '未知用户';
    
    List<List<dynamic>> rows = [];
    rows.add(['采购-汇款明细分析 - 用户: $username']);
    rows.add(['导出时间: ${DateTime.now().toString().substring(0, 19)}']);
    
    // 添加筛选条件
    String supplierFilter = _selectedSupplier ?? '所有供应商';
    rows.add(['供应商筛选: $supplierFilter']);
    
    String dateFilter = '所有日期';
    if (_selectedDateRange != null) {
      dateFilter = '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}';
    }
    rows.add(['日期范围: $dateFilter']);
    rows.add([]);
    
    // 表头
    rows.add(['日期', '供应商', '净采购额', '实际汇款', '差值']);

    // 数据行
    for (var item in _analysisData) {
      rows.add([
        item['date'],
        item['supplierName'],
        item['totalPurchases'].toStringAsFixed(2),
        item['totalRemittances'].toStringAsFixed(2),
        item['difference'].toStringAsFixed(2),
      ]);
    }

    // 总计行
    rows.add([]);
    rows.add([
      '总计', '',
      _totalPurchases.toStringAsFixed(2), // 净采购额
      _totalRemittances.toStringAsFixed(2),
      _totalDifference.toStringAsFixed(2),
    ]);

    String csv = const ListToCsvConverter().convert(rows);

    // 使用统一的导出服务
    await ExportService.showExportOptions(
      context: context,
      csvData: csv,
      baseFileName: (_selectedSupplier != null && _selectedSupplier != '所有供应商')
          ? '${_selectedSupplier}_采购与汇款统计'
          : '采购与汇款统计',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('采购与汇款', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            tooltip: '导出',
            onPressed: _exportToCSV,
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选条件
          _buildFilterSection(),
          
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
                    '每日的采购额（含退货）与实际汇款的对应情况，差值为正表示欠款（赊账金额），差值为负表示超付（预付金额）',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 数据表格
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _analysisData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              '暂无分析数据',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildDataTable(),
          ),
          
          FooterWidget(),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          Row(
            children: [
              // 供应商筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('供应商筛选', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    DropdownButtonHideUnderline(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButton<String>(
                          hint: Text('选择供应商'),
                          value: _selectedSupplier,
                          isExpanded: true,
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedSupplier = newValue;
                              _fetchAnalysisData();
                            });
                          },
                          items: [
                            DropdownMenuItem<String>(
                              value: '所有供应商',
                              child: Text('所有供应商'),
                            ),
                            ..._suppliers.map((supplier) {
                              return DropdownMenuItem<String>(
                                value: supplier['name'],
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
              SizedBox(width: 16),
              // 日期范围筛选
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('日期范围', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          lastDate: DateTime.now(),
                        );
                        
                        if (pickedRange != null) {
                          setState(() {
                            _selectedDateRange = pickedRange;
                            _fetchAnalysisData();
                          });
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedDateRange != null
                                    ? '${_selectedDateRange!.start.year}-${_selectedDateRange!.start.month.toString().padLeft(2, '0')}-${_selectedDateRange!.start.day.toString().padLeft(2, '0')} 至 ${_selectedDateRange!.end.year}-${_selectedDateRange!.end.month.toString().padLeft(2, '0')}-${_selectedDateRange!.end.day.toString().padLeft(2, '0')}'
                                    : '选择日期范围',
                                style: TextStyle(
                                  color: _selectedDateRange != null ? Colors.black87 : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_selectedDateRange != null || _selectedSupplier != null) ...[
            SizedBox(height: 12),
            Row(
              children: [
                Text('清除筛选: ', style: TextStyle(color: Colors.grey[600])),
                if (_selectedDateRange != null)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDateRange = null;
                          _fetchAnalysisData();
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('日期范围', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Icon(Icons.close, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_selectedSupplier != null && _selectedSupplier != '所有供应商')
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSupplier = null;
                        _fetchAnalysisData();
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('供应商: $_selectedSupplier', style: TextStyle(fontSize: 12)),
                          SizedBox(width: 4),
                          Icon(Icons.close, size: 14),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      margin: EdgeInsets.all(8),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '汇总统计',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSummaryExpanded = !_isSummaryExpanded;
                    });
                  },
                  child: Icon(
                    _isSummaryExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 20,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
            if (_isSummaryExpanded) ...[
              Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryItem('净采购额', _formatMoney(_totalPurchases), Colors.blue),
                  _buildSummaryItem('实际汇款', _formatMoney(_totalRemittances), Colors.orange),
                  _buildSummaryItem('差值', _formatMoney(_totalDifference), _totalDifference >= 0 ? Colors.red : Colors.green),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 4),
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
  
  // 负数金额显示为 -¥123.45，正数保持 ¥123.45
  String _formatMoney(double value) {
    final absText = value.abs().toStringAsFixed(2);
    return value < 0 ? '-¥$absText' : '¥$absText';
  }

  Widget _buildDataTable() {
    // 原始列定义（保持原样）
    final columns = <DataColumn>[
      DataColumn(
        label: Text('日期'),
        onSort: (columnIndex, ascending) => _onSort('date'),
      ),
      DataColumn(
        label: Text('供应商'),
        onSort: (columnIndex, ascending) => _onSort('supplierName'),
      ),
      DataColumn(
        label: Text('净采购额'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalPurchases'),
      ),
      DataColumn(
        label: Text('实际汇款'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('totalRemittances'),
      ),
      DataColumn(
        label: Text('差值'),
        numeric: true,
        onSort: (columnIndex, ascending) => _onSort('difference'),
      ),
    ];
    
    // 构造用于“撑开列宽”的隐形行（保证表头与数据列宽一致）
    String maxDate = '';
    String maxSupplier = '';
    String maxTotalPurchases = '¥0.00';
    String maxTotalRemittances = '¥0.00';
    String maxDifference = '¥0.00';
    
    for (final item in _analysisData) {
      final String date = (item['date'] ?? '').toString();
      final String supplier = (item['supplierName'] ?? '').toString();
      final String totalPurchases = _formatMoney((item['totalPurchases'] as num).toDouble());
      final String totalRemittances = _formatMoney((item['totalRemittances'] as num).toDouble());
      final String difference = _formatMoney((item['difference'] as num).toDouble());
      
      if (date.length > maxDate.length) maxDate = date;
      if (supplier.length > maxSupplier.length) maxSupplier = supplier;
      if (totalPurchases.length > maxTotalPurchases.length) maxTotalPurchases = totalPurchases;
      if (totalRemittances.length > maxTotalRemittances.length) maxTotalRemittances = totalRemittances;
      if (difference.length > maxDifference.length) maxDifference = difference;
    }
    
    // 也考虑“总计行”的数值宽度（避免总计更宽导致对齐偏差）
    final String totalPurchasesText = _formatMoney(_totalPurchases);
    final String totalRemittancesText = _formatMoney(_totalRemittances);
    final String totalDifferenceText = _formatMoney(_totalDifference);
    
    if (totalPurchasesText.length > maxTotalPurchases.length) maxTotalPurchases = totalPurchasesText;
    if (totalRemittancesText.length > maxTotalRemittances.length) maxTotalRemittances = totalRemittancesText;
    if (totalDifferenceText.length > maxDifference.length) maxDifference = totalDifferenceText;
    
    final List<DataRow> headerSizerRows = [
      DataRow(
        cells: [
          DataCell(Opacity(opacity: 0, child: Text(maxDate))),
          DataCell(Opacity(opacity: 0, child: Text(maxSupplier))),
          DataCell(Opacity(opacity: 0, child: Text(maxTotalPurchases))),
          DataCell(Opacity(opacity: 0, child: Text(maxTotalRemittances))),
          DataCell(Opacity(opacity: 0, child: Text(maxDifference))),
        ],
      ),
    ];
    
    final bodyRows = <DataRow>[
      ..._analysisData.map((item) {
        final double totalPurchases = (item['totalPurchases'] as num).toDouble();
        final double totalRemittances = (item['totalRemittances'] as num).toDouble();
        final double difference = (item['difference'] as num).toDouble();
        
        return DataRow(
          cells: [
            DataCell(Text(item['date'] ?? '')),
            DataCell(Text(item['supplierName'] ?? '')),
            DataCell(Text(_formatMoney(totalPurchases),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney(totalRemittances),
              style: TextStyle(color: Colors.orange))),
            DataCell(Text(_formatMoney(difference),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: difference >= 0 ? Colors.red : Colors.green
              ))),
          ],
        );
      }).toList(),
      
      // 总计行
      if (_analysisData.isNotEmpty)
        DataRow(
          color: MaterialStateProperty.all(Colors.grey[100]),
          cells: [
            DataCell(Text('总计', style: TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text('')),
            DataCell(Text(_formatMoney(_totalPurchases),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
            DataCell(Text(_formatMoney(_totalRemittances),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
            DataCell(Text(_formatMoney(_totalDifference),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _totalDifference >= 0 ? Colors.red : Colors.green
              ))),
          ],
        ),
    ];
    
    return Column(
      children: [
        // 固定表头（仅垂直方向固定；水平方向与数据同步）
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _headerHorizontalScrollController,
          child: DataTable(
            sortColumnIndex: _getSortColumnIndex(),
            sortAscending: !_isDescending,
            horizontalMargin: 12,
            columnSpacing: 16,
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
              fontSize: 12,
            ),
            dataTextStyle: TextStyle(fontSize: 11),
            // 用 0 高度的数据行撑列宽，不改变视觉（只显示表头）
            dataRowMinHeight: 0,
            dataRowMaxHeight: 0,
            columns: columns,
            rows: headerSizerRows,
          ),
        ),
        
        // 数据区域（可上下滚动；左右滚动与表头同步保持对齐）
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _dataHorizontalScrollController,
              child: DataTable(
                horizontalMargin: 12,
                columnSpacing: 16,
                headingTextStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                  fontSize: 12,
                ),
                dataTextStyle: TextStyle(fontSize: 11),
                // 隐藏表头（仅显示数据），但列定义保持一致以确保对齐
                headingRowHeight: 0,
                columns: columns,
                rows: bodyRows,
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'date': return 0;
      case 'supplierName': return 1;
      case 'totalPurchases': return 2;
      case 'totalRemittances': return 3;
      case 'difference': return 4;
      default: return 0;
    }
  }
} 