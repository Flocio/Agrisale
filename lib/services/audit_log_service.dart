/// 操作日志服务
/// 用于本地版 Agrisale 的操作日志记录和查询

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import '../models/audit_log.dart';

class AuditLogService {
  static final AuditLogService _instance = AuditLogService._internal();
  factory AuditLogService() => _instance;
  AuditLogService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 记录操作日志
  /// 
  /// [transaction] 可选的事务对象，如果提供则在事务内插入日志
  /// [userId] 用户ID
  /// [username] 用户名
  Future<int> logOperation({
    required OperationType operationType,
    required EntityType entityType,
    required int userId,
    required String username,
    int? entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? changes,
    String? note,
    DatabaseExecutor? transaction,
  }) async {
    try {
      // 计算变更摘要（如果没有提供）
      Map<String, dynamic>? finalChanges = changes;
      if (finalChanges == null && oldData != null && newData != null) {
        finalChanges = _compareData(oldData, newData);
      }

      // 转换数据为JSON字符串
      final oldDataJson = oldData != null ? jsonEncode(oldData) : null;
      final newDataJson = newData != null ? jsonEncode(newData) : null;
      final changesJson = finalChanges != null ? jsonEncode(finalChanges) : null;

      // 获取本地时间
      final now = DateTime.now();
      final localTime = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      // 插入日志（使用事务对象或普通数据库连接）
      final executor = transaction ?? await _dbHelper.database;
      final id = await executor.insert('operation_logs', {
        'userId': userId,
        'username': username,
        'operation_type': operationType.value,
        'entity_type': entityType.value,
        'entity_id': entityId,
        'entity_name': entityName,
        'old_data': oldDataJson,
        'new_data': newDataJson,
        'changes': changesJson,
        'operation_time': localTime,
        'note': note,
      });

      return id;
    } catch (e) {
      print('记录操作日志失败: $e');
      // 日志记录失败不应影响主业务
      return 0;
    }
  }

  /// 记录创建操作
  Future<int> logCreate({
    required EntityType entityType,
    required int userId,
    required String username,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? newData,
    String? note,
    DatabaseExecutor? transaction,
  }) async {
    return await logOperation(
      operationType: OperationType.create,
      entityType: entityType,
      userId: userId,
      username: username,
      entityId: entityId,
      entityName: entityName,
      newData: newData,
      note: note,
      transaction: transaction,
    );
  }

  /// 记录更新操作
  Future<int> logUpdate({
    required EntityType entityType,
    required int userId,
    required String username,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    Map<String, dynamic>? changes,
    String? note,
    DatabaseExecutor? transaction,
  }) async {
    return await logOperation(
      operationType: OperationType.update,
      entityType: entityType,
      userId: userId,
      username: username,
      entityId: entityId,
      entityName: entityName,
      oldData: oldData,
      newData: newData,
      changes: changes,
      note: note,
      transaction: transaction,
    );
  }

  /// 记录删除操作
  Future<int> logDelete({
    required EntityType entityType,
    required int userId,
    required String username,
    required int entityId,
    String? entityName,
    Map<String, dynamic>? oldData,
    String? note,
    DatabaseExecutor? transaction,
  }) async {
    return await logOperation(
      operationType: OperationType.delete,
      entityType: entityType,
      userId: userId,
      username: username,
      entityId: entityId,
      entityName: entityName,
      oldData: oldData,
      note: note,
      transaction: transaction,
    );
  }

  /// 记录覆盖操作（用于数据导入/恢复）
  Future<int> logCover({
    required int userId,
    required String username,
    String? entityName,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
    String? note,
    DatabaseExecutor? transaction,
  }) async {
    return await logOperation(
      operationType: OperationType.cover,
      entityType: EntityType.userData,
      userId: userId,
      username: username,
      entityName: entityName,
      oldData: oldData,
      newData: newData,
      note: note,
      transaction: transaction,
    );
  }

