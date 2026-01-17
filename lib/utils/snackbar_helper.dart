// lib/utils/snackbar_helper.dart
// 统一的 SnackBar 显示工具，确保新提示立即顶替旧提示

import 'package:flutter/material.dart';

/// 显示 SnackBar，如果当前已有 SnackBar 正在显示，会先隐藏它再显示新的
/// 这样可以避免多个提示排队显示，新提示会立即顶替旧提示
void showSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 2),
}) {
  // 先隐藏当前正在显示的 SnackBar（如果有）
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  
  // 显示新的 SnackBar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration,
    ),
  );
}

/// BuildContext 扩展方法，提供便捷的 SnackBar 显示方法
extension SnackBarExtension on BuildContext {
  /// 显示普通提示
  void showSnackBar(String message, {Duration? duration}) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? Duration(seconds: 2),
      ),
    );
  }

  /// 显示成功提示（绿色背景）
  void showSuccessSnackBar(String message, {Duration? duration}) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: duration ?? Duration(seconds: 2),
      ),
    );
  }

  /// 显示错误提示（红色背景）
  void showErrorSnackBar(String message, {Duration? duration}) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: duration ?? Duration(seconds: 3),
      ),
    );
  }

  /// 显示警告提示（橙色背景）
  void showWarningSnackBar(String message, {Duration? duration}) {
    ScaffoldMessenger.of(this).hideCurrentSnackBar();
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: duration ?? Duration(seconds: 3),
      ),
    );
  }
}

