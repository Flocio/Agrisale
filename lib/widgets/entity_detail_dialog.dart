/// 基础信息详情对话框
/// 显示产品/客户/供应商/员工的完整数据库信息和操作历史

import 'package:flutter/material.dart';
import '../models/audit_log.dart';
import '../services/audit_log_service.dart';
import '../utils/field_translator.dart';

/// 操作按钮定义
class EntityActionButton {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const EntityActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });
}

/// 基础信息详情对话框
/// 
/// 用于显示产品/客户/供应商/员工的完整信息和操作历史
class EntityDetailDialog extends StatefulWidget {
  /// 实体类型
  final EntityType entityType;
  
  /// 实体类型显示名称（如 '产品', '客户'）
  final String entityTypeDisplayName;
  
  /// 实体ID
  final int entityId;
  
  /// 用户ID
  final int userId;
  
  /// 实体名称（用于标题显示）
  final String entityName;
  
  /// 记录的完整数据（所有数据库字段）
  final Map<String, dynamic> recordData;
  
  /// 主题色（用于图标和强调色）
  final Color themeColor;
  
  /// 操作按钮列表（显示在顶部）
  final List<EntityActionButton> actionButtons;

  const EntityDetailDialog({
    Key? key,
    required this.entityType,
    required this.entityTypeDisplayName,
    required this.entityId,
    required this.userId,
    required this.entityName,
    required this.recordData,
    this.themeColor = Colors.blue,
    this.actionButtons = const [],
  }) : super(key: key);

  @override
  State<EntityDetailDialog> createState() => _EntityDetailDialogState();
}

class _EntityDetailDialogState extends State<EntityDetailDialog> {
  final AuditLogService _auditLogService = AuditLogService();
  
  List<AuditLog> _logs = [];
  bool _isLoadingLogs = true;
  bool _showAllFields = false; // 是否显示所有字段（包括ID等）

  @override
  void initState() {
    super.initState();
    _loadOperationHistory();
  }