  /// 获取操作日志列表
  Future<PaginatedAuditLogs> getAuditLogs({
    required int userId,
    int page = 1,
    int pageSize = 20,
    String? operationType,
    String? entityType,
    String? startTime,
    String? endTime,
    String? search,
  }) async {
    try {
      final db = await _dbHelper.database;

      // 构建WHERE条件
      final whereConditions = <String>['userId = ?'];
      final whereArgs = <dynamic>[userId];

      if (operationType != null && operationType.isNotEmpty) {
        whereConditions.add('operation_type = ?');
        whereArgs.add(operationType);
      }

      if (entityType != null && entityType.isNotEmpty) {
        whereConditions.add('entity_type = ?');
        whereArgs.add(entityType);
      }

      if (startTime != null && startTime.isNotEmpty) {
        // 转换ISO8601格式为SQLite datetime格式
        final startDateTime = startTime.replaceAll('T', ' ').substring(0, 19);
        whereConditions.add('operation_time >= ?');
        whereArgs.add(startDateTime);
      }

      if (endTime != null && endTime.isNotEmpty) {
        // 转换ISO8601格式为SQLite datetime格式
        final endDateTime = endTime.replaceAll('T', ' ').substring(0, 19);
        whereConditions.add('operation_time <= ?');
        whereArgs.add(endDateTime);
      }

      if (search != null && search.isNotEmpty) {
        whereConditions.add('(entity_name LIKE ? OR note LIKE ?)');
        whereArgs.add('%$search%');
        whereArgs.add('%$search%');
      }

      final whereClause = whereConditions.join(' AND ');

      // 获取总数
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM operation_logs WHERE $whereClause',
        whereArgs,
      );
      final total = countResult.first['count'] as int;

      // 获取分页数据
      final offset = (page - 1) * pageSize;
      final logsResult = await db.query(
        'operation_logs',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'operation_time DESC',
        limit: pageSize,
        offset: offset,
      );

      // 转换为AuditLog对象
      final logs = logsResult.map((row) => AuditLog.fromMap(row)).toList();

      final totalPages = (total / pageSize).ceil();

      return PaginatedAuditLogs(
        logs: logs,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: totalPages,
      );
    } catch (e) {
      print('获取操作日志失败: $e');
      return PaginatedAuditLogs(
        logs: [],
        total: 0,
        page: page,
        pageSize: pageSize,
        totalPages: 0,
      );
    }
  }

  /// 获取操作日志详情
  Future<AuditLog?> getAuditLogDetail(int logId, int userId) async {
    try {
      final db = await _dbHelper.database;

      final result = await db.query(
        'operation_logs',
        where: 'id = ? AND userId = ?',
        whereArgs: [logId, userId],
      );

      if (result.isEmpty) {
        return null;
      }

      return AuditLog.fromMap(result.first);
    } catch (e) {
      print('获取操作日志详情失败: $e');
      return null;
    }
  }

  /// 清理旧日志（保留最近N天的日志）
  Future<int> cleanupOldLogs(int userId, int daysToKeep) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final cutoffDateStr = '${cutoffDate.year.toString().padLeft(4, '0')}-'
          '${cutoffDate.month.toString().padLeft(2, '0')}-'
          '${cutoffDate.day.toString().padLeft(2, '0')} 00:00:00';

      final deletedCount = await db.delete(
        'operation_logs',
        where: 'userId = ? AND operation_time < ?',
        whereArgs: [userId, cutoffDateStr],
      );

      return deletedCount;
    } catch (e) {
      print('清理旧日志失败: $e');
      return 0;
    }
  }

  /// 获取日志统计信息
  Future<Map<String, int>> getLogStatistics(int userId) async {
    try {
      final db = await _dbHelper.database;
      final stats = <String, int>{};

      // 总日志数
      final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM operation_logs WHERE userId = ?',
        [userId],
      );
      stats['total'] = totalResult.first['count'] as int;

      // 按操作类型统计
      for (final opType in OperationType.values) {
        final result = await db.rawQuery(
          'SELECT COUNT(*) as count FROM operation_logs WHERE userId = ? AND operation_type = ?',
          [userId, opType.value],
        );
        stats[opType.value] = result.first['count'] as int;
      }

      return stats;
    } catch (e) {
      print('获取日志统计失败: $e');
      return {'total': 0};
    }
  }

  /// 对比数据，生成变更摘要
  Map<String, dynamic> _compareData(
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) {
    final changes = <String, dynamic>{};
    
    // 找出新增和修改的字段
    newData.forEach((key, newValue) {
      final oldValue = oldData[key];
      if (oldValue != newValue) {
        // 检查是否是数字字段，计算差值
        if (oldValue is num && newValue is num) {
          changes[key] = {
            'old': oldValue,
            'new': newValue,
            'delta': newValue - oldValue,
          };
        } else {
          changes[key] = {
            'old': oldValue,
            'new': newValue,
          };
        }
      }
    });
    
    // 找出删除的字段
    oldData.forEach((key, oldValue) {
      if (!newData.containsKey(key)) {
        changes[key] = {
          'old': oldValue,
          'new': null,
        };
      }
    });
    
    return changes;
  }

  /// 获取特定实体的操作日志历史
  /// 
  /// [userId] 用户ID
  /// [entityType] 实体类型
  /// [entityId] 实体ID
  /// 
  /// 返回该实体的所有操作历史记录，按时间倒序排列
  Future<List<AuditLog>> getLogsByEntity({
    required int userId,
    required EntityType entityType,
    required int entityId,
  }) async {
    try {
      final db = await _dbHelper.database;

      final result = await db.rawQuery(
        '''
        SELECT id, userId, username, operation_type, entity_type, entity_id, entity_name,
               old_data, new_data, changes, operation_time, note
        FROM operation_logs
        WHERE userId = ? AND entity_type = ? AND entity_id = ?
        ORDER BY operation_time DESC
        LIMIT 100
        ''',
        [userId, entityType.value, entityId],
      );

      return result.map((row) => AuditLog.fromMap(row)).toList();
    } catch (e) {
      print('获取实体日志失败: $e');
      return [];
    }
  }
}
