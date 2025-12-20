// lib/screens/version_info_screen.dart

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import 'update_dialog.dart';
import 'help_screen.dart';

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
        if (updateInfo != null) {
          _updateInfo = updateInfo;
        } else {
          // 已是最新版本
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('当前已是最新版本'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    } catch (e) {
      setState(() {
        _isChecking = false;
        _checkError = '检查更新失败: $e';
      });
    }
  }

  void _showUpdateDialog() {
    if (_updateInfo != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => UpdateDialog(updateInfo: _updateInfo!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('关于系统', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
      ),
      body: _packageInfo == null
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 当前版本信息卡片
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.green[700], size: 28),
                              SizedBox(width: 12),
                              Text(
                                '当前版本',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          _buildInfoRow('版本号', _packageInfo!.version),
                          SizedBox(height: 12),
                          _buildInfoRow('构建号', _packageInfo!.buildNumber),
                          SizedBox(height: 12),
                          _buildInfoRow('应用名称', _packageInfo!.appName),
                          SizedBox(height: 12),
                          _buildInfoRow('包名', _packageInfo!.packageName),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 20),
                  
                  // 检查更新按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isChecking ? null : _checkForUpdate,
                      icon: _isChecking
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(Icons.system_update),
                      label: Text(_isChecking ? '正在检查更新...' : '检查更新'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  
                  
                  // 检查错误提示
                  if (_checkError != null) ...[
                    SizedBox(height: 16),
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
                              _checkError!,
                              style: TextStyle(color: Colors.red[900], fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // 更新信息卡片
                  if (_updateInfo != null) ...[
                    SizedBox(height: 20),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      color: Colors.blue[50],
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.system_update, color: Colors.blue[700], size: 28),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '发现新版本 ${_updateInfo!.version}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    final url = 'https://github.com/Flocio/Agrisale/releases/latest';
                                    try {
                                      final uri = Uri.parse(url);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } else {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('无法打开链接，请手动访问: $url'),
                                              backgroundColor: Colors.orange,
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('打开链接失败: $e'),
                                            backgroundColor: Colors.red,
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: Icon(Icons.open_in_new, size: 18),
                                  tooltip: 'Github',
                                  padding: EdgeInsets.all(4),
                                  constraints: BoxConstraints(),
                                  style: IconButton.styleFrom(
                                    foregroundColor: Colors.blue[700],
                                    minimumSize: Size(32, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            if (_updateInfo!.releaseNotes.isNotEmpty) ...[
                              SizedBox(height: 16),
                              SizedBox(height: 16),
                              Text(
                                '更新内容：',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
                                    _updateInfo!.releaseNotes,
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                            SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _showUpdateDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text('立即更新'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  
                  SizedBox(height: 20),
                  
                  // 系统信息卡片
                  Card(
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
                            '系统信息',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Divider(),
                          ListTile(
                            leading: Icon(Icons.help_outline, color: Colors.blue),
                            title: Text('使用帮助'),
                            subtitle: Text('查看系统使用说明和功能介绍'),
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
                          Divider(),
                          ListTile(
                            leading: Icon(Icons.info_outline, color: Colors.blue),
                            title: Text('系统信息'),
                            subtitle: Text('Agrisale v${_packageInfo!.version}'),
                            trailing: Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'Agrisale',
                                applicationVersion: 'v${_packageInfo!.version}',
                                applicationIcon: Image.asset(
                                  'assets/images/background.png',
                                  width: 50,
                                  height: 50,
                                ),
                                applicationLegalese: '© 2025 Agrisale',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

