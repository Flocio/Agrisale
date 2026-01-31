/// 操作日志数据模型
/// 用于本地版 Agrisale 的操作日志记录

import 'dart:convert';

/// 操作类型枚举
enum OperationType {
  create('CREATE'),
  update('UPDATE'),
  delete('DELETE'),
  cover('COVER');

  final String value;
  const OperationType(this.value);

  static OperationType fromString(String value) {
    return OperationType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => OperationType.create,
    );
  }

  String get displayName {
    switch (this) {
      case OperationType.create:
        return '创建';
      case OperationType.update:
        return '修改';
      case OperationType.delete:
        return '删除';
      case OperationType.cover:
        return '覆盖';
    }
  }
}

/// 实体类型枚举
enum EntityType {
  product('product', '产品'),
  customer('customer', '客户'),
  supplier('supplier', '供应商'),
  employee('employee', '员工'),
  purchase('purchase', '采购'),
  sale('sale', '销售'),
  return_('return', '退货'),
  income('income', '进账'),
  remittance('remittance', '汇款'),
  userData('user_data', '全域');

  final String value;
  final String displayName;
  const EntityType(this.value, this.displayName);

  static EntityType fromString(String value) {
    return EntityType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EntityType.product,
    );
  }
}

/// 操作日志模型
class AuditLog {
  final int id;
  final int userId;
  final String username;
  final OperationType operationType;
  final EntityType entityType;
  final int? entityId;
  final String? entityName;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final Map<String, dynamic>? changes;
  final String operationTime;
  final String? note;

  AuditLog({
    required this.id,
    required this.userId,
    required this.username,
    required this.operationType,
    required this.entityType,
    this.entityId,
    this.entityName,
    this.oldData,
    this.newData,
    this.changes,
    required this.operationTime,
    this.note,
  });

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as int,
      userId: map['userId'] as int,
      username: map['username'] as String,
      operationType: OperationType.fromString(map['operation_type'] as String),
      entityType: EntityType.fromString(map['entity_type'] as String),
      entityId: map['entity_id'] as int?,
      entityName: map['entity_name'] as String?,
      oldData: map['old_data'] != null
          ? jsonDecode(map['old_data'] as String) as Map<String, dynamic>
          : null,
      newData: map['new_data'] != null
          ? jsonDecode(map['new_data'] as String) as Map<String, dynamic>
          : null,
      changes: map['changes'] != null
          ? jsonDecode(map['changes'] as String) as Map<String, dynamic>
          : null,
      operationTime: map['operation_time'] as String,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'operation_type': operationType.value,
      'entity_type': entityType.value,
      if (entityId != null) 'entity_id': entityId,
      if (entityName != null) 'entity_name': entityName,
      if (oldData != null) 'old_data': jsonEncode(oldData),
      if (newData != null) 'new_data': jsonEncode(newData),
      if (changes != null) 'changes': jsonEncode(changes),
      'operation_time': operationTime,
      if (note != null) 'note': note,
    };
  }

  /// 格式化操作时间
  String get formattedTime {
    try {
      String timeStr = operationTime.trim();
      
      // 如果格式是 YYYY-MM-DD HH:MM:SS，直接返回
      if (timeStr.length == 19 && 
          timeStr.contains(' ') && 
          !timeStr.contains('T')) {
        return timeStr;
      }
      
      // 如果是 ISO8601 格式，解析后格式化
      final dateTime = DateTime.parse(timeStr);
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    } catch (e) {
      return operationTime;
    }
  }

  /// 获取变更摘要文本
  String get changesSummary {
    if (changes == null || changes!.isEmpty) {
      return '';
    }

    final summaries = <String>[];
    changes!.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final oldValue = value['old'];
        final newValue = value['new'];
        final delta = value['delta'];

        if (delta != null) {
          // 数字字段，显示差值
          final deltaValue = delta is double ? delta : (delta as num).toDouble();
          if (deltaValue > 0) {
            summaries.add('$key: +$deltaValue');
          } else if (deltaValue < 0) {
            summaries.add('$key: $deltaValue');
          }
        } else {
          // 非数字字段，显示变更
          summaries.add('$key: ${oldValue?.toString() ?? '空'} → ${newValue?.toString() ?? '空'}');
        }
      }
    });

    return summaries.join(', ');
  }
}

/// 分页响应
class PaginatedAuditLogs {
  final List<AuditLog> logs;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;

  PaginatedAuditLogs({
    required this.logs,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  bool get hasNextPage => page < totalPages;
  bool get hasPreviousPage => page > 1;
}
