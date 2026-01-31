// lib/screens/audit_log_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/audit_log.dart';
import '../services/audit_log_service.dart';
import '../database_helper.dart';
import '../utils/field_translator.dart';

class AuditLogScreen extends StatefulWidget {
  @override
  _AuditLogScreenState createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final AuditLogService _auditLogService = AuditLogService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  List<AuditLog> _logs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  final int _pageSize = 20;
  int _total = 0;
  
  int? _currentUserId;
  String? _currentUsername;
  
  // 筛选条件
  OperationType? _selectedOperationType;
  EntityType? _selectedEntityType;
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchText = '';
  final TextEditingController _searchController = TextEditingController();
  
  Timer? _searchTimer;
  
  // 字段显示模式
  FieldDisplayMode _displayMode = FieldDisplayMode.original;
  
  @override
  void initState() {
    super.initState();
    // 每次打开日志页面时，重置为默认的英文显示模式
    FieldTranslator.setDisplayMode(FieldDisplayMode.original);
    _searchController.addListener(_onSearchChanged);
    _loadCurrentUser();
  }
  
  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    if (username != null) {
      final userId = await _dbHelper.getCurrentUserId(username);
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUsername = username;
        });
        _fetchLogs();
      }
    }
  }
  
  void _onSearchChanged() {
    _searchTimer?.cancel();
    _searchTimer = Timer(Duration(milliseconds: 500), () {
      if (mounted && _searchController.text != _searchText) {
        setState(() {
          _searchText = _searchController.text;
          _currentPage = 1;
        });
        _fetchLogs();
      }
    });
  }
  
  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    // 退出页面时，重置为默认显示模式
    FieldTranslator.setDisplayMode(FieldDisplayMode.original);
    super.dispose();
  }
  
  Future<void> _fetchLogs({bool isRefresh = false}) async {
    if (_currentUserId == null) return;
    
    if (!isRefresh) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      String? startTime;
      String? endTime;
      
      if (_startDate != null) {
        startTime = '${_startDate!.toIso8601String().split('T')[0]}T00:00:00';
      }
      
      if (_endDate != null) {
        endTime = '${_endDate!.toIso8601String().split('T')[0]}T23:59:59';
      }
      
      final response = await _auditLogService.getAuditLogs(
        userId: _currentUserId!,
        page: _currentPage,
        pageSize: _pageSize,
        operationType: _selectedOperationType?.value,
        entityType: _selectedEntityType?.value,
        startTime: startTime,
        endTime: endTime,
        search: _searchText.isEmpty ? null : _searchText,
      );
      
      setState(() {
        if (_currentPage == 1) {
          _logs = response.logs;
          _total = response.total;
        } else {
          _logs.addAll(response.logs);
        }
        _hasMore = response.hasNextPage;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载日志失败: ${e.toString()}')),
        );
      }
    }
  }
  
  Future<void> _loadMore() async {
    if (_isLoadingMore || _isLoading || !_hasMore) {
      return;
    }
    
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    
    try {
      await _fetchLogs();
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }
  
  void _resetFilters() {
    setState(() {
      _selectedOperationType = null;
      _selectedEntityType = null;
      _startDate = null;
      _endDate = null;
      _searchText = '';
      _searchController.clear();
      _currentPage = 1;
    });
    _fetchLogs();
  }
  
  bool _hasFilters() {
    return _selectedOperationType != null ||
           _selectedEntityType != null ||
           _startDate != null ||
           _endDate != null ||
           _searchText.isNotEmpty;
  }
  
  Future<void> _showFilterDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterBottomSheet(
        selectedOperationType: _selectedOperationType,
        selectedEntityType: _selectedEntityType,
        startDate: _startDate,
        endDate: _endDate,
        onApply: (operationType, entityType, startDate, endDate) {
          setState(() {
            _selectedOperationType = operationType;
            _selectedEntityType = entityType;
            _startDate = startDate;
            _endDate = endDate;
            _currentPage = 1;
          });
          _fetchLogs();
        },
        onReset: () {
          _resetFilters();
          Navigator.pop(context);
        },
      ),
    );
  }
  
  void _showLogDetail(AuditLog log) {
    showDialog(
      context: context,
      builder: (context) => _LogDetailDialog(log: log),
    );
  }
  
  Color _getOperationTypeColor(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Colors.green;
      case OperationType.update:
        return Colors.blue;
      case OperationType.delete:
        return Colors.red;
      case OperationType.cover:
        return Colors.purple;
    }
  }
  
  /// 格式化实体名称中的金额显示
  String _formatEntityName(String? name) {
    if (name == null) return '未知';
    return name.replaceAllMapped(
      RegExp(r'¥(-\d+\.?\d*)'),
      (match) => '-¥${match.group(1)!.substring(1)}',
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '操作日志',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          // 字段显示模式切换按钮
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.translate),
                // 右上角显示当前模式指示器
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: _displayMode == FieldDisplayMode.original 
                          ? Colors.amber[600]
                          : (_displayMode == FieldDisplayMode.chineseOnly
                              ? Colors.green[600]
                              : Colors.blue[600]),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _displayMode.icon,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            tooltip: _displayMode.tooltip,
            onPressed: () {
              setState(() {
                // 切换到下一个模式
                switch (_displayMode) {
                  case FieldDisplayMode.original:
                    _displayMode = FieldDisplayMode.chineseOnly;
                    break;
                  case FieldDisplayMode.chineseOnly:
                    _displayMode = FieldDisplayMode.chineseWithEnglish;
                    break;
                  case FieldDisplayMode.chineseWithEnglish:
                    _displayMode = FieldDisplayMode.original;
                    break;
                }
                // 同步更新 FieldTranslator 的全局模式
                FieldTranslator.setDisplayMode(_displayMode);
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            tooltip: '筛选',
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框
          Padding(
            padding: EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索实体名称、备注...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[600]),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchText = '';
                            _currentPage = 1;
                          });
                          _fetchLogs();
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
              textInputAction: TextInputAction.search,
              onEditingComplete: () {
                FocusScope.of(context).unfocus();
              },
            ),
          ),
          
          // 筛选条件指示器
          if (_hasFilters())
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Icon(Icons.filter_alt, size: 16, color: Colors.grey[700]),
                  SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (_selectedOperationType != null)
                            Chip(
                              label: Text('操作: ${_selectedOperationType!.displayName}'),
                              onDeleted: () {
                                setState(() {
                                  _selectedOperationType = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          if (_selectedEntityType != null) ...[
                            SizedBox(width: 4),
                            Chip(
                              label: Text('类型: ${_selectedEntityType!.displayName}'),
                              onDeleted: () {
                                setState(() {
                                  _selectedEntityType = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          ],
                          if (_startDate != null || _endDate != null) ...[
                            SizedBox(width: 4),
                            Chip(
                              label: Text(
                                _startDate != null && _endDate != null
                                    ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                    : _startDate != null
                                        ? '从 ${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                                        : '至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                              ),
                              onDeleted: () {
                                setState(() {
                                  _startDate = null;
                                  _endDate = null;
                                  _currentPage = 1;
                                });
                                _fetchLogs();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetFilters,
                    child: Text('清除全部'),
                  ),
                ],
              ),
            ),
          
          // 列表标题
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.grey[700], size: 20),
                SizedBox(width: 8),
                Text(
                  '操作记录',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Spacer(),
                Text(
                  '共 $_total 条记录',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
          
          // 日志列表
          Expanded(
            child: _isLoading && _logs.isEmpty
                ? Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                '暂无日志',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                '进行创建、修改、删除操作后会显示在这里',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          setState(() {
                            _currentPage = 1;
                          });
                          await _fetchLogs(isRefresh: true);
                        },
                        child: ListView.builder(
                          itemCount: _logs.length + (_hasMore ? 1 : 0),
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          itemBuilder: (context, index) {
                            if (index == _logs.length) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _loadMore();
                              });
                              return Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            
                            final log = _logs[index];
                            return _buildLogItem(log);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogItem(AuditLog log) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: () => _showLogDetail(log),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    log.formattedTime,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getOperationTypeColor(log.operationType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      log.operationType.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: _getOperationTypeColor(log.operationType),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      log.entityType.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatEntityName(log.entityName),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              if (log.changesSummary.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  log.changesSummary,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (log.note != null && log.note!.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(
                  log.note!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选底部表单
class _FilterBottomSheet extends StatefulWidget {
  final OperationType? selectedOperationType;
  final EntityType? selectedEntityType;
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(OperationType?, EntityType?, DateTime?, DateTime?) onApply;
  final VoidCallback onReset;

  _FilterBottomSheet({
    required this.selectedOperationType,
    required this.selectedEntityType,
    required this.startDate,
    required this.endDate,
    required this.onApply,
    required this.onReset,
  });

  @override
  _FilterBottomSheetState createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late OperationType? _operationType;
  late EntityType? _entityType;
  late DateTime? _startDate;
  late DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _operationType = widget.selectedOperationType;
    _entityType = widget.selectedEntityType;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '筛选条件',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: widget.onReset,
                child: Text('重置'),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 操作类型筛选
          Text('操作类型', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showOperationTypePicker(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  child: Text(_operationType?.displayName ?? '全部'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 实体类型筛选
          Text('实体类型', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showEntityTypePicker(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  child: Text(_entityType?.displayName ?? '全部'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // 时间范围筛选
          Text('时间范围', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.date_range),
                  label: Text(
                    _startDate != null && _endDate != null
                        ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')} 至 ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                        : '选择时间范围',
                  ),
                  onPressed: _selectDateRange,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消'),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(_operationType, _entityType, _startDate, _endDate);
                    Navigator.pop(context);
                  },
                  child: Text('应用'),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }

  Future<void> _showOperationTypePicker() async {
    final options = ['全部', ...OperationType.values.map((e) => e.displayName)];
    int currentIndex = _operationType != null
        ? OperationType.values.indexOf(_operationType!) + 1
        : 0;

    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择操作类型'),
          content: SizedBox(
            height: 200,
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
                  children: options.map((text) => Center(child: Text(text))).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null) {
      setState(() {
        _operationType = selectedIndex == 0
            ? null
            : OperationType.values[selectedIndex - 1];
      });
    }
  }

  Future<void> _showEntityTypePicker() async {
    final options = ['全部', ...EntityType.values.map((e) => e.displayName)];
    final currentIndex = _entityType != null
        ? EntityType.values.indexOf(_entityType!) + 1
        : 0;

    int tempIndex = currentIndex;

    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('选择实体类型'),
          content: SizedBox(
            height: 200,
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
                  children: options.map((text) => Center(child: Text(text))).toList(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, tempIndex),
              child: Text('确定'),
            ),
          ],
        );
      },
    );

    if (selectedIndex != null) {
      setState(() {
        _entityType = selectedIndex == 0
            ? null
            : EntityType.values[selectedIndex - 1];
      });
    }
  }
}

/// 日志详情对话框
class _LogDetailDialog extends StatefulWidget {
  final AuditLog log;

  _LogDetailDialog({required this.log});

  @override
  _LogDetailDialogState createState() => _LogDetailDialogState();
}

class _LogDetailDialogState extends State<_LogDetailDialog> {
  Color _getOperationTypeColor(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Colors.green;
      case OperationType.update:
        return Colors.blue;
      case OperationType.delete:
        return Colors.red;
      case OperationType.cover:
        return Colors.purple;
    }
  }

  String _formatEntityName(String? name) {
    if (name == null) return '未知';
    return name.replaceAllMapped(
      RegExp(r'¥(-\d+\.?\d*)'),
      (match) => '-¥${match.group(1)!.substring(1)}',
    );
  }

  String _getOldDataTitle() {
    if (widget.log.operationType == OperationType.cover) {
      if (widget.log.entityName == '备份恢复') {
        return '恢复前数据';
      } else {
        return '导入前数据';
      }
    }
    return '修改前数据';
  }

  String _getNewDataTitle() {
    if (widget.log.operationType == OperationType.cover) {
      if (widget.log.entityName == '备份恢复') {
        return '恢复后数据';
      } else {
        return '导入后数据';
      }
    }
    return '修改后数据';
  }

  Widget _buildDataTable(Map<String, dynamic>? data, String title) {
    if (data == null || data.isEmpty) {
      return SizedBox.shrink();
    }

    // 提取 cascade_info（如果存在），不在主表格中显示
    final cascadeInfo = data['cascade_info'] as Map<String, dynamic>?;
    final filteredData = Map<String, dynamic>.from(data);
    if (cascadeInfo != null) {
      filteredData.remove('cascade_info');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            columnWidths: {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
            },
            children: filteredData.entries.map((entry) {
              return TableRow(
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      FieldTranslator.translate(entry.key),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      entry.value?.toString() ?? 'null',
                      style: TextStyle(color: Colors.grey[800]),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChangesTable(BuildContext context) {
    if (widget.log.changes == null || widget.log.changes!.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '变更详情',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            columnWidths: {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('字段', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('旧值', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('新值', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('变化', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              ...widget.log.changes!.entries.map((entry) {
                final change = entry.value as Map<String, dynamic>;
                final oldValue = change['old'];
                final newValue = change['new'];
                final delta = change['delta'];
                
                Color? rowColor;
                if (delta != null) {
                  final deltaValue = delta is double ? delta : (delta as num).toDouble();
                  if (deltaValue > 0) {
                    rowColor = Colors.green[50];
                  } else if (deltaValue < 0) {
                    rowColor = Colors.red[50];
                  }
                }
                
                return TableRow(
                  decoration: rowColor != null
                      ? BoxDecoration(color: rowColor)
                      : null,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        FieldTranslator.translate(entry.key),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(oldValue?.toString() ?? 'null'),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(newValue?.toString() ?? 'null'),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: delta != null
                          ? Text(
                              delta > 0 ? '+$delta' : '$delta',
                              style: TextStyle(
                                color: delta > 0 ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Text('-'),
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建级联操作信息展示
  Widget _buildCascadeInfo(Map<String, dynamic>? cascadeInfo) {
    if (cascadeInfo == null || cascadeInfo.isEmpty) {
      return SizedBox.shrink();
    }

    final operation = cascadeInfo['operation'] as String?;
    String title = '级联操作信息';
    Color cardColor = Colors.orange[50]!;
    Color borderColor = Colors.orange[200]!;
    Color iconColor = Colors.orange[700]!;
    IconData icon = Icons.info_outline;

    // 根据操作类型设置标题和样式
    switch (operation) {
      case 'product_name_sync':
        title = '产品名称同步更新';
        cardColor = Colors.blue[50]!;
        borderColor = Colors.blue[200]!;
        iconColor = Colors.blue[700]!;
        icon = Icons.sync;
        break;
      case 'product_supplier_sync':
        title = '供应商同步更新';
        cardColor = Colors.blue[50]!;
        borderColor = Colors.blue[200]!;
        iconColor = Colors.blue[700]!;
        icon = Icons.sync;
        break;
      case 'product_supplier_no_sync':
        title = '供应商变更 - 未同步';
        cardColor = Colors.grey[100]!;
        borderColor = Colors.grey[300]!;
        iconColor = Colors.grey[600]!;
        icon = Icons.sync_disabled;
        break;
      case 'product_cascade_delete':
        title = '产品级联删除';
        cardColor = Colors.red[50]!;
        borderColor = Colors.red[200]!;
        iconColor = Colors.red[700]!;
        icon = Icons.delete_sweep;
        break;
      case 'customer_delete_update_relations':
        title = '客户删除 - 关联记录更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.people_outline;
        break;
      case 'supplier_delete_update_relations':
        title = '供应商删除 - 关联记录更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.business;
        break;
      case 'employee_delete_update_relations':
        title = '员工删除 - 关联记录更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.person_outline;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildCascadeInfoContent(cascadeInfo, operation),
          ),
        ),
        SizedBox(height: 16),
      ],
    );
  }

  /// 构建级联信息内容
  List<Widget> _buildCascadeInfoContent(Map<String, dynamic> cascadeInfo, String? operation) {
    final widgets = <Widget>[];

    switch (operation) {
      case 'product_name_sync':
        // 产品名称同步
        final oldName = cascadeInfo['old_product_name'];
        final newName = cascadeInfo['new_product_name'];
        final affectedPurchases = cascadeInfo['affected_purchases'] ?? 0;
        final affectedSales = cascadeInfo['affected_sales'] ?? 0;
        final affectedReturns = cascadeInfo['affected_returns'] ?? 0;
        final totalAffected = cascadeInfo['total_affected'] ?? 0;

        widgets.add(Text(
          '产品名称从「$oldName」改为「$newName」',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '同步更新了以下关联记录：',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ));
        widgets.add(SizedBox(height: 6));
        if (affectedPurchases > 0) {
          widgets.add(_buildAffectedItem('采购记录', affectedPurchases));
        }
        if (affectedSales > 0) {
          widgets.add(_buildAffectedItem('销售记录', affectedSales));
        }
        if (affectedReturns > 0) {
          widgets.add(_buildAffectedItem('退货记录', affectedReturns));
        }
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '共更新 $totalAffected 条记录',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue[800]),
        ));
        
        // 检查是否同时有供应商同步信息
        final supplierSync = cascadeInfo['supplier_sync'] as Map<String, dynamic>?;
        if (supplierSync != null) {
          widgets.add(SizedBox(height: 10));
          widgets.add(Divider(height: 1, color: Colors.grey[300]));
          widgets.add(SizedBox(height: 10));
          widgets.addAll(_buildSupplierSyncInfo(supplierSync));
        }
        
        // 检查是否有供应商变更但用户选择不同步的信息
        final supplierNoSync = cascadeInfo['supplier_no_sync'] as Map<String, dynamic>?;
        if (supplierNoSync != null) {
          widgets.add(SizedBox(height: 10));
          widgets.add(Divider(height: 1, color: Colors.grey[300]));
          widgets.add(SizedBox(height: 10));
          widgets.addAll(_buildSupplierNoSyncInfo(supplierNoSync));
        }
        break;

      case 'product_supplier_sync':
        // 供应商同步更新
        final updatedPurchases = cascadeInfo['updated_purchases'] ?? 0;
        final oldSupplier = cascadeInfo['old_supplier'];
        final newSupplier = cascadeInfo['new_supplier'];

        widgets.add(Text(
          '供应商从「$oldSupplier」改为「$newSupplier」',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        widgets.add(_buildAffectedItem('同步更新的采购记录', updatedPurchases));
        break;

      case 'product_supplier_no_sync':
        // 供应商变更但用户选择不同步
        final skippedPurchases = cascadeInfo['skipped_purchases'] ?? 0;
        final oldSupplierNoSync = cascadeInfo['old_supplier'];
        final newSupplierNoSync = cascadeInfo['new_supplier'];
        final noteNoSync = cascadeInfo['note'];

        widgets.add(Text(
          '供应商从「$oldSupplierNoSync」改为「$newSupplierNoSync」',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        if (skippedPurchases > 0) {
          widgets.add(Text(
            '有 $skippedPurchases 条采购记录关联到原供应商，用户选择不同步',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ));
        } else {
          widgets.add(Text(
            '无关联的采购记录需要同步',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ));
        }
        if (noteNoSync != null) {
          widgets.add(SizedBox(height: 6));
          widgets.add(Text(
            noteNoSync,
            style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
          ));
        }
        break;

      case 'product_cascade_delete':
        // 产品级联删除
        final deletedPurchases = cascadeInfo['deleted_purchases'] ?? 0;
        final deletedSales = cascadeInfo['deleted_sales'] ?? 0;
        final deletedReturns = cascadeInfo['deleted_returns'] ?? 0;
        final totalDeleted = cascadeInfo['total_deleted'] ?? 0;

        widgets.add(Text(
          '删除产品的同时级联删除了以下记录：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        if (deletedPurchases > 0) {
          widgets.add(_buildAffectedItem('采购记录', deletedPurchases, isDelete: true));
        }
        if (deletedSales > 0) {
          widgets.add(_buildAffectedItem('销售记录', deletedSales, isDelete: true));
        }
        if (deletedReturns > 0) {
          widgets.add(_buildAffectedItem('退货记录', deletedReturns, isDelete: true));
        }
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '共删除 $totalDeleted 条记录',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red[800]),
        ));
        break;

      case 'customer_delete_update_relations':
        // 客户删除
        final affectedSales = cascadeInfo['affected_sales'] ?? 0;
        final affectedReturns = cascadeInfo['affected_returns'] ?? 0;
        final affectedIncome = cascadeInfo['affected_income'] ?? 0;
        final totalAffected = cascadeInfo['total_affected'] ?? 0;
        final note = cascadeInfo['note'];

        widgets.add(Text(
          '删除客户后，以下关联记录的客户ID已设为0（未知客户）：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        if (affectedSales > 0) {
          widgets.add(_buildAffectedItem('销售记录', affectedSales));
        }
        if (affectedReturns > 0) {
          widgets.add(_buildAffectedItem('退货记录', affectedReturns));
        }
        if (affectedIncome > 0) {
          widgets.add(_buildAffectedItem('进账记录', affectedIncome));
        }
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '共更新 $totalAffected 条记录',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange[800]),
        ));
        if (note != null) {
          widgets.add(SizedBox(height: 6));
          widgets.add(Text(
            note,
            style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
          ));
        }
        break;

      case 'supplier_delete_update_relations':
        // 供应商删除
        final affectedPurchases = cascadeInfo['affected_purchases'] ?? 0;
        final affectedProducts = cascadeInfo['affected_products'] ?? 0;
        final affectedRemittance = cascadeInfo['affected_remittance'] ?? 0;
        final totalAffected = cascadeInfo['total_affected'] ?? 0;
        final note = cascadeInfo['note'];

        widgets.add(Text(
          '删除供应商后，以下关联记录已更新：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        if (affectedPurchases > 0) {
          widgets.add(_buildAffectedItem('采购记录（设为未知供应商）', affectedPurchases));
        }
        if (affectedProducts > 0) {
          widgets.add(_buildAffectedItem('产品记录（设为未分配供应商）', affectedProducts));
        }
        if (affectedRemittance > 0) {
          widgets.add(_buildAffectedItem('汇款记录（设为未知供应商）', affectedRemittance));
        }
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '共更新 $totalAffected 条记录',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange[800]),
        ));
        if (note != null) {
          widgets.add(SizedBox(height: 6));
          widgets.add(Text(
            note,
            style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
          ));
        }
        break;

      case 'employee_delete_update_relations':
        // 员工删除
        final affectedIncome = cascadeInfo['affected_income'] ?? 0;
        final affectedRemittance = cascadeInfo['affected_remittance'] ?? 0;
        final totalAffected = cascadeInfo['total_affected'] ?? 0;
        final note = cascadeInfo['note'];

        widgets.add(Text(
          '删除员工后，以下关联记录的员工ID已设为0（未知员工）：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ));
        widgets.add(SizedBox(height: 8));
        if (affectedIncome > 0) {
          widgets.add(_buildAffectedItem('进账记录', affectedIncome));
        }
        if (affectedRemittance > 0) {
          widgets.add(_buildAffectedItem('汇款记录', affectedRemittance));
        }
        widgets.add(SizedBox(height: 8));
        widgets.add(Text(
          '共更新 $totalAffected 条记录',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange[800]),
        ));
        if (note != null) {
          widgets.add(SizedBox(height: 6));
          widgets.add(Text(
            note,
            style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
          ));
        }
        break;

      default:
        // 默认显示所有字段
        cascadeInfo.forEach((key, value) {
          if (key != 'operation') {
            widgets.add(Text(
              '$key: $value',
              style: TextStyle(fontSize: 13),
            ));
          }
        });
    }

    return widgets;
  }

  /// 构建供应商同步信息（用于嵌套显示）
  List<Widget> _buildSupplierSyncInfo(Map<String, dynamic> supplierSync) {
    final widgets = <Widget>[];
    final updatedPurchases = supplierSync['updated_purchases'] ?? 0;
    final oldSupplier = supplierSync['old_supplier'];
    final newSupplier = supplierSync['new_supplier'];

    widgets.add(Text(
      '同时同步了供应商信息：',
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
    ));
    widgets.add(SizedBox(height: 6));
    widgets.add(Text(
      '供应商从「$oldSupplier」改为「$newSupplier」',
      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
    ));
    widgets.add(SizedBox(height: 6));
    widgets.add(_buildAffectedItem('同步更新的采购记录', updatedPurchases));

    return widgets;
  }

  /// 构建供应商不同步信息（用于嵌套显示，用户选择不同步的情况）
  List<Widget> _buildSupplierNoSyncInfo(Map<String, dynamic> supplierNoSync) {
    final widgets = <Widget>[];
    final skippedPurchases = supplierNoSync['skipped_purchases'] ?? 0;
    final oldSupplier = supplierNoSync['old_supplier'];
    final newSupplier = supplierNoSync['new_supplier'];
    final note = supplierNoSync['note'];

    widgets.add(Text(
      '供应商变更但未同步采购记录：',
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[800]),
    ));
    widgets.add(SizedBox(height: 6));
    widgets.add(Text(
      '供应商从「$oldSupplier」改为「$newSupplier」',
      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
    ));
    if (skippedPurchases > 0) {
      widgets.add(SizedBox(height: 6));
      widgets.add(Text(
        '有 $skippedPurchases 条采购记录未同步（用户选择不修改）',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ));
    }
    if (note != null) {
      widgets.add(SizedBox(height: 6));
      widgets.add(Text(
        note,
        style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
      ));
    }

    return widgets;
  }

  /// 构建受影响项目显示
  Widget _buildAffectedItem(String label, int count, {bool isDelete = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isDelete ? Icons.delete_outline : Icons.update,
            size: 16,
            color: isDelete ? Colors.red[700] : Colors.blue[700],
          ),
          SizedBox(width: 6),
          Text(
            '$label：',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          Text(
            '$count 条',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDelete ? Colors.red[700] : Colors.blue[700],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getOperationTypeColor(widget.log.operationType).withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getOperationTypeColor(widget.log.operationType),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.log.operationType.displayName,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        widget.log.entityType.displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 基本信息
                    _buildInfoRow('操作时间', widget.log.formattedTime),
                    _buildInfoRow('操作人', widget.log.username),
                    _buildInfoRow('实体名称', _formatEntityName(widget.log.entityName)),
                    if (widget.log.entityId != null)
                      _buildInfoRow('实体ID', widget.log.entityId.toString()),
                    if (widget.log.note != null && widget.log.note!.isNotEmpty)
                      _buildInfoRow('备注', widget.log.note!),
                    
                    SizedBox(height: 16),
                    Divider(),
                    SizedBox(height: 16),
                    
                    // 级联操作信息（如果存在）
                    _buildCascadeInfo(widget.log.oldData?['cascade_info'] as Map<String, dynamic>?),
                    
                    // 变更详情（仅UPDATE操作）
                    if (widget.log.operationType == OperationType.update)
                      _buildChangesTable(context),
                    
                    // 旧数据（UPDATE、DELETE和COVER操作）
                    if (widget.log.operationType == OperationType.update ||
                        widget.log.operationType == OperationType.delete ||
                        widget.log.operationType == OperationType.cover)
                      _buildDataTable(widget.log.oldData, _getOldDataTitle()),
                    
                    // 新数据（CREATE、UPDATE和COVER操作）
                    if (widget.log.operationType == OperationType.create ||
                        widget.log.operationType == OperationType.update ||
                        widget.log.operationType == OperationType.cover)
                      _buildDataTable(widget.log.newData, _getNewDataTitle()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
