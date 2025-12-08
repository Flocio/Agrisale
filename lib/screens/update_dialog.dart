import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新已开始安装，请按照提示完成安装'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.green,
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
}

