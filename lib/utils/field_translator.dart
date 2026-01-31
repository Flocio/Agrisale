/// 字段名翻译工具
/// 将数据库字段名（英文）翻译为中文显示名称
class FieldTranslator {
  /// 字段名映射表（英文 -> 中文）
  static const Map<String, String> _fieldNameMap = {
    // 通用字段
    'id': 'ID',
    'userId': '用户ID',
    'name': '名称',
    'description': '描述',
    'note': '备注',
    'created_at': '创建时间',
    'updated_at': '更新时间',
    'version': '版本号',
    
    // 产品相关
    'productName': '产品名称',
    'stock': '库存',
    'unit': '单位',
    'supplierId': '供应商ID',
    'supplierName': '供应商名称',
    
    // 客户相关
    'customerId': '客户ID',
    'customerName': '客户名称',
    
    // 员工相关
    'employeeId': '经手人ID',
    'employeeName': '经手人名称',
    
    // 采购相关
    'quantity': '数量',
    'purchaseDate': '采购日期',
    'totalPurchasePrice': '总进价',
    
    // 销售相关
    'saleDate': '销售日期',
    'totalSalePrice': '总售价',
    
    // 退货相关
    'returnDate': '退货日期',
    'totalReturnPrice': '总退货金额',
    
    // 进账相关
    'incomeDate': '进账日期',
    'amount': '金额',
    'discount': '优惠金额',
    'paymentMethod': '支付方式',
    
    // 汇款相关
    'remittanceDate': '汇款日期',
    
    // 数据导入/恢复相关
    'operation': '操作类型',
    'source_user': '来源用户',
    'source_time': '来源时间',
    'source_version': '来源版本',
    'is_from_different_user': '是否来自不同用户',
    'suppliers': '供应商数',
    'customers': '客户数',
    'employees': '员工数',
    'products': '产品数',
    'purchases': '采购数',
    'sales': '销售数',
    'returns': '退货数',
    'income': '进账数',
    'incomes': '进账数',
    'remittance': '汇款数',
    'remittances': '汇款数',
    'import_counts': '导入数量统计',
    'before_counts': '操作前数量统计',
    'total_count': '总数量',
    
    // 其他
    'last_login_at': '最后登录时间',
  };
  
  /// 字段显示模式
  static FieldDisplayMode _currentMode = FieldDisplayMode.original;
  
  /// 获取当前显示模式
  static FieldDisplayMode get currentMode => _currentMode;
  
  /// 设置显示模式
  static void setDisplayMode(FieldDisplayMode mode) {
    _currentMode = mode;
  }
  
  /// 切换到下一个显示模式（循环切换）
  static FieldDisplayMode switchToNextMode() {
    switch (_currentMode) {
      case FieldDisplayMode.original:
        _currentMode = FieldDisplayMode.chineseOnly;
        break;
      case FieldDisplayMode.chineseOnly:
        _currentMode = FieldDisplayMode.chineseWithEnglish;
        break;
      case FieldDisplayMode.chineseWithEnglish:
        _currentMode = FieldDisplayMode.original;
        break;
    }
    return _currentMode;
  }
  
  /// 根据当前显示模式翻译字段名
  static String translate(String fieldName) {
    switch (_currentMode) {
      case FieldDisplayMode.original:
        // 原始模式：仅显示英文
        return fieldName;
        
      case FieldDisplayMode.chineseOnly:
        // 中文模式：仅显示中文，如果没有翻译则显示英文
        return _fieldNameMap[fieldName] ?? fieldName;
        
      case FieldDisplayMode.chineseWithEnglish:
        // 中英模式：显示"中文（英文）"
        final chineseName = _fieldNameMap[fieldName];
        if (chineseName != null) {
          return '$chineseName（$fieldName）';
        } else {
          return fieldName;
        }
    }
  }
  
  /// 仅获取中文名称（不受当前模式影响）
  /// 如果没有对应的中文翻译，则返回英文原名
  static String getChineseName(String fieldName) {
    return _fieldNameMap[fieldName] ?? fieldName;
  }
  
  /// 检查是否有中文翻译
  static bool hasTranslation(String fieldName) {
    return _fieldNameMap.containsKey(fieldName);
  }
}

/// 字段显示模式枚举
enum FieldDisplayMode {
  /// 原始模式（仅英文）
  original,
  
  /// 仅中文模式
  chineseOnly,
  
  /// 中英文混合模式
  chineseWithEnglish,
}

/// 字段显示模式扩展方法
extension FieldDisplayModeExtension on FieldDisplayMode {
  /// 获取显示模式的中文名称
  String get displayName {
    switch (this) {
      case FieldDisplayMode.original:
        return '原始';
      case FieldDisplayMode.chineseOnly:
        return '中文';
      case FieldDisplayMode.chineseWithEnglish:
        return '中英';
    }
  }
  
  /// 获取显示模式的图标
  String get icon {
    switch (this) {
      case FieldDisplayMode.original:
        return 'En';
      case FieldDisplayMode.chineseOnly:
        return '中';
      case FieldDisplayMode.chineseWithEnglish:
        return '中En';
    }
  }
  
  /// 获取显示模式的提示文本
  String get tooltip {
    switch (this) {
      case FieldDisplayMode.original:
        return '原始字段名（英文）';
      case FieldDisplayMode.chineseOnly:
        return '中文字段名';
      case FieldDisplayMode.chineseWithEnglish:
        return '中英文字段名';
    }
  }
}
