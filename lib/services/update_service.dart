import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

class UpdateService {
  // GitHub 仓库地址
  static const String GITHUB_REPO = 'Flocio/Agrisale';
  static const String GITHUB_RELEASES_URL = 'https://github.com/$GITHUB_REPO/releases/latest';
  
  // 下载源配置（按优先级排序）
  static List<DownloadSource> get DOWNLOAD_SOURCES => [
    DownloadSource(
      name: 'GitHub 直连',
      apiUrl: 'https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: null,
    ),
    DownloadSource(
      name: 'GitHub 代理 1 (ghproxy.com)',
      apiUrl: 'https://ghproxy.com/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghproxy.com',
    ),
    DownloadSource(
      name: 'GitHub 代理 2 (ghps.cc)',
      apiUrl: 'https://ghps.cc/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghps.cc',
    ),
    DownloadSource(
      name: 'GitHub 代理 3 (mirror.ghproxy.com)',
      apiUrl: 'https://mirror.ghproxy.com/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://mirror.ghproxy.com',
    ),
    DownloadSource(
      name: 'GitHub 代理 4 (ghp.ci)',
      apiUrl: 'https://ghp.ci/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghp.ci',
    ),
    DownloadSource(
      name: 'GitHub 代理 5 (ghproxy.net)',
      apiUrl: 'https://ghproxy.net/https://api.github.com/repos/$GITHUB_REPO/releases/latest',
      proxyBase: 'https://ghproxy.net',
    ),
  ];
  
  // 检查更新（尝试多个源）
  static Future<UpdateInfo?> checkForUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    
    print('当前版本: $currentVersion');
    print('开始检查更新，尝试多个下载源...');
    
    // 按优先级尝试每个下载源
    for (var source in DOWNLOAD_SOURCES) {
      try {
        print('尝试 ${source.name}...');
        final updateInfo = await _checkFromSource(source, currentVersion);
        
        if (updateInfo != null) {
          print('✓ ${source.name} 检查成功，发现新版本: ${updateInfo.version}');
          return updateInfo;
        } else {
          print('✓ ${source.name} 检查成功，当前已是最新版本');
          return null; // 已是最新版本，不需要继续尝试其他源
        }
      } catch (e) {
        print('✗ ${source.name} 检查失败: $e');
        // 打印详细错误信息（仅在调试时）
        if (e.toString().contains('TimeoutException') || 
            e.toString().contains('超时')) {
          print('  原因: 连接超时（可能网络较慢或被墙）');
        } else if (e.toString().contains('HandshakeException')) {
          print('  原因: SSL握手失败（可能代理服务不稳定）');
        } else if (e.toString().contains('FormatException') || 
                   e.toString().contains('非JSON')) {
          print('  原因: 服务器返回了错误页面（可能代理服务异常）');
        } else if (e.toString().contains('SocketException')) {
          print('  原因: 网络连接失败（请检查网络连接）');
        }
        continue; // 尝试下一个源
      }
    }
    
