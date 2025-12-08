import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auto_backup_service.dart';
import '../database_helper.dart';
import '../widgets/footer_widget.dart';

class AutoBackupScreen extends StatefulWidget {
  @override
  _AutoBackupScreenState createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends State<AutoBackupScreen> {
  // 自动备份设置
  bool _autoBackupEnabled = false;
  int _autoBackupInterval = 15; // 分钟
  int _autoBackupMaxCount = 20;
  String? _lastBackupTime;
  int _backupCount = 0;
  bool _isLoading = true;
  final _backupService = AutoBackupService();
  Timer? _countdownTimer; // 倒计时定时器
  String _countdown = '未启动'; // 倒计时文本
  
  final List<int> _availableIntervals = [5, 15, 30, 60, 360, 720, 1440]; // 分钟

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
    _loadBackupCount();
    _startCountdownTimer(); // 启动倒计时定时器
  }
  
  // 启动倒计时定时器，每秒更新一次
  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _countdown = _backupService.formatTimeUntilNextBackup();
        });
      }
    });
  }

  // 加载自动备份设置
  Future<void> _loadBackupSettings() async {
    setState(() {
      _isLoading = true;
    });
    
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId != null) {
        final result = await db.query(
          'user_settings',
          where: 'userId = ?',
          whereArgs: [userId],
        );
        
        if (result.isNotEmpty) {
          final settings = result.first;
          setState(() {
            _autoBackupEnabled = (settings['auto_backup_enabled'] as int?) == 1;
            _autoBackupInterval = (settings['auto_backup_interval'] as int?) ?? 15;
            _autoBackupMaxCount = (settings['auto_backup_max_count'] as int?) ?? 20;
            _lastBackupTime = settings['last_backup_time'] as String?;
            _isLoading = false;
          });
          
          // 不在这里启动定时器，定时器应该在登录时启动，此处只读取设置
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }
  
  // 加载备份数量
  Future<void> _loadBackupCount() async {
    try {
      final backupList = await _backupService.getBackupList();
      setState(() {
        _backupCount = backupList.length;
      });
    } catch (e) {
      print('加载备份数量失败: $e');
    }
  }
  
  // 保存自动备份设置
  Future<void> _saveBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('current_username');
    
    if (username != null) {
      final db = await DatabaseHelper().database;
      final userId = await DatabaseHelper().getCurrentUserId(username);
      
      if (userId != null) {
        await db.update(
          'user_settings',
          {
            'auto_backup_enabled': _autoBackupEnabled ? 1 : 0,
            'auto_backup_interval': _autoBackupInterval,
            'auto_backup_max_count': _autoBackupMaxCount,
          },
          where: 'userId = ?',
          whereArgs: [userId],
        );
      }
    }
  }
  
  // 切换自动备份开关
  Future<void> _toggleAutoBackup(bool enabled) async {
    setState(() {
      _autoBackupEnabled = enabled;
    });
    
    await _saveBackupSettings();
    
    if (enabled) {
      await _backupService.startAutoBackup(_autoBackupInterval);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动备份已开启'), backgroundColor: Colors.green),
      );
    } else {
      await _backupService.stopAutoBackup();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('自动备份已关闭')),
      );
    }
  }
  
  // 更改备份间隔
  Future<void> _changeBackupInterval(int interval) async {
    setState(() {
      _autoBackupInterval = interval;
    });
    
    await _saveBackupSettings();
    
    // 如果自动备份已开启，重启定时器
    if (_autoBackupEnabled) {
      await _backupService.startAutoBackup(_autoBackupInterval);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份间隔已更新为 ${_formatInterval(interval)}')),
      );
    }
  }
  
  // 更改最大保留数量
  Future<void> _changeMaxBackupCount(int count) async {
    setState(() {
      _autoBackupMaxCount = count;
    });
    
    await _saveBackupSettings();
  }
  
  // 格式化时间间隔
  String _formatInterval(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    } else if (minutes < 1440) {
      return '${minutes ~/ 60} 小时';
    } else {
      return '${minutes ~/ 1440} 天';
    }
  }
  
  // 格式化最后备份时间
  String _formatLastBackupTime() {
    if (_lastBackupTime == null) {
      return '从未备份';
    }
    
    try {
      final backupTime = DateTime.parse(_lastBackupTime!);
      final now = DateTime.now();
      final difference = now.difference(backupTime);
      
      if (difference.inMinutes < 1) {
        return '刚刚';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} 分钟前';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} 小时前';
      } else {
        return '${difference.inDays} 天前';
      }
    } catch (e) {
      return '未知';
    }
  }
  
  // 手动执行一次备份
  Future<void> _manualBackup() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在备份...'),
          ],
        ),
      ),
    );
    
    final success = await _backupService.performAutoBackup();
    Navigator.of(context).pop(); // 关闭加载对话框
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('手动备份成功'), backgroundColor: Colors.green),
      );
      _loadBackupSettings();
      _loadBackupCount();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel(); // 取消倒计时定时器
    // 不要在这里停止定时器，因为定时器是全局的
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('数据备份', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.all(16.0),
                    children: [
                      // 自动备份状态卡片
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '自动备份',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Divider(),
                              SwitchListTile(
                                title: Text('启用自动备份'),
                                subtitle: Text(_autoBackupEnabled ? '已开启，系统将定期自动备份数据' : '已关闭'),
                                value: _autoBackupEnabled,
                                onChanged: _toggleAutoBackup,
                                secondary: Icon(
                                  _autoBackupEnabled ? Icons.backup : Icons.backup_outlined,
                                  color: _autoBackupEnabled ? Colors.green : Colors.grey,
                                  size: 32,
                                ),
                              ),
                              
                              if (_autoBackupEnabled) ...[
                                Divider(),
                                ListTile(
                                  leading: Icon(Icons.schedule, color: Colors.blue),
                                  title: Text('上次备份'),
                                  subtitle: Text(_formatLastBackupTime()),
                                ),
                                Divider(),
                                ListTile(
                                  leading: Icon(Icons.timer, color: Colors.orange),
                                  title: Text('下次备份'),
                                  subtitle: Text(_countdown),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      // 备份设置卡片
                      if (_autoBackupEnabled) ...[
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '备份设置',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Divider(),
                                
                                // 备份间隔设置
                                ListTile(
                                  leading: Icon(Icons.timer, color: Colors.orange),
                                  title: Text('备份间隔'),
                                  subtitle: Text('当前: ${_formatInterval(_autoBackupInterval)}'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _availableIntervals.map((interval) {
                                      return ChoiceChip(
                                        label: Text(_formatInterval(interval)),
                                        selected: _autoBackupInterval == interval,
                                        onSelected: (selected) {
                                          if (selected) {
                                            _changeBackupInterval(interval);
                                          }
                                        },
                                        selectedColor: Colors.blue[200],
                                      );
                                    }).toList(),
                                  ),
                                ),
                                SizedBox(height: 16),
                                
                                // 最大保留数量
                                ListTile(
                                  leading: Icon(Icons.inventory, color: Colors.purple),
                                  title: Text('最多保留'),
                                  subtitle: Text('$_autoBackupMaxCount 个备份'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Slider(
                                    value: _autoBackupMaxCount.toDouble(),
                                    min: 5,
                                    max: 50,
                                    divisions: 9,
                                    label: '$_autoBackupMaxCount',
                                    onChanged: (value) {
                                      _changeMaxBackupCount(value.toInt());
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                      ],
                      
                      // 备份管理卡片
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '备份管理',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Divider(),
                              ListTile(
                                leading: Icon(Icons.backup, color: Colors.green),
                                title: Text('立即备份'),
                                subtitle: Text('手动执行一次数据备份'),
                                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: _manualBackup,
                              ),
                              Divider(),
                              ListTile(
                                leading: Icon(Icons.folder_open, color: Colors.blue),
                                title: Text('查看所有备份'),
                                subtitle: Text('当前有 $_backupCount 个备份'),
                                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () async {
                                  await Navigator.of(context).pushNamed('/auto_backup_list');
                                  _loadBackupCount(); // 返回后刷新备份数量
                                },
                              ),
                              Divider(),
                              ListTile(
                                leading: Icon(Icons.delete_sweep, color: Colors.red),
                                title: Text('清理所有备份'),
                                subtitle: Text('删除所有自动备份文件'),
                                trailing: Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () async {
                                  if (_backupCount == 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('没有备份可删除')),
                                    );
                                    return;
                                  }
                                  
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('确认清理', style: TextStyle(color: Colors.red[700])),
                                      content: Text('确定要删除所有 $_backupCount 个自动备份吗？\n\n此操作不可撤销！'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(false),
                                          child: Text('取消'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.of(context).pop(true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: Text('全部删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirm == true) {
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) => AlertDialog(
                                        content: Row(
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(width: 20),
                                            Text('正在删除...'),
                                          ],
                                        ),
                                      ),
                                    );
                                    
                                    final deletedCount = await _backupService.deleteAllBackups();
                                    Navigator.of(context).pop(); // 关闭加载对话框
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('已删除 $deletedCount 个备份')),
                                    );
                                    _loadBackupCount();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 16),
                      
                      // 使用说明卡片
                      Card(
                        elevation: 2,
                        color: Colors.blue[50],
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.blue[700]),
                                  SizedBox(width: 8),
                                  Text(
                                    '使用说明',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              _buildInfoText('• 自动备份仅在应用运行时生效'),
                              _buildInfoText('• 备份文件保存在本地，不会上传到云端'),
                              _buildInfoText('• 备份不包含您的个人设置（API Key等）'),
                              _buildInfoText('• 超过最大保留数量时，自动删除最旧的备份'),
                              _buildInfoText('• 恢复备份会覆盖当前数据，请谨慎操作'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FooterWidget(),
              ],
            ),
    );
  }
  
  Widget _buildInfoText(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.blue[800]),
      ),
    );
  }
}

