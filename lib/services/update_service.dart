import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../utils/app_version.dart';

class UpdateService {
  // GitHub 仓库地址
  static const String GITHUB_REPO = 'Flocio/Agrisale';
  static const String GITHUB_RELEASES_URL = 'https://github.com/$GITHUB_REPO/releases/latest';
  
  // 下载取消令牌
  static CancelToken? _cancelToken;
  
  // 下载源配置（UI显示顺序：官网 → GitHub → 123网盘）
  static List<DownloadSource> get DOWNLOAD_SOURCES => [
    // Agrisale官网（Cloudflare Pages）
    DownloadSource(
      name: 'Agrisale官网',
      apiUrl: 'https://agrisale.drflo.org/api/agrisale/latest.json',
    ),
    // GitHub 直连
    DownloadSource(
      name: 'GitHub',
      apiUrl: 'https://api.github.com/repos/$GITHUB_REPO/releases/latest',
    ),
    // 123网盘（国内直连，速度快）
    DownloadSource(
      name: '123网盘',
      downloadUrlBase: 'https://1819203311.v.123pan.cn/1819203311/releases/agrisale',
      requiresApkRename: true, // .apk 会被改为 .apk.bak，下载后需要重命名
    ),
  ];
  
  // 检查更新（并行检测所有 API 源，获取最高版本）
  static Future<UpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    
    // 筛选出所有 API 源（跳过纯下载源如 123网盘）
    final apiSources = DOWNLOAD_SOURCES.where((s) => !s.isDownloadOnlySource).toList();
    
    // 并行检测所有 API 源
    final results = await Future.wait(
      apiSources.map((source) async {
        try {
          return await checkFromSource(source, currentVersion);
        } catch (e) {
          return null; // 检测失败返回 null
        }
      }),
      eagerError: false, // 不要在第一个错误时就停止
    );
    
    // 从所有结果中找出最高版本
    UpdateInfo? highestUpdateInfo;
    String? highestVersion;
    bool hasSuccessfulCheck = false;
    
    for (var updateInfo in results) {
      // updateInfo 为 null 可能是：1. 已是最新版本 2. 检测失败
      // 但只要有一个源成功响应（即使没有更新），就算成功检查
      hasSuccessfulCheck = true;
      
      if (updateInfo != null) {
        final versionStr = updateInfo.version.replaceAll('v', '');
        if (highestVersion == null || 
            _compareVersions(versionStr, highestVersion) > 0) {
          highestVersion = versionStr;
          highestUpdateInfo = updateInfo;
        }
      }
    }
    
    // 返回最高版本的更新信息
    if (highestUpdateInfo != null) {
      return highestUpdateInfo;
    }
    
    // 有成功的检查但没有更新（已是最新版本）
    if (hasSuccessfulCheck) {
      return null;
    }
    