    // 所有源都失败，返回 GitHub Releases 链接
    print('所有下载源都失败，返回 GitHub Releases 链接');
    return UpdateInfo(
      version: '未知',
      currentVersion: currentVersion,
      releaseNotes: '无法连接到更新服务器，请手动访问 GitHub Releases 下载更新。',
      downloadUrl: null,
      githubReleasesUrl: GITHUB_RELEASES_URL,
    );
  }
  
  // 从指定源检查更新
  static Future<UpdateInfo?> _checkFromSource(DownloadSource source, String currentVersion) async {
    try {
      print('正在连接: ${source.apiUrl}');
      
      final response = await http.get(
        Uri.parse(source.apiUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AgriSale-Update-Checker/2.3.0',
        },
      ).timeout(Duration(seconds: 20)); // 增加到20秒超时
      
      print('响应状态码: ${response.statusCode}');
      print('响应内容类型: ${response.headers['content-type']}');
      
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
        
        print('成功获取版本信息: $latestVersion');
        
        if (_compareVersions(latestVersion, currentVersion) > 0) {
          // 有新版本，获取下载链接
          final downloadUrl = _getDownloadUrl(
            data['assets'] as List,
            Platform.operatingSystem,
            source.proxyBase,
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
          print('当前已是最新版本');
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
  
  // 获取下载链接（支持代理）
  static String? _getDownloadUrl(List assets, String platform, String? proxyBase) {
    String fileName;
    
    if (platform == 'android') {
      fileName = 'agrisale-android-';
    } else if (platform == 'ios') {
      fileName = 'agrisale-ios-';
    } else if (platform == 'macos') {
      fileName = 'agrisale-macos-';
    } else if (platform == 'windows') {
      fileName = 'agrisale-windows-';
    } else {
      print('不支持的平台: $platform');
      return null;
    }
    
    for (var asset in assets) {
      final assetName = asset['name'] as String;
      if (assetName.startsWith(fileName)) {
        final originalUrl = asset['browser_download_url'] as String;
        
        // 如果使用代理，添加代理前缀
        if (proxyBase != null) {
          final proxiedUrl = '$proxyBase/$originalUrl';
          print('找到下载链接（代理）: $proxiedUrl');
          return proxiedUrl;
        } else {
          print('找到下载链接（直连）: $originalUrl');
          return originalUrl;
        }
      }
    }
    
    print('未找到平台 $platform 的下载文件');
    return null;
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
  
  // 下载并安装更新（支持多个源重试）
  static Future<void> downloadAndInstall(
    String originalDownloadUrl,
    Function(int received, int total) onProgress,
  ) async {
    // 构建多个下载源（原始链接 + 代理链接）
    final downloadUrls = _buildDownloadUrls(originalDownloadUrl);
    
    Exception? lastError;
    
    // 尝试从每个源下载
    for (var downloadUrl in downloadUrls) {
      try {
        print('尝试从 ${downloadUrl['name']} 下载: ${downloadUrl['url']}');
        
        final dio = Dio();
        final tempDir = await getTemporaryDirectory();
        final fileName = originalDownloadUrl.split('/').last;
        final filePath = '${tempDir.path}/$fileName';
        
        // 下载文件（30秒超时）
        await dio.download(
          downloadUrl['url'] as String,
          filePath,
          options: Options(
            receiveTimeout: Duration(seconds: 30),
          ),
          onReceiveProgress: (received, total) {
            onProgress(received, total);
          },
        ).timeout(Duration(minutes: 10)); // 总超时10分钟
        
        print('下载完成: $filePath');
        
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
        
        // 下载成功，返回
        return;
      } catch (e) {
        print('从 ${downloadUrl['name']} 下载失败: $e');
        lastError = e is Exception ? e : Exception(e.toString());
        continue; // 尝试下一个源
      }
    }
    
    // 所有源都失败
    throw lastError ?? Exception('所有下载源都失败');
  }
  
  // 构建多个下载源 URL
  static List<Map<String, String>> _buildDownloadUrls(String originalUrl) {
    final urls = <Map<String, String>>[];
    
    // 1. 原始链接（直连）
    urls.add({
      'name': 'GitHub 直连',
      'url': originalUrl,
    });
    
    // 2-4. 代理链接
    final proxies = [
      'https://ghproxy.com',
      'https://ghps.cc',
      'https://mirror.ghproxy.com',
    ];
    
    for (var proxy in proxies) {
      urls.add({
        'name': '代理服务',
        'url': '$proxy/$originalUrl',
      });
    }
    
    return urls;
  }
  
  // Android 安装
  static Future<void> _installAndroid(String apkPath) async {
    try {
      await InstallPlugin.installApk(apkPath);
      print('Android 安装已启动');
    } catch (e) {
      print('Android 安装失败: $e');
      rethrow;
    }
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
        print('Windows 安装已启动');
      } else {
        // 如果找不到 exe，打开文件夹让用户手动运行
        await Process.run('explorer', [extractPath]);
      }
    } catch (e) {
      print('Windows 安装失败: $e');
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
        print('macOS 安装已启动');
      } else {
        // 如果找不到 .app，打开文件夹让用户手动安装
        await Process.run('open', [extractPath]);
      }
    } catch (e) {
      print('macOS 安装失败: $e');
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
  final String apiUrl;
  final String? proxyBase; // 代理服务地址（用于下载链接）
  
  const DownloadSource({
    required this.name,
    required this.apiUrl,
    this.proxyBase,
  });
}

