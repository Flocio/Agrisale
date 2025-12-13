import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  
  const UpdateDialog({Key? key, required this.updateInfo}) : super(key: key);
  
  @override
  _UpdateDialogState createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  
  Future<void> _downloadUpdate() async {
    if (widget.updateInfo.downloadUrl == null) {
      setState(() {
        _errorMessage = '无法获取下载链接\n\n请点击"前往 GitHub 下载"按钮手动下载更新';
      });
      return;
    }
    
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });
    
    try {
      await UpdateService.downloadAndInstall(
        widget.updateInfo.downloadUrl!,
        (received, total) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        
        // 显示安装完成提示
        // 注意：InstallPlugin.installApk() 只是启动安装流程，不等待安装完成
        // 用户需要在系统安装界面中完成所有步骤
        final currentVersion = (await PackageInfo.fromPlatform()).version;
        final targetVersion = widget.updateInfo.version.replaceAll('v', '');
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.system_update, color: Colors.blue),
                SizedBox(width: 8),
                Text('安装提示'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '安装流程已启动。请按照以下步骤完成安装：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 16),
                  _buildInstallStep('1', '在系统安装界面完成安装'),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 24),
                    child: Text(
                      '• 如果看到"安装未知应用"设置页面：\n'
                      '  打开"Allow from this source"开关，然后返回\n'
                      '• 如果看到安装确认对话框：\n'
                      '  点击"Install"按钮\n'
                      '• 如果看到Google Play Protect提示：\n'
                      '  点击"Install without scanning"\n'
                      '• 如果看到"应用未安装"或安装失败：\n'
                      '  说明需要先卸载旧版本（见下方说明）',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Android更新说明',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Android覆盖安装要求：\n'
                          '• 新版本的构建号（versionCode）必须大于旧版本\n'
                          '• 如果构建号相同或更小，会显示"App not installed"\n'
                          '• 这种情况下需要先卸载旧版本再安装\n\n'
                          '如果看到"应用未安装"或"App not installed"：\n'
                          '1. 卸载当前应用\n'
                          '2. 手动从GitHub下载并安装新版本',
                          style: TextStyle(fontSize: 10, color: Colors.blue[900]),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildInstallStep('2', '等待安装完成'),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 24),
                    child: Text(
                      '• 观察安装进度条\n'
                      '• 等待看到"应用已安装"或类似提示\n'
                      '• 如果看到"应用未安装"或安装失败，说明需要先卸载旧版本',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildInstallStep('3', '完全关闭并重新打开应用'),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.only(left: 24),
                    child: Text(
                      '• 按返回键完全退出应用\n'
                      '• 从应用列表重新打开应用\n'
                      '• 在"关于系统"页面检查版本号',
                      style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                            SizedBox(width: 8),
                            Text(
                              '重要：验证安装是否成功',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[900]),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          '重启应用后，请到"关于系统"页面检查版本号。\n\n'
                          '⚠️ 如果版本还是 $currentVersion（应该是 $targetVersion）：\n'
                          '说明安装失败了。可能的原因：\n'
                          '1. 构建号（versionCode）没有递增\n'
                          '2. 签名不匹配\n'
                          '3. 其他系统限制\n\n'
                          '💡 解决方法：\n'
                          '如果看到"App not installed"，说明构建号问题。\n'
                          '请先卸载当前应用，然后手动从GitHub下载并安装新版本。',
                          style: TextStyle(fontSize: 10, color: Colors.orange[900], fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('我知道了'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // 打开GitHub Releases页面，让用户手动下载安装
                  final url = widget.updateInfo.githubReleasesUrl ?? 
                              'https://github.com/Flocio/Agrisale/releases/latest';
                  try {
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已打开GitHub Releases页面，请手动下载并安装APK'),
                          duration: Duration(seconds: 3),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('无法打开链接: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: Icon(Icons.download, size: 18),
                label: Text('手动下载安装'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = '自动更新失败: $e\n\n请尝试手动从 GitHub Releases 下载更新';
        });
      }
    }
  }
  
  Future<void> _openGitHubReleases() async {
    final url = widget.updateInfo.githubReleasesUrl ?? 
                'https://github.com/Flocio/Agrisale/releases/latest';
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法打开链接: $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开链接失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text('发现新版本 ${widget.updateInfo.version}'),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[900], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
            ],
            if (_isDownloading) ...[
              Text('正在下载更新...', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              LinearProgressIndicator(
                value: _totalBytes > 0 ? _downloadedBytes / _totalBytes : null,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(_downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (_totalBytes > 0)
                    Text(
                      '${(_totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
              if (_totalBytes > 0) ...[
                SizedBox(height: 4),
                Text(
                  '${((_downloadedBytes / _totalBytes) * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ] else ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                        SizedBox(width: 8),
                        Text(
                          '当前版本: ${widget.updateInfo.currentVersion}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '最新版本: ${widget.updateInfo.version}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text('更新内容：', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                constraints: BoxConstraints(maxHeight: 200),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.updateInfo.releaseNotes.isEmpty 
                        ? '暂无更新说明' 
                        : widget.updateInfo.releaseNotes,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isDownloading) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('稍后'),
          ),
          // 如果没有下载链接或下载失败，显示 GitHub 链接按钮
          if (widget.updateInfo.downloadUrl == null || _errorMessage != null)
            TextButton.icon(
              onPressed: _openGitHubReleases,
              icon: Icon(Icons.open_in_browser, size: 18),
              label: Text('前往 GitHub 下载'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[700],
              ),
            ),
          // 如果有下载链接且没有错误，显示更新按钮
          if (widget.updateInfo.downloadUrl != null && _errorMessage == null)
            ElevatedButton(
              onPressed: _downloadUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text('立即更新'),
            ),
        ],
      ],
    );
  }
  
  Widget _buildInstallStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