    // 所有源都失败，返回 GitHub Releases 链接
    return UpdateInfo(
      version: '未知',
      currentVersion: currentVersion,
      releaseNotes: '无法连接到更新服务器，请手动访问 GitHub Releases 下载更新。',
      downloadUrl: null,
      githubReleasesUrl: GITHUB_RELEASES_URL,
    );
  }
  
  // 从指定源检查更新（公开方法，供UI选择源使用）
  static Future<UpdateInfo?> checkFromSource(DownloadSource source, String currentVersion) async {
    // 纯下载源不支持 API 检查
    if (!source.isApiSource) {
      throw Exception('此下载源不支持 API 检查，请使用其他方式获取版本信息');
    }
    
    try {
      final response = await http.get(
        Uri.parse(source.apiUrl!),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Agrisale-Update-Checker/${AppVersion.versionForUserAgent}',
        },
      ).timeout(Duration(seconds: 20)); // 增加到20秒超时
      
      if (response.statusCode == 200) {
        // 检查响应内容是否为JSON
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json') && 
            !contentType.contains('text/json')) {
          // 如果返回的不是JSON（可能是HTML错误页面）
          final preview = response.body.length > 200 
              ? response.body.substring(0, 200) 
              : response.body;
          throw Exception('服务器返回了非JSON内容: $preview...');
        }
        
        final data = jsonDecode(response.body);
        
        // 验证响应数据格式
        if (data is! Map || !data.containsKey('tag_name')) {
          throw Exception('无效的API响应格式');
        }
        
        final latestVersionTag = data['tag_name'] as String;
        final latestVersion = latestVersionTag.replaceAll('v', '');
        
        
        if (_compareVersions(latestVersion, currentVersion) > 0) {
          // 有新版本，获取下载链接
          final downloadUrl = _getDownloadUrl(
            data['assets'] as List,
            Platform.operatingSystem,
          );
          
          return UpdateInfo(
            version: latestVersionTag,
            currentVersion: currentVersion,
            releaseNotes: data['body'] ?? '',
            downloadUrl: downloadUrl,
            githubReleasesUrl: GITHUB_RELEASES_URL,
          );
        } else {
          // 已是最新版本
          return null;
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
    } on TimeoutException {
      throw Exception('连接超时（20秒）');
    } on FormatException catch (e) {
      throw Exception('响应格式错误: ${e.message}');
    } on SocketException catch (e) {
      throw Exception('网络连接失败: ${e.message}');
    } on HandshakeException catch (e) {
      throw Exception('SSL握手失败: ${e.message}');
    } catch (e) {
      throw Exception('未知错误: $e');
    }
  }
  
  // 获取下载链接
  static String? _getDownloadUrl(List assets, String platform) {
    if (platform == 'android') {
      // Android优先查找APK文件（可以直接安装），如果没有再查找AAB文件
      String? apkUrl;
      String? aabUrl;
      
      for (var asset in assets) {
        final assetName = asset['name'] as String;
        // 清理URL中的空格和特殊字符
        final originalUrl = (asset['browser_download_url'] as String).trim().replaceAll(' ', '');
        
        if (assetName.startsWith('Agrisale-android-') && assetName.endsWith('.apk')) {
          apkUrl = originalUrl;
        } else if (assetName.startsWith('Agrisale-android-') && assetName.endsWith('.aab')) {
          aabUrl = originalUrl;
        }
      }
      
      // 优先返回APK，如果没有APK则返回AAB（虽然不能直接安装，但至少可以提示用户）
      return apkUrl ?? aabUrl;
    } else {
      // 其他平台的处理
      String fileName;
      
      if (platform == 'ios') {
        fileName = 'Agrisale-ios-';
      } else if (platform == 'macos') {
        fileName = 'Agrisale-macos-';
      } else if (platform == 'windows') {
        fileName = 'Agrisale-windows-';
      } else {
        return null;
      }
      
      for (var asset in assets) {
        final assetName = asset['name'] as String;
        if (assetName.startsWith(fileName)) {
          // 清理URL中的空格和特殊字符
          return (asset['browser_download_url'] as String).trim().replaceAll(' ', '');
        }
      }
      
      return null;
    }
  }
  
  // 版本号比较 (返回: 1=version1>version2, -1=version1<version2, 0=相等)
  static int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final v2Parts = version2.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    
    // 补齐到3位
    while (v1Parts.length < 3) v1Parts.add(0);
    while (v2Parts.length < 3) v2Parts.add(0);
    
    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }
    return 0;
  }
  
  // 取消当前下载
  static void cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('用户取消下载');
    }
  }
  
  // 下载并安装更新
  static Future<void> downloadAndInstall(
    String downloadUrl,
    Function(int received, int total, String? downloadPath, String? downloadSource) onProgress, {
    bool requiresApkRename = false, // 是否需要处理 .apk.bak -> .apk 重命名
  }) async {
    // 创建新的取消令牌
    _cancelToken = CancelToken();
    
    // Android: 预先检查并请求安装权限
    if (Platform.isAndroid) {
      await _checkAndRequestInstallPermission();
    }
    
    // 预先删除旧的APK文件（避免因文件存在导致下载失败）
    await _deleteOldApkFiles(downloadUrl);
    
    // 清理URL中的空格和特殊字符
    final cleanDownloadUrl = downloadUrl.trim().replaceAll(' ', '');
    
    // 配置Dio
    final dio = Dio();
    
    // 创建自定义HttpClient，禁用SSL证书验证（仅用于下载更新文件）
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return true;
        };
      
      final adapter = IOHttpClientAdapter();
      adapter.createHttpClient = () {
        return httpClient;
      };
      dio.httpClientAdapter = adapter;
    }
    
    // 使用外部存储目录，确保安装程序可以访问
    Directory downloadDir;
    if (Platform.isAndroid) {
      // Android: 尝试使用外部存储的Download目录
      try {
        downloadDir = Directory('/storage/emulated/0/Download');
        if (!await downloadDir.exists()) {
          downloadDir = await getTemporaryDirectory();
        }
      } catch (e) {
        downloadDir = await getTemporaryDirectory();
      }
    } else {
      downloadDir = await getTemporaryDirectory();
    }
    
    // 提取文件名
    final fileName = cleanDownloadUrl.split('/').last;
    var filePath = '${downloadDir.path}/$fileName';
    
    // 检查是否是AAB文件（Android App Bundle不能直接安装）
    if (Platform.isAndroid && fileName.toLowerCase().endsWith('.aab')) {
      throw Exception('下载的文件是AAB格式（Android App Bundle），无法直接安装。\n\n'
          'AAB文件需要通过Google Play商店安装。\n'
          '请从GitHub Releases下载APK文件进行安装。');
    }
    
    // 检查并删除旧文件，如果无法删除则使用新文件名
    final oldFile = File(filePath);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
      } catch (e) {
        // 使用带时间戳的文件名
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        final baseName = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
        filePath = '${downloadDir.path}/${baseName}_$timestamp$ext';
      }
    }
    
    // 下载文件
    await dio.download(
      cleanDownloadUrl,
      filePath,
      cancelToken: _cancelToken,
      options: Options(
        receiveTimeout: Duration(seconds: 30),
        followRedirects: true,
        validateStatus: (status) => status! < 500,
      ),
      onReceiveProgress: (received, total) {
        onProgress(received, total, filePath, cleanDownloadUrl);
      },
    ).timeout(Duration(minutes: 10));
    
    // 处理 .apk.bak -> .apk 重命名（针对某些网盘会自动改后缀的情况）
    if (requiresApkRename && filePath.toLowerCase().endsWith('.apk.bak')) {
      final newFilePath = filePath.substring(0, filePath.length - 4); // 去掉 .bak
      try {
        final file = File(filePath);
        await file.rename(newFilePath);
        filePath = newFilePath;
      } catch (e) {
        throw Exception('重命名文件失败: $e\n\n请手动将下载的文件后缀从 .apk.bak 改为 .apk');
      }
    }
    
    // 验证下载的文件
    try {
      if (Platform.isAndroid) {
        await _validateApkFile(filePath);
      } else if (Platform.isWindows) {
        await _validateZipFile(filePath);
      } else if (Platform.isMacOS) {
        await _validateZipFile(filePath);
      }
    } catch (validationError) {
      // 验证失败，删除无效文件
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (deleteError) {
      }
      rethrow;
    }
    
    // 根据平台安装
    if (Platform.isAndroid) {
      await _installAndroid(filePath);
    } else if (Platform.isIOS) {
      await _installIOS();
    } else if (Platform.isWindows) {
      await _installWindows(filePath);
    } else if (Platform.isMacOS) {
      await _installMacOS(filePath);
    }
  }
  
  // 检查并请求安装未知应用权限（Android专用）
  static Future<void> _checkAndRequestInstallPermission() async {
    try {
      // 检查是否有安装未知应用的权限
      final installStatus = await Permission.requestInstallPackages.status;
      
      if (!installStatus.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        
        if (!result.isGranted) {
        }
      } else {
      }
    } catch (e) {
      // 不抛出异常，继续流程（安装时系统会自动提示）
    }
  }
  
  // 预先删除旧的APK文件
  static Future<void> _deleteOldApkFiles(String downloadUrl) async {
    try {
      // 清理URL并提取文件名
      final cleanUrl = downloadUrl.trim().replaceAll(' ', '');
      final fileName = cleanUrl.split('/').last;
      
      // 检查所有可能的下载目录
      final possibleDirs = <Directory>[];
      
      if (Platform.isAndroid) {
        // 请求存储权限（用于访问外部Download目录）
        try {
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            await Permission.storage.request();
          }
          
          // Android 11+ 需要管理外部存储权限
          if (await Permission.manageExternalStorage.status.isDenied) {
            await Permission.manageExternalStorage.request();
          }
        } catch (e) {
        }
        
        // Android外部下载目录
        possibleDirs.add(Directory('/storage/emulated/0/Download'));
        // 应用临时目录
        try {
          possibleDirs.add(await getTemporaryDirectory());
        } catch (e) {
        }
      } else {
        try {
          possibleDirs.add(await getTemporaryDirectory());
        } catch (e) {
        }
      }
      
      for (var dir in possibleDirs) {
        if (await dir.exists()) {
          final filePath = '${dir.path}/$fileName';
          final file = File(filePath);
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (e) {
            }
          } else {
          }
        }
      }
    } catch (e) {
      // 不抛出异常，继续下载流程
    }
  }
  
  // 验证APK文件
  static Future<void> _validateApkFile(String filePath) async {
    final file = File(filePath);
    
    // 检查文件是否存在
    if (!await file.exists()) {
      throw Exception('下载的文件不存在');
    }
    
    // 检查文件大小（APK文件应该至少1MB）
    final fileSize = await file.length();
    if (fileSize < 1024 * 1024) {
      throw Exception('下载的文件太小（${(fileSize / 1024).toStringAsFixed(1)} KB），可能下载不完整');
    }
    
    // 检查文件扩展名
    if (!filePath.toLowerCase().endsWith('.apk')) {
      throw Exception('下载的文件不是APK格式: $filePath');
    }
    
    // 检查文件头（APK文件是ZIP格式，ZIP文件头是"PK"）
    final bytes = await file.openRead(0, 2).toList();
    if (bytes.isEmpty || bytes[0].isEmpty) {
      throw Exception('无法读取文件内容');
    }
    
    final fileHeader = String.fromCharCodes(bytes[0].take(2));
    if (fileHeader != 'PK') {
      // 检查是否是HTML错误页面
      final firstBytes = await file.openRead(0, 100).toList();
      if (firstBytes.isNotEmpty && firstBytes[0].isNotEmpty) {
        final content = String.fromCharCodes(firstBytes[0].take(50));
        if (content.trim().toLowerCase().startsWith('<!doctype') || 
            content.trim().toLowerCase().startsWith('<html')) {
          throw Exception('下载的文件是HTML错误页面，不是有效的APK文件。请检查网络连接或尝试手动下载。');
        }
      }
      throw Exception('下载的文件格式不正确（不是有效的APK/ZIP文件）。文件头: $fileHeader');
    }
    
  }
  
  // 验证ZIP文件
  static Future<void> _validateZipFile(String filePath) async {
    final file = File(filePath);
    
    // 检查文件是否存在
    if (!await file.exists()) {
      throw Exception('下载的文件不存在');
    }
    
    // 检查文件大小（ZIP文件应该至少1MB）
    final fileSize = await file.length();
    if (fileSize < 1024 * 1024) {
      throw Exception('下载的文件太小（${(fileSize / 1024).toStringAsFixed(1)} KB），可能下载不完整');
    }
    
    // 检查文件扩展名
    if (!filePath.toLowerCase().endsWith('.zip')) {
      throw Exception('下载的文件不是ZIP格式: $filePath');
    }
    
    // 检查文件头（ZIP文件头是"PK"）
    final bytes = await file.openRead(0, 2).toList();
    if (bytes.isEmpty || bytes[0].isEmpty) {
      throw Exception('无法读取文件内容');
    }
    
    final fileHeader = String.fromCharCodes(bytes[0].take(2));
    if (fileHeader != 'PK') {
      // 检查是否是HTML错误页面
      final firstBytes = await file.openRead(0, 100).toList();
      if (firstBytes.isNotEmpty && firstBytes[0].isNotEmpty) {
        final content = String.fromCharCodes(firstBytes[0].take(50));
        if (content.trim().toLowerCase().startsWith('<!doctype') || 
            content.trim().toLowerCase().startsWith('<html')) {
          throw Exception('下载的文件是HTML错误页面，不是有效的ZIP文件。请检查网络连接或尝试手动下载。');
        }
      }
      throw Exception('下载的文件格式不正确（不是有效的ZIP文件）。文件头: $fileHeader');
    }
    
  }
  
  // Android 安装
  static Future<void> _installAndroid(String apkPath) async {
    try {
      // 确保文件存在且可读
      final file = File(apkPath);
      if (!await file.exists()) {
        throw Exception('APK文件不存在: $apkPath');
      }
      
      // 检查文件权限
      final fileSize = await file.length();
      if (fileSize == 0) {
        throw Exception('APK文件为空');
      }
      
      
      // 再次验证文件可读
      try {
        final testBytes = await file.openRead(0, 100).toList();
        if (testBytes.isEmpty || testBytes[0].isEmpty) {
          throw Exception('APK文件无法读取');
        }
      } catch (e) {
        throw Exception('APK文件无法读取: $e');
      }
      
      // 调用安装插件
      // install_plugin会自动处理权限请求和FileProvider
      
      try {
        // 注意：installApk 只是启动安装流程，不等待安装完成
        // 它不会返回安装是否成功，也不会抛出异常（即使安装失败）
        // 用户必须在系统安装界面中完成所有步骤
      await InstallPlugin.installApk(apkPath);
      } catch (installError) {
        rethrow;
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      
      // 提供更详细的错误信息
      if (errorStr.contains('permission denied') || 
          errorStr.contains('权限') ||
          errorStr.contains('install_denied') ||
          errorStr.contains('user restriction')) {
        throw Exception('需要安装权限');
      } else if (errorStr.contains('filenotfoundexception') ||
                 errorStr.contains('文件不存在')) {
        throw Exception('安装失败：找不到APK文件。\n\n错误详情: $e');
      } else if (errorStr.contains('package') && 
                 (errorStr.contains('signature') || 
                  errorStr.contains('签名') ||
                  errorStr.contains('conflicting') ||
                  errorStr.contains('newer') ||
                  errorStr.contains('older'))) {
        // 签名不匹配或版本冲突
        throw Exception('安装失败：签名不匹配。\n\n'
            '这可能是因为：\n'
            '1. 您当前运行的是通过 flutter run 安装的调试版本\n'
            '2. 而下载的APK是发布版本，签名不同\n\n'
            '解决方案：\n'
            '• 如果是开发测试：请使用 flutter build apk 构建发布版本后手动安装\n'
            '• 如果是正式使用：请先卸载当前应用，再安装新版本\n\n'
            '错误详情: $e');
      } else if (errorStr.contains('user_canceled') ||
                 errorStr.contains('用户取消')) {
        throw Exception('安装已取消');
      } else {
        throw Exception('安装失败：$e\n\n'
            '如果这是开发环境（通过 flutter run 运行），可能是签名不匹配问题。\n'
            '请尝试手动从GitHub Releases下载并安装。');
      }
    }
  }
  
  // 直接安装APK（用于权限授予后重试）
  static Future<void> installApkDirect(String apkPath) async {
    return _installAndroid(apkPath);
  }
  
  // iOS 安装（跳转到 App Store 或 TestFlight）
  static Future<void> _installIOS() async {
    // iOS 无法直接安装 IPA，需要跳转到 App Store
    // 这里可以打开 GitHub Releases 页面让用户手动安装
    final url = Uri.parse('https://github.com/$GITHUB_REPO/releases/latest');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
  
  // Windows 安装
  static Future<void> _installWindows(String zipPath) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final extractPath = '${appDir.path}/update';
      final extractDir = Directory(extractPath);
      
      // 清理旧文件
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      
      // 解压 ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (var file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(path.join(extractPath, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
      
      // 查找并运行 agrisale.exe
      final exeFile = File(path.join(extractPath, 'agrisale.exe'));
      if (await exeFile.exists()) {
        await Process.start(exeFile.path, [], mode: ProcessStartMode.detached);
      } else {
        // 如果找不到 exe，打开文件夹让用户手动运行
        await Process.run('explorer', [extractPath]);
      }
    } catch (e) {
      rethrow;
    }
  }
  
  // macOS 安装
  static Future<void> _installMacOS(String zipPath) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final extractPath = '${appDir.path}/update';
      final extractDir = Directory(extractPath);
      
      // 清理旧文件
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);
      
      // 解压 ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (var file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(path.join(extractPath, filename));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        }
      }
      
      // 查找并打开 .app 文件
      final appFiles = extractDir.listSync(recursive: true)
          .where((f) => f.path.endsWith('.app'))
          .toList();
      
      if (appFiles.isNotEmpty) {
        await Process.run('open', [appFiles.first.path]);
      } else {
        // 如果找不到 .app，打开文件夹让用户手动安装
        await Process.run('open', [extractPath]);
      }
    } catch (e) {
      rethrow;
    }
  }
}

