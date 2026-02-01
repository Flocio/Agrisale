// lib/utils/visual_length_formatter.dart
// 基于视觉宽度的字符限制：中文算2，英文/数字/符号算1

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 默认最大视觉长度
const int kDefaultMaxVisualLength = 30;

/// 计算字符串的视觉宽度
/// 中文字符（包括中文标点）算2，其他字符算1
int getVisualLength(String text) {
  int length = 0;
  for (var rune in text.runes) {
    // CJK统一汉字: U+4E00 - U+9FFF
    // CJK扩展A: U+3400 - U+4DBF
    // CJK扩展B-F: U+20000 - U+2CEAF
    // 中文标点: U+3000 - U+303F, U+FF00 - U+FFEF
    // 日文平假名/片假名: U+3040 - U+30FF
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||   // CJK统一汉字
        (rune >= 0x3400 && rune <= 0x4DBF) ||   // CJK扩展A
        (rune >= 0x3000 && rune <= 0x303F) ||   // 中文标点
        (rune >= 0xFF00 && rune <= 0xFFEF) ||   // 全角字符
        (rune >= 0x3040 && rune <= 0x30FF)) {   // 日文假名
      length += 2;
    } else {
      length += 1;
    }
  }
  return length;
}

/// 视觉宽度限制的输入格式化器
/// maxVisualLength: 最大视觉宽度（默认30，相当于15个中文或30个英文）
class VisualLengthFormatter extends TextInputFormatter {
  final int maxVisualLength;
  
  VisualLengthFormatter({this.maxVisualLength = 30});
  
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newLength = getVisualLength(newValue.text);
    
    if (newLength <= maxVisualLength) {
      return newValue;
    }
    
    // 超出限制，截断到合适长度
    String truncated = '';
    int currentLength = 0;
    
    for (var rune in newValue.text.runes) {
      int charWidth;
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x3000 && rune <= 0x303F) ||
          (rune >= 0xFF00 && rune <= 0xFFEF) ||
          (rune >= 0x3040 && rune <= 0x30FF)) {
        charWidth = 2;
      } else {
        charWidth = 1;
      }
      
      if (currentLength + charWidth <= maxVisualLength) {
        truncated += String.fromCharCode(rune);
        currentLength += charWidth;
      } else {
        break;
      }
    }
    
    return TextEditingValue(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}

/// 构建视觉长度计数器（用于输入框外部）
/// 用于 TextFormField 的 buildCounter 参数
Widget? buildVisualLengthCounter({
  required BuildContext context,
  required int currentLength,
  required bool isFocused,
  int? maxLength,
  int maxVisualLength = kDefaultMaxVisualLength,
  required String currentText,
}) {
  final visualLength = getVisualLength(currentText);
  final isAtLimit = visualLength >= maxVisualLength;
  
  return Text(
    '$visualLength/$maxVisualLength',
    style: TextStyle(
      fontSize: 10,
      color: isAtLimit ? Colors.red[400] : Colors.grey[500],
    ),
  );
}

/// 构建视觉长度计数器（用于输入框内部）
/// 用于 InputDecoration 的 suffix 参数
Widget buildVisualLengthSuffix({
  required String currentText,
  int maxVisualLength = kDefaultMaxVisualLength,
}) {
  final visualLength = getVisualLength(currentText);
  final isAtLimit = visualLength >= maxVisualLength;
  
  return Padding(
    padding: EdgeInsets.only(right: 4),
    child: Text(
      '$visualLength/$maxVisualLength',
      style: TextStyle(
        fontSize: 10,
        color: isAtLimit ? Colors.red[400] : Colors.grey[400],
      ),
    ),
  );
}

/// 带视觉长度计数器的输入框包装器
/// 计数器显示在输入框内部右下角
class TextFormFieldWithCounter extends StatelessWidget {
  final TextEditingController controller;
  final InputDecoration? decoration;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int maxVisualLength;

  const TextFormFieldWithCounter({
    Key? key,
    required this.controller,
    this.decoration,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.maxVisualLength = kDefaultMaxVisualLength,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final visualLength = getVisualLength(controller.text);
    final isAtLimit = visualLength >= maxVisualLength;

    return Stack(
      children: [
        TextFormField(
          controller: controller,
          decoration: decoration,
          inputFormatters: inputFormatters ?? [VisualLengthFormatter(maxVisualLength: maxVisualLength)],
          validator: validator,
          onChanged: onChanged,
        ),
        Positioned(
          right: 12,
          bottom: 8,
          child: Text(
            '$visualLength/$maxVisualLength',
            style: TextStyle(
              fontSize: 10,
              color: isAtLimit ? Colors.red[400] : Colors.grey[400],
            ),
          ),
        ),
      ],
    );
  }
}
