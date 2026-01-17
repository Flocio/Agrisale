import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../utils/snackbar_helper.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final String? sourceName; // 下载源名称
  final bool requiresApkRename; // 是否需要处理 .apk.bak -> .apk 重命名
  
  const UpdateDialog({
    Key? key, 
    required this.updateInfo,
    this.sourceName,
    this.requiresApkRename = false,
  }) : super(key: key);
  
  @override
  _UpdateDialogState createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadPath; // 保存下载路径
  String? _downloadSource; // 保存下载来源URL
  
  @override
  void initState() {
    super.initState();
    // 自动开始下载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _downloadUpdate();
    });
  }
  
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
        (received, total, downloadPath, downloadSource) {
          if (mounted) {
            setState(() {
              _downloadedBytes = received;
              _totalBytes = total;
              _downloadPath = downloadPath;
              _downloadSource = downloadSource;
            });
          }
        },
        requiresApkRename: widget.requiresApkRename,
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        
        // 显示下载路径提示
        if (_downloadPath != null) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => AlertDialog(
              title: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('下载完成'),
                  ],
                ),
              ),
              content: Padding(
                padding: EdgeInsets.only(top: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '安装包已下载到',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    SelectableText(
                      _downloadPath!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = '更新失败';
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
          context.showWarningSnackBar('无法打开链接，请手动访问: $url');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('打开链接失败: $e');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _errorMessage != null 
                ? Icons.error_outline 
                : (_isDownloading ? Icons.downloading : Icons.system_update), 
              color: _errorMessage != null ? Colors.red : Colors.blue
            ),
            SizedBox(width: 8),
            Text(_errorMessage != null ? '下载失败' : (_isDownloading ? '正在下载更新...' : '下载更新')),
          ],
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_errorMessage != null) ...[
              Padding(
                padding: EdgeInsets.only(top: 28),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (_isDownloading) ...[
              // 下载信息（居中显示）
              Padding(
                padding: EdgeInsets.only(top: 28),
                child: Column(
                  children: [
                    if (widget.sourceName != null) ...[
                      Text(
                        '下载源：${widget.sourceName}',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                  ],
                  if (_downloadPath != null) ...[
                    Text(
                      '保存路径',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    SelectableText(
                      _downloadPath!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                  ],
                ],
                ),
              ),
              // 进度条
              LinearProgressIndicator(
                value: _totalBytes > 0 ? _downloadedBytes / _totalBytes : null,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              SizedBox(height: 12),
              // 下载进度信息（居中显示，一行显示）
              _totalBytes > 0
                  ? Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${((_downloadedBytes / _totalBytes) * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: '  ${(_downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB / ${(_totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    )
                  : Text(
                      '${(_downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // 如果下载失败，显示知道了按钮
        if (_errorMessage != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '知道了',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // 如果正在下载，显示取消按钮
        if (_isDownloading)
          TextButton(
            onPressed: () {
              UpdateService.cancelDownload();
              Navigator.of(context).pop();
            },
            child: Text(
              '取消',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
  
}