class UpdateInfo {
  final String version;
  final String currentVersion;
  final String releaseNotes;
  final String? downloadUrl;
  final String? githubReleasesUrl; // GitHub Releases 链接（用于手动下载）
  
  UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.releaseNotes,
    this.downloadUrl,
    this.githubReleasesUrl,
  });
}

// 下载源配置
class DownloadSource {
  final String name;
  final String? apiUrl; // API URL，如果为 null 则是纯下载源
  final String? downloadUrlBase; // 下载 URL 基础路径（用于纯下载源）
  final bool requiresApkRename; // 是否需要处理 .apk.bak -> .apk 重命名
  
  const DownloadSource({
    required this.name,
    this.apiUrl,
    this.downloadUrlBase,
    this.requiresApkRename = false,
  });
  
  /// 是否是 API 源（需要通过 API 检查更新）
  bool get isApiSource => apiUrl != null;
  
  /// 是否是纯下载源（只提供下载，不提供 API）
  bool get isDownloadOnlySource => apiUrl == null && downloadUrlBase != null;
  
  /// 根据版本号和平台构建下载 URL
  /// 注意：URL 始终使用原始文件名（如 .apk），即使某些网盘会在下载时自动改后缀
  String? buildDownloadUrl(String version, String platform) {
    if (downloadUrlBase == null) return null;
    
    String fileName;
    if (platform == 'android') {
      fileName = 'Agrisale-android-v$version.apk';
    } else if (platform == 'ios') {
      fileName = 'Agrisale-ios-v$version.ipa';
    } else if (platform == 'macos') {
      fileName = 'Agrisale-macos-v$version.dmg';
    } else if (platform == 'windows') {
      fileName = 'Agrisale-windows-v$version-installer.exe';
    } else {
      return null;
    }
    
    return '$downloadUrlBase/v$version/$fileName';
  }
}
