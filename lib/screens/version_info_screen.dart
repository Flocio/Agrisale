// lib/screens/version_info_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/update_service.dart';
import 'update_dialog.dart';
import 'help_screen.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/footer_widget.dart';

class VersionInfoScreen extends StatefulWidget {
  @override
  _VersionInfoScreenState createState() => _VersionInfoScreenState();
}

class _VersionInfoScreenState extends State<VersionInfoScreen> {
  PackageInfo? _packageInfo;
  bool _isChecking = false;
  UpdateInfo? _updateInfo;
  String? _checkError;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = packageInfo;
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _isChecking = true;
      _checkError = null;
      _updateInfo = null;
    });

    try {
      final updateInfo = await UpdateService.checkForUpdate();

      setState(() {
        _isChecking = false;
      });
      
      if (updateInfo != null) {
        // 发现新版本，直接显示更新弹窗
        _showUpdateInfoDialog(updateInfo);
      } else {
        // 已是最新版本
        context.showSuccessSnackBar('当前已是最新版本');
      }
    } catch (e) {
      setState(() {
        _isChecking = false;
        _checkError = '检查更新失败: $e';
      });
    }
  }

  // 显示更新信息弹窗（新版本）
  void _showUpdateInfoDialog(UpdateInfo updateInfo) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update, color: Colors.blue),
              SizedBox(width: 8),
              Text('发现新版本 ${updateInfo.version}'),
            ],
          ),
        ),
        content: Padding(
          padding: EdgeInsets.only(top: 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (updateInfo.releaseNotes.isNotEmpty) ...[
                  Container(
                    constraints: BoxConstraints(maxHeight: 300),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: updateInfo.releaseNotes,
                        styleSheet: MarkdownStyleSheet(
                          h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          h2: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          h3: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          p: TextStyle(fontSize: 12, height: 1.6),
                          listBullet: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '稍后',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 64),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startDownloadAndInstall(updateInfo);
            },
            child: Text(
              '立即更新',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 显示下载源选择弹窗或平台不支持提示
  void _startDownloadAndInstall(UpdateInfo updateInfo) async {
    // 检查平台，只有Android支持自动更新
    if (!Platform.isAndroid) {
      // 非Android平台，显示不支持自动更新的提示
      _showPlatformNotSupportedDialog();
      return;
    }
    
    // Android平台，继续正常的更新流程
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadSourceSelectionDialog(
        updateInfo: updateInfo,
      ),
    );
  }
  
  // 显示平台不支持自动更新的提示窗口
  void _showPlatformNotSupportedDialog() {
    String platformName = '';
    if (Platform.isIOS) {
      platformName = 'iOS';
    } else if (Platform.isMacOS) {
      platformName = 'macOS';
    } else if (Platform.isWindows) {
      platformName = 'Windows';
    } else if (Platform.isLinux) {
      platformName = 'Linux';
    } else {
      platformName = '当前';
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('暂不支持自动更新'),
            ],
          ),
        ),
        content: Padding(
          padding: EdgeInsets.only(top: 28),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                fontSize: 15,
                color: Colors.black,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$platformName系统目前暂不支持自动安装更新，请前往',
                ),
                TextSpan(
                  text: 'Agrisale官网',
                  style: TextStyle(
                    color: Colors.green,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      final url = Uri.parse('https://agrisale.drflo.org/agrisale/');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                ),
                TextSpan(
                  text: '或',
                ),
                TextSpan(
                  text: 'Github',
                  style: TextStyle(
                    color: Colors.green,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () async {
                      final url = Uri.parse('https://github.com/${UpdateService.GITHUB_REPO}/releases/latest');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                ),
                TextSpan(
                  text: '手动下载最新安装包完成更新。',
                ),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '知道了',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('关于', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
      ),
      body: _packageInfo == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 使用帮助卡片
                        _buildHelpCard(),
                        SizedBox(height: 16),
                        
                        // 版本信息卡片
                        _buildVersionInfoCard(),
                        
                        SizedBox(height: 16),
                        
                        // 联系支持卡片
                        _buildContactSupportCard(),
                      ],
                    ),
                  ),
                ),
                FooterWidget(),
              ],
            ),
    );
  }

  // 使用帮助卡片
  Widget _buildHelpCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '使用帮助',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.help_outline, color: Colors.green),
              title: Text('帮助文档'),
              subtitle: Text('查看完整的使用说明和常见问题'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HelpScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 版本信息卡片
  Widget _buildVersionInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '版本信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.info_outline, color: Colors.green),
              title: Text('当前版本'),
              subtitle: Text('v${_packageInfo!.version} (${_packageInfo!.buildNumber})'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                _showVersionDetails();
              },
            ),
            Divider(),
            ListTile(
              leading: _isChecking
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    )
                  : Icon(Icons.system_update, color: Colors.green),
              title: Text(_isChecking ? '正在检查更新...' : '检查更新'),
              subtitle: _checkError != null 
                  ? Text(_checkError!, style: TextStyle(color: Colors.red))
                  : Text('检查是否有新版本可用'),
              trailing: _isChecking ? null : Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _isChecking ? null : _checkForUpdate,
            ),
          ],
        ),
      ),
    );
  }


  // 联系支持卡片
  Widget _buildContactSupportCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '联系支持',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.email_outlined, color: Colors.green),
              title: Text('邮件支持'),
              subtitle: Text('agrisalews@163.com'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final emailUrl = Uri.parse('mailto:agrisalews@163.com?subject=Agrisale支持请求');
                try {
                  if (await canLaunchUrl(emailUrl)) {
                    await launchUrl(emailUrl);
                  } else {
                    if (mounted) {
                      context.showWarningSnackBar('无法打开邮件应用，请手动发送邮件至: agrisalews@163.com');
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    context.showErrorSnackBar('打开邮件应用失败: $e');
                  }
                }
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.public, color: Colors.green),
              title: Text('项目主页'),
              subtitle: Text('访问 GitHub 查看更多信息'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final url = 'https://github.com/Flocio/Agrisale';
                try {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      context.showWarningSnackBar('无法打开链接，请手动访问: $url');
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    context.showErrorSnackBar('打开链接失败: $e');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // 显示版本详情
  void _showVersionDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Padding(
          padding: EdgeInsets.only(top: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 应用名称
              Text(
                _packageInfo!.appName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 38),
              // 版本号和构建号并排
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCompactInfoRow('版本号', _packageInfo!.version),
                  SizedBox(width: 40),
                  _buildCompactInfoRow('构建号', _packageInfo!.buildNumber),
                ],
              ),
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 8),
              // 版权信息
              Text(
                'Copyright © 2026 Agrisale',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                'All Rights Reserved.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '关闭',
              style: TextStyle(
                fontSize: 16,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建紧凑的信息行（用于并排显示）
  Widget _buildCompactInfoRow(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// 下载源选择弹窗
class _DownloadSourceSelectionDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  
  const _DownloadSourceSelectionDialog({
    Key? key,
    required this.updateInfo,
  }) : super(key: key);
  
  @override
  _DownloadSourceSelectionDialogState createState() => _DownloadSourceSelectionDialogState();
}

class _DownloadSourceSelectionDialogState extends State<_DownloadSourceSelectionDialog> {
  Map<int, SourceCheckResult> _sourceStatus = {};
  bool _isChecking = true;
  int? _selectedSourceIndex;
  
  @override
  void initState() {
    super.initState();
    _checkAllSources();
  }
  
  Future<void> _checkAllSources() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final sources = UpdateService.DOWNLOAD_SOURCES;
    
    // 第一步：并行检测所有 API 源
    // 创建检测任务列表（只针对 API 源）
    final apiSourceIndices = <int>[];
    final apiCheckFutures = <Future<_ApiCheckResult>>[];
    
    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source.isDownloadOnlySource) continue;
      
      apiSourceIndices.add(i);
      apiCheckFutures.add(_checkApiSource(source, packageInfo.version, i));
    }
    
    // 并行执行所有 API 源检测
    final apiResults = await Future.wait(apiCheckFutures, eagerError: false);
    
    // 收集结果，找出最高版本
    String? highestVersion;
    String? highestVersionReleaseNotes;
    String? highestVersionGithubUrl;
    
    for (var result in apiResults) {
      // 更新 UI 状态
      if (mounted) {
        setState(() {
          _sourceStatus[result.index] = result.checkResult;
        });
      }
      
      // 记录最高版本
      if (result.checkResult.isAvailable && result.checkResult.updateInfo != null) {
        final versionStr = result.checkResult.updateInfo!.version.replaceAll('v', '');
        if (highestVersion == null || 
            _compareVersions(versionStr, highestVersion!) > 0) {
          highestVersion = versionStr;
          highestVersionReleaseNotes = result.checkResult.updateInfo!.releaseNotes;
          highestVersionGithubUrl = result.checkResult.updateInfo!.githubReleasesUrl;
        }
      }
    }
    
    // 第二步：为纯下载源构建 URL（使用最高版本）
    final versionForDownloadOnly = highestVersion ?? 
        widget.updateInfo.version.replaceAll('v', '');
    
    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      
      if (!source.isDownloadOnlySource) {
        continue; // 已处理
      }
      
      final downloadUrl = source.buildDownloadUrl(
        versionForDownloadOnly, 
        Platform.operatingSystem,
      );
      
      if (mounted) {
        setState(() {
          if (downloadUrl != null) {
            _sourceStatus[i] = SourceCheckResult(
              isAvailable: true,
              updateInfo: UpdateInfo(
                version: 'v$versionForDownloadOnly',
                currentVersion: packageInfo.version,
                releaseNotes: highestVersionReleaseNotes ?? widget.updateInfo.releaseNotes,
                downloadUrl: downloadUrl,
                githubReleasesUrl: highestVersionGithubUrl ?? widget.updateInfo.githubReleasesUrl,
              ),
              error: null,
              requiresApkRename: source.requiresApkRename,
            );
          } else {
            _sourceStatus[i] = SourceCheckResult(
              isAvailable: false,
              updateInfo: null,
              error: '不支持当前平台',
            );
          }
        });
      }
    }
    
    if (mounted) {
      setState(() {
        _isChecking = false;
        // 默认选择第一个可用的源
        for (int i = 0; i < sources.length; i++) {
          if (_sourceStatus[i]?.isAvailable == true) {
            _selectedSourceIndex = i;
            break;
          }
        }
      });
    }
  }
  
  // 检测单个 API 源（用于并行执行）
  Future<_ApiCheckResult> _checkApiSource(DownloadSource source, String currentVersion, int index) async {
    try {
      final updateInfo = await UpdateService.checkFromSource(source, currentVersion);
      return _ApiCheckResult(
        index: index,
        checkResult: SourceCheckResult(
          isAvailable: true,
          updateInfo: updateInfo,
          error: null,
        ),
      );
    } catch (e) {
      return _ApiCheckResult(
        index: index,
        checkResult: SourceCheckResult(
          isAvailable: false,
          updateInfo: null,
          error: e.toString(),
        ),
      );
    }
  }
  
  // 版本号比较 (返回: 1=version1>version2, -1=version1<version2, 0=相等)
  int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final v2Parts = version2.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    
    while (v1Parts.length < 3) v1Parts.add(0);
    while (v2Parts.length < 3) v2Parts.add(0);
    
    for (int i = 0; i < 3; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }
    return 0;
  }
  
  @override
  Widget build(BuildContext context) {
    final sources = UpdateService.DOWNLOAD_SOURCES;
    
    return AlertDialog(
      title: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download, color: Colors.blue),
            SizedBox(width: 8),
            Text('选择下载源'),
          ],
        ),
      ),
      content: Padding(
        padding: EdgeInsets.only(top: 28),
        child: Container(
          width: double.maxFinite,
          child: _isChecking
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在检测下载源...', style: TextStyle(fontSize: 15)),
                  ],
                )
              : ListView.builder(
                shrinkWrap: true,
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final source = sources[index];
                  final status = _sourceStatus[index];
                  
                  return Card(
                    margin: EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: status?.isAvailable == true
                          ? () {
                              setState(() {
                                _selectedSourceIndex = index;
                              });
                            }
                          : null,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Radio<int>(
                                  value: index,
                                  groupValue: _selectedSourceIndex,
                                  onChanged: status?.isAvailable == true
                                      ? (value) {
                                          setState(() {
                                            _selectedSourceIndex = value;
                                          });
                                        }
                                      : null,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            source.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: status?.isAvailable == true
                                                  ? Colors.green[100]
                                                  : Colors.red[100],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              status?.isAvailable == true ? '可用' : '不可用',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: status?.isAvailable == true
                                                    ? Colors.green[800]
                                                    : Colors.red[800],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        source.apiUrl ?? source.downloadUrlBase ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (status?.isAvailable == true && status?.updateInfo != null) ...[
                                        SizedBox(height: 4),
                                        Text(
                                          '版本: ${status!.updateInfo!.version}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      if (status?.isAvailable == false && status?.error != null) ...[
                                        SizedBox(height: 4),
                                        Text(
                                          '错误: ${status!.error}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red[600],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // 只在检测完成后显示开始下载按钮
        if (!_isChecking) ...[
          SizedBox(width: 64),
          TextButton(
            onPressed: _selectedSourceIndex != null
                ? () {
                    final selectedSource = sources[_selectedSourceIndex!];
                    final selectedStatus = _sourceStatus[_selectedSourceIndex!];
                    final selectedUpdateInfo = selectedStatus?.updateInfo;
                    
                    if (selectedUpdateInfo != null) {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => UpdateDialog(
                          updateInfo: selectedUpdateInfo,
                          sourceName: selectedSource.name,
                          requiresApkRename: selectedStatus?.requiresApkRename ?? false,
                        ),
                      );
                    }
                  }
                : null,
            child: Text(
              '开始下载',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// API 源检测结果（用于并行检测）
class _ApiCheckResult {
  final int index;
  final SourceCheckResult checkResult;
  
  _ApiCheckResult({
    required this.index,
    required this.checkResult,
  });
}

// 下载源检测结果
class SourceCheckResult {
  final bool isAvailable;
  final UpdateInfo? updateInfo;
  final String? error;
  final bool requiresApkRename; // 是否需要处理 .apk.bak -> .apk 重命名
  
  SourceCheckResult({
    required this.isAvailable,
    this.updateInfo,
    this.error,
    this.requiresApkRename = false,
  });
}