  Future<void> _loadOperationHistory() async {
    try {
      final logs = await _auditLogService.getLogsByEntity(
        userId: widget.userId,
        entityType: widget.entityType,
        entityId: widget.entityId,
      );
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoadingLogs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLogs = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(),
            
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 操作按钮区域（顶部）
                    if (widget.actionButtons.isNotEmpty) ...[
                      _buildActionButtons(),
                      SizedBox(height: 16),
                    ],
                    
                    // 记录详情
                    _buildRecordInfo(),
                    
                    SizedBox(height: 24),
                    
                    // 操作历史
                    _buildOperationHistory(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: widget.themeColor),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.entityTypeDisplayName}详情',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.themeColor,
                  ),
                ),
                Text(
                  widget.entityName,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final buttonCount = widget.actionButtons.length;
        final spacing = 8.0 * (buttonCount - 1); // 按钮之间的间距
        
        // 计算最长标签的字符数
        int maxLabelLength = 0;
        for (final button in widget.actionButtons) {
          if (button.label.length > maxLabelLength) {
            maxLabelLength = button.label.length;
          }
        }
        
        // 估算每个按钮需要的最小宽度
        // 中文字符约14-16px，取15px
        // 带图标的按钮：图标(18) + 间距(8) + 文字 + padding(24)
        final textWidth = maxLabelLength * 15.0;
        final minWidthWithIcon = 18 + 8 + textWidth + 24;
        
        // 计算是否需要隐藏图标
        final totalWidthWithIcons = buttonCount * minWidthWithIcon + spacing;
        final showIcons = availableWidth >= totalWidthWithIcons;
        
        // 构建按钮列表
        final buttons = widget.actionButtons.map((button) {
          if (showIcons) {
            return OutlinedButton.icon(
              onPressed: () => button.onPressed(),
              icon: Icon(button.icon, size: 18, color: button.color),
              label: Text(
                button.label,
                style: TextStyle(color: button.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: button.color.withOpacity(0.5)),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            );
          } else {
            // 空间不足时只显示文字
            return OutlinedButton(
              onPressed: () => button.onPressed(),
              child: Text(
                button.label,
                style: TextStyle(color: button.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: button.color.withOpacity(0.5)),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            );
          }
        }).toList();
        
        // 使用 Row + Flexible 让按钮在空间不足时等比例缩小
        return Row(
          children: buttons.asMap().entries.map((entry) {
            final index = entry.key;
            final button = entry.value;
            return Flexible(
              child: Padding(
                padding: EdgeInsets.only(right: index < buttons.length - 1 ? 8 : 0),
                child: SizedBox(
                  width: double.infinity,
                  child: button,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // 系统字段列表（默认隐藏）
  static const _systemFields = ['id', 'userId', 'version', 'created_at', 'updated_at'];

  Widget _buildRecordInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description, size: 20, color: widget.themeColor),
            SizedBox(width: 8),
            Text(
              '完整数据',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Spacer(),
            // 切换显示模式
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showAllFields = !_showAllFields;
                });
              },
              icon: Icon(
                _showAllFields ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              label: Text(_showAllFields ? '隐藏系统字段' : '显示全部字段'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: _buildFieldRows(),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFieldRows() {
    final fields = widget.recordData.entries.toList();
    final widgets = <Widget>[];
    
    for (int i = 0; i < fields.length; i++) {
      final entry = fields[i];
      final isSystemField = _systemFields.contains(entry.key);
      
      // 如果不显示所有字段，跳过系统字段
      if (!_showAllFields && isSystemField) continue;
      
      widgets.add(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: i < fields.length - 1
                ? Border(bottom: BorderSide(color: Colors.grey[200]!))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  _getFieldLabel(entry.key),
                  style: TextStyle(
                    color: isSystemField ? Colors.grey[500] : Colors.grey[700],
                    fontSize: 13,
                    fontStyle: isSystemField ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatValue(entry.value),
                  style: TextStyle(
                    color: isSystemField ? Colors.grey[600] : Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    if (widgets.isEmpty) {
      widgets.add(
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '无数据',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }
    
    return widgets;
  }

  String _formatValue(dynamic value) {
    if (value == null) return '-';
    if (value is double) {
      // 格式化数字：整数显示为整数，小数保留小数
      if (value == value.floor()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    return value.toString();
  }

  /// 获取字段的显示标签
  String _getFieldLabel(String fieldKey) {
    // 特殊字段使用更明确的标签
    switch (fieldKey) {
      case 'id':
        return '记录ID';
      case 'userId':
        return '创建者ID';
      default:
        return FieldTranslator.getChineseName(fieldKey);
    }
  }

  Widget _buildOperationHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 20, color: widget.themeColor),
            SizedBox(width: 8),
            Text(
              '操作历史',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 8),
            if (!_isLoadingLogs)
              Text(
                '(${_logs.length}条)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        SizedBox(height: 12),
        
        if (_isLoadingLogs)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_logs.isEmpty)
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Text(
                '暂无操作记录',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _logs.asMap().entries.map((entry) {
                final index = entry.key;
                final log = entry.value;
                return _buildLogItem(log, isLast: index == _logs.length - 1);
              }).toList(),
            ),
          ),
        
        // 提示信息
        SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber[200]!),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber[700]),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '数据导入/备份恢复会重新分配基础信息ID，因此仅显示最近一次数据导入/备份恢复后的操作历史。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber[900],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(AuditLog log, {bool isLast = false}) {
    final color = _getOperationColor(log.operationType);
    final icon = _getOperationIcon(log.operationType);
    
    return InkWell(
      onTap: () => _showLogDetail(log),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: !isLast
              ? Border(bottom: BorderSide(color: Colors.grey[200]!))
              : null,
        ),
        child: Row(
          children: [
            // 操作类型图标
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            SizedBox(width: 12),
            
            // 操作信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.operationType.displayName,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        log.username,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    log.operationTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  // 显示简要变更信息
                  if (log.operationType == OperationType.update && log.changes != null && log.changes!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        _getChangeSummary(log.changes!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // 显示级联操作摘要
                  if (log.oldData != null && log.oldData!['cascade_info'] != null)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Text(
                          _getCascadeSummary(log.oldData!['cascade_info'] as Map<String, dynamic>),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  String _getChangeSummary(Map<String, dynamic> changes) {
    final changedFields = changes.keys
        .map((key) => FieldTranslator.getChineseName(key))
        .take(3)
        .join('、');
    if (changes.length > 3) {
      return '修改了: $changedFields 等${changes.length}个字段';
    }
    return '修改了: $changedFields';
  }

  String _getCascadeSummary(Map<String, dynamic> cascadeInfo) {
    final operation = cascadeInfo['operation'] as String?;
    switch (operation) {
      case 'product_name_sync':
        return '级联: 产品名称同步';
      case 'product_supplier_sync':
        return '级联: 供应商同步';
      case 'product_cascade_delete':
        return '级联: 删除关联记录';
      case 'customer_delete_update_relations':
        return '级联: 客户删除关联更新';
      case 'supplier_delete_update_relations':
        return '级联: 供应商删除关联更新';
      case 'employee_delete_update_relations':
        return '级联: 员工删除关联更新';
      default:
        return '级联操作';
    }
  }

  void _showLogDetail(AuditLog log) {
    showDialog(
      context: context,
      builder: (context) => _LogDetailSubDialog(log: log, themeColor: widget.themeColor),
    );
  }

  Color _getOperationColor(OperationType type) {
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

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Icons.add_circle_outline;
      case OperationType.update:
        return Icons.edit_outlined;
      case OperationType.delete:
        return Icons.delete_outline;
      case OperationType.cover:
        return Icons.restore;
    }
  }
}

/// 日志详情子对话框
class _LogDetailSubDialog extends StatelessWidget {
  final AuditLog log;
  final Color themeColor;

  const _LogDetailSubDialog({required this.log, this.themeColor = Colors.blue});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _getOperationIcon(log.operationType),
            color: _getOperationColor(log.operationType),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '${log.operationType.displayName}操作详情',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: 400),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 基本信息
              _buildInfoRow('操作人', log.username),
              _buildInfoRow('操作时间', log.operationTime),
              if (log.note != null && log.note!.isNotEmpty)
                _buildInfoRow('备注', log.note!),
              
              SizedBox(height: 16),
              
              // 变更详情
              if (log.operationType == OperationType.update && log.changes != null && log.changes!.isNotEmpty) ...[
                Text(
                  '变更内容',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                ..._buildChangesRows(log.changes!),
              ] else if (log.operationType == OperationType.create && log.newData != null) ...[
                Text(
                  '创建数据',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '创建了新的${log.entityType.displayName}记录',
                    style: TextStyle(color: Colors.green[700], fontSize: 13),
                  ),
                ),
              ] else if (log.operationType == OperationType.delete && log.oldData != null) ...[
                Text(
                  '删除数据',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '删除了该${log.entityType.displayName}记录',
                    style: TextStyle(color: Colors.red[700], fontSize: 13),
                  ),
                ),
              ] else if (log.operationType == OperationType.cover) ...[
                Text(
                  '覆盖操作',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '通过备份恢复或数据导入操作覆盖',
                    style: TextStyle(color: Colors.purple[700], fontSize: 13),
                  ),
                ),
              ],
              
              // 级联操作信息
              _buildCascadeInfo(log.oldData?['cascade_info'] as Map<String, dynamic>?),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChangesRows(Map<String, dynamic> changes) {
    return changes.entries.map((entry) {
      final fieldName = FieldTranslator.getChineseName(entry.key);
      final change = entry.value;
      
      String oldValue = '-';
      String newValue = '-';
      
      if (change is Map<String, dynamic>) {
        oldValue = _formatValue(change['old']);
        newValue = _formatValue(change['new']);
      }
      
      return Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fieldName,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    oldValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[700],
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                ),
                Expanded(
                  child: Text(
                    newValue,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[700],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  String _formatValue(dynamic value) {
    if (value == null) return '-';
    if (value is double) {
      if (value == value.floor()) {
        return value.toInt().toString();
      }
      return value.toString();
    }
    return value.toString();
  }

  Color _getOperationColor(OperationType type) {
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

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.create:
        return Icons.add_circle_outline;
      case OperationType.update:
        return Icons.edit_outlined;
      case OperationType.delete:
        return Icons.delete_outline;
      case OperationType.cover:
        return Icons.restore;
    }
  }

  /// 构建级联操作信息展示
  Widget _buildCascadeInfo(Map<String, dynamic>? cascadeInfo) {
    if (cascadeInfo == null || cascadeInfo.isEmpty) {
      return SizedBox.shrink();
    }

    final operation = cascadeInfo['operation'] as String?;
    String title = '级联操作';
    Color cardColor = Colors.orange[50]!;
    Color borderColor = Colors.orange[200]!;
    Color iconColor = Colors.orange[700]!;
    IconData icon = Icons.info_outline;

    // 根据操作类型设置标题和样式
    switch (operation) {
      case 'product_name_sync':
        title = '产品名称同步';
        cardColor = Colors.blue[50]!;
        borderColor = Colors.blue[200]!;
        iconColor = Colors.blue[700]!;
        icon = Icons.sync;
        break;
      case 'product_supplier_sync':
        title = '供应商同步';
        cardColor = Colors.blue[50]!;
        borderColor = Colors.blue[200]!;
        iconColor = Colors.blue[700]!;
        icon = Icons.sync;
        break;
      case 'product_supplier_no_sync':
        title = '供应商变更（未同步）';
        cardColor = Colors.grey[100]!;
        borderColor = Colors.grey[300]!;
        iconColor = Colors.grey[600]!;
        icon = Icons.sync_disabled;
        break;
      case 'product_cascade_delete':
        title = '级联删除';
        cardColor = Colors.red[50]!;
        borderColor = Colors.red[200]!;
        iconColor = Colors.red[700]!;
        icon = Icons.delete_sweep;
        break;
      case 'customer_delete_update_relations':
        title = '客户删除关联更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.people_outline;
        break;
      case 'supplier_delete_update_relations':
        title = '供应商删除关联更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.business;
        break;
      case 'employee_delete_update_relations':
        title = '员工删除关联更新';
        cardColor = Colors.orange[50]!;
        borderColor = Colors.orange[200]!;
        iconColor = Colors.orange[700]!;
        icon = Icons.person_outline;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildCascadeContent(cascadeInfo, operation),
          ),
        ),
      ],
    );
  }

  /// 构建级联信息内容
  List<Widget> _buildCascadeContent(Map<String, dynamic> cascadeInfo, String? operation) {
    final widgets = <Widget>[];

    switch (operation) {
      case 'product_name_sync':
        final oldName = cascadeInfo['old_product_name'];
        final newName = cascadeInfo['new_product_name'];
        final affected = cascadeInfo['total_affected'] ?? 0;
        widgets.add(Text('「$oldName」→「$newName」', style: TextStyle(fontSize: 12)));
        widgets.add(Text('影响 $affected 条记录', style: TextStyle(fontSize: 12, color: Colors.grey[600])));
        break;
        
      case 'product_supplier_sync':
        final oldSupplier = cascadeInfo['old_supplier_name'] ?? '无';
        final newSupplier = cascadeInfo['new_supplier_name'] ?? '无';
        final updated = cascadeInfo['updated_purchases'] ?? 0;
        widgets.add(Text('「$oldSupplier」→「$newSupplier」', style: TextStyle(fontSize: 12)));
        widgets.add(Text('更新 $updated 条采购记录', style: TextStyle(fontSize: 12, color: Colors.grey[600])));
        break;
        
      case 'product_cascade_delete':
        final purchases = cascadeInfo['deleted_purchases'] ?? 0;
        final sales = cascadeInfo['deleted_sales'] ?? 0;
        final returns = cascadeInfo['deleted_returns'] ?? 0;
        if (purchases > 0) widgets.add(Text('删除 $purchases 条采购记录', style: TextStyle(fontSize: 12)));
        if (sales > 0) widgets.add(Text('删除 $sales 条销售记录', style: TextStyle(fontSize: 12)));
        if (returns > 0) widgets.add(Text('删除 $returns 条退货记录', style: TextStyle(fontSize: 12)));
        break;
        
      case 'customer_delete_update_relations':
        final sales = cascadeInfo['affected_sales'] ?? 0;
        final returns = cascadeInfo['affected_returns'] ?? 0;
        final income = cascadeInfo['affected_income'] ?? 0;
        if (sales > 0) widgets.add(Text('$sales 条销售记录', style: TextStyle(fontSize: 12)));
        if (returns > 0) widgets.add(Text('$returns 条退货记录', style: TextStyle(fontSize: 12)));
        if (income > 0) widgets.add(Text('$income 条进账记录', style: TextStyle(fontSize: 12)));
        break;
        
      case 'supplier_delete_update_relations':
        final purchases = cascadeInfo['affected_purchases'] ?? 0;
        final remittances = cascadeInfo['affected_remittances'] ?? 0;
        if (purchases > 0) widgets.add(Text('$purchases 条采购记录', style: TextStyle(fontSize: 12)));
        if (remittances > 0) widgets.add(Text('$remittances 条汇款记录', style: TextStyle(fontSize: 12)));
        break;
        
      case 'employee_delete_update_relations':
        final income = cascadeInfo['affected_income'] ?? 0;
        final remittances = cascadeInfo['affected_remittances'] ?? 0;
        if (income > 0) widgets.add(Text('$income 条进账记录', style: TextStyle(fontSize: 12)));
        if (remittances > 0) widgets.add(Text('$remittances 条汇款记录', style: TextStyle(fontSize: 12)));
        break;
        
      default:
        // 显示原始数据
        cascadeInfo.forEach((key, value) {
          if (key != 'operation') {
            widgets.add(Text('$key: $value', style: TextStyle(fontSize: 12)));
          }
        });
    }

    if (widgets.isEmpty) {
      widgets.add(Text('无详细信息', style: TextStyle(fontSize: 12, color: Colors.grey[600])));
    }

    return widgets;
  }
}
