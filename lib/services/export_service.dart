// lib/services/export_service.dart
// 统一的CSV导出服务，支持保存到本地和分享到其他应用

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../utils/snackbar_helper.dart';

enum ExportAction {
  saveToLocal,  // 保存到本地
  share,        // 分享到其他应用
}

class ExportService {
  /// 对外统一调用的方法
  /// 
  /// [context] - BuildContext，用于显示对话框和提示
  /// [csvData] - CSV文件内容
  /// [baseFileName] - 基础文件名（不含扩展名和时间戳），例如："采购报告"
  /// [action] - 导出动作：保存到本地或分享
  static Future<void> exportCSV({
    required BuildContext context,
    required String csvData,
    required String baseFileName,
    required ExportAction action,
  }) async {
    try {
      final fileName = _generateFileName(baseFileName);

      // 1️⃣ 先生成临时 CSV 文件（绝对安全）
      final tempFile = await _createTempCSV(
        csvData: csvData,
        fileName: fileName,
      );

      // 2️⃣ 根据用户选择执行动作
      switch (action) {
        case ExportAction.saveToLocal:
          await _saveToLocal(context, tempFile, fileName);
          break;
        case ExportAction.share:
          await _shareFile(context, tempFile);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('导出失败：$e');
      }
    }
  }

  /// 显示导出选项对话框（保存到本地或分享）
  /// 
  /// [context] - BuildContext
  /// [csvData] - CSV文件内容
  /// [baseFileName] - 基础文件名（不含扩展名和时间戳）
  static Future<void> showExportOptions({
    required BuildContext context,
    required String csvData,
    required String baseFileName,
  }) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('保存到本地'),
            onTap: () {
              Navigator.pop(context);
              exportCSV(
                context: context,
                csvData: csvData,
                baseFileName: baseFileName,
                action: ExportAction.saveToLocal,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享给其他应用'),
            onTap: () {
              Navigator.pop(context);
              exportCSV(
                context: context,
                csvData: csvData,
                baseFileName: baseFileName,
                action: ExportAction.share,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 生成带时间戳的文件名
  /// 格式：基础文件名_YYYYMMDD_HHMMSS.csv
  static String _generateFileName(String base) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${base}_$timestamp.csv';
  }

  /// 创建临时 CSV 文件
  static Future<File> _createTempCSV({
    required String csvData,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvData);
    return file;
  }

  /// 保存到本地（可选目录 + 改名）
  static Future<void> _saveToLocal(
    BuildContext context,
    File tempFile,
    String fileName,
  ) async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存 CSV 文件',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (savePath == null) {
      if (context.mounted) {
        context.showSnackBar('已取消保存');
      }
      return;
    }

    await tempFile.copy(savePath);
    if (context.mounted) {
      context.showSuccessSnackBar('导出成功');
    }
  }

  /// 分享CSV文件给其他 App
  static Future<void> _shareFile(BuildContext context, File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '导出的 CSV 文件',
    );
  }

  /// 导出JSON文件（用于数据备份等）
  /// 
  /// [context] - BuildContext，用于显示对话框和提示
  /// [jsonData] - JSON文件内容
  /// [fileName] - 完整文件名（包含扩展名），例如："admin_Agrisale数据_2025-01-15T14-30-22.json"
  static Future<void> exportJSON({
    required BuildContext context,
    required String jsonData,
    required String fileName,
    required ExportAction action,
  }) async {
    try {
      // 1️⃣ 先生成临时 JSON 文件（绝对安全）
      final tempFile = await _createTempJSON(
        jsonData: jsonData,
        fileName: fileName,
      );

      // 2️⃣ 根据用户选择执行动作
      switch (action) {
        case ExportAction.saveToLocal:
          await _saveJSONToLocal(context, tempFile, fileName);
          break;
        case ExportAction.share:
          await _shareJSONFile(context, tempFile);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('导出失败：$e');
      }
    }
  }

  /// 创建临时 JSON 文件
  static Future<File> _createTempJSON({
    required String jsonData,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonData);
    return file;
  }

  /// 保存JSON到本地（可选目录 + 改名）
  static Future<void> _saveJSONToLocal(
    BuildContext context,
    File tempFile,
    String fileName,
  ) async {
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存数据备份',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (savePath == null) {
      if (context.mounted) {
        context.showSnackBar('已取消保存');
      }
      return;
    }

    await tempFile.copy(savePath);
    if (context.mounted) {
      context.showSuccessSnackBar('数据导出成功');
    }
  }

  /// 分享JSON文件给其他 App
  static Future<void> _shareJSONFile(BuildContext context, File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Agrisale数据备份文件',
    );
  }

  /// 显示JSON导出选项对话框（保存到本地或分享）
  /// 
  /// [context] - BuildContext
  /// [jsonData] - JSON文件内容
  /// [fileName] - 完整文件名（包含扩展名）
  static Future<void> showJSONExportOptions({
    required BuildContext context,
    required String jsonData,
    required String fileName,
  }) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('保存到本地'),
            onTap: () {
              Navigator.pop(context);
              exportJSON(
                context: context,
                jsonData: jsonData,
                fileName: fileName,
                action: ExportAction.saveToLocal,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('分享给其他应用'),
            onTap: () {
              Navigator.pop(context);
              exportJSON(
                context: context,
                jsonData: jsonData,
                fileName: fileName,
                action: ExportAction.share,
              );
            },
          ),
        ],
      ),
    );
  }
}

