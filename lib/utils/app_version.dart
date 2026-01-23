// lib/utils/app_version.dart
// 统一管理应用版本号
//
// ⚠️ 重要：更新版本号时，必须同时更新以下两个地方：
// 1. pubspec.yaml 中的 version 字段（格式：x.y.z+buildNumber，如：2.4.1+1）
// 2. 本文件中的 version 常量（格式：x.y.z，如：2.4.1）
//
// 🔑 关键：构建号（buildNumber）必须每次递增！
// - 这是Android的versionCode，用于判断是否可以覆盖安装
// - 新版本的构建号必须大于旧版本，否则Android会拒绝安装
// - 例如：2.4.2+1 → 2.4.3+2（版本号升级，构建号也要递增）
// - 即使只修复bug，也要递增构建号：2.4.2+1 → 2.4.2+2
//
// 说明：
// - pubspec.yaml 是 Flutter 的版本号来源，用于构建和 package_info_plus
// - AppVersion.version 用于编译时需要的版本号（如备份文件、导出文件等）
// - 运行时版本号通过 package_info_plus 从 pubspec.yaml 读取

class AppVersion {
  // 应用版本号（主版本号，格式：x.y.z）
  // ⚠️ 必须与 pubspec.yaml 中的 version 字段保持一致（不包括构建号）
  static const String version = '3.3.2';
  
  // 获取完整版本号（带v前缀，用于显示）
  static String get versionWithPrefix => 'v$version';
  
  // 获取版本号用于User-Agent等场景
  static String get versionForUserAgent => version;
  
  // 私有构造函数，防止实例化
  AppVersion._();
}

