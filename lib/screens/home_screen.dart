import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/lock_config.dart';
import '../services/ble_service.dart';
import 'config_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LockConfig> _locks = [];
  final BleService _bleService = BleService();
  String _log = '';
  bool _isUnlocking = false;
  int? _unlockingIndex;
  bool _showLog = true;

  @override
  void initState() {
    super.initState();
    _loadLocks();
    _loadShowLog();
    _bleService.logStream.listen((msg) {
      if (mounted) {
        setState(() {
          _log = '$_log\n$msg';
        });
      }
    });
  }

  Future<void> _loadLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    if (locksJson != null) {
      final List<dynamic> list = jsonDecode(locksJson);
      setState(() {
        _locks = list.map((e) => LockConfig.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));
  }

  Future<void> _loadShowLog() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showLog = prefs.getBool('showLog') ?? true;
    });
  }

  Future<void> _saveShowLog(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showLog', value);
  }

  void _toggleLog() {
    setState(() {
      _showLog = !_showLog;
    });
    _saveShowLog(_showLog);
  }

  Future<void> _unlock(LockConfig config, int index) async {
    setState(() {
      _isUnlocking = true;
      _unlockingIndex = index;
      _log = '';
    });
    try {
      final connected = await _bleService.connectToDevice(config);
      if (connected) {
        await _bleService.unlock(config);
      }
    } finally {
      await _bleService.disconnect();
      if (mounted) {
        setState(() {
          _isUnlocking = false;
          _unlockingIndex = null;
        });
      }
    }
  }

  void _addLock() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConfigScreen()),
    );
    if (result != null && result is LockConfig) {
      setState(() {
        _locks.add(result);
      });
      _saveLocks();
    }
  }

  void _editLock(int index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigScreen(config: _locks[index]),
      ),
    );
    if (result != null && result is LockConfig) {
      setState(() {
        _locks[index] = result;
      });
      _saveLocks();
    }
  }

  void _deleteLock(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除门禁'),
        content: Text('确定要删除「${_locks[index].doorName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _locks.removeAt(index);
              });
              _saveLocks();
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ========== 备份与恢复 ==========
  Future<void> _backupLocks() async {
    if (_locks.isEmpty) {
      _showSnackBar('没有门禁可备份');
      return;
    }
    final data = {
      'version': 1,
      'app': 'baiyun_keys',
      'locks': _locks.map((e) => e.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    _showSnackBar('已复制 ${_locks.length} 个门禁配置到剪贴板');
  }

  Future<void> _restoreLocks() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null || clipboardData.text!.isEmpty) {
      _showSnackBar('剪贴板为空，请先复制备份文本');
      return;
    }
    try {
      final data = jsonDecode(clipboardData.text!);
      if (data is! Map || data['locks'] is! List) {
        _showSnackBar('备份格式不正确');
        return;
      }
      final List<dynamic> locksList = data['locks'];
      int added = 0;
      for (final item in locksList) {
        if (item is Map) {
          try {
            final config = LockConfig.fromJson(item);
            setState(() {
              _locks.add(config);
            });
            added++;
          } catch (_) {}
        }
      }
      if (added > 0) {
        _saveLocks();
        _showSnackBar('成功导入 $added 个门禁配置');
      } else {
        _showSnackBar('没有可导入的门禁配置');
      }
    } catch (e) {
      _showSnackBar('解析失败，请确认备份文本正确');
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF0D9488),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.key, color: Colors.tealAccent, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      '包子的key',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 日志开关
                    IconButton(
                      icon: Icon(
                        _showLog ? Icons.visibility : Icons.visibility_off,
                        color: _showLog ? Colors.tealAccent : Colors.grey,
                        size: 22,
                      ),
                      onPressed: _toggleLog,
                      tooltip: _showLog ? '隐藏日志' : '显示日志',
                    ),
                    // 备份恢复菜单
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
                      color: const Color(0xFF1A2A3A),
                      onSelected: (value) {
                        if (value == 'backup') _backupLocks();
                        if (value == 'restore') _restoreLocks();
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'backup',
                          child: Row(
                            children: [
                              Icon(Icons.copy, size: 18, color: Colors.tealAccent),
                              SizedBox(width: 8),
                              Text('一键复制', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'restore',
                          child: Row(
                            children: [
                              Icon(Icons.paste, size: 18, color: Colors.tealAccent),
                              SizedBox(width: 8),
                              Text('一键导入', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 门禁列表
              Expanded(
                child: _locks.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.key, size: 56, color: Colors.white24),
                            SizedBox(height: 12),
                            Text('还没有添加门禁', style: TextStyle(fontSize: 16, color: Colors.white54)),
                            SizedBox(height: 6),
                            Text('点击右下角按钮添加', style: TextStyle(fontSize: 13, color: Colors.white38)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _locks.length,
                        itemBuilder: (context, index) {
                          final lock = _locks[index];
                          final isUnlocking = _unlockingIndex == index;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2A3A).withOpacity(0.8),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.teal.withOpacity(0.2)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.door_front_door, color: Colors.tealAccent, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          lock.doorName,
                                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                                        onPressed: () => _editLock(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                                        onPressed: () => _deleteLock(index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('MAC: ${lock.mac}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  Text('蓝牙: ${lock.bluetoothName}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  const SizedBox(height: 10),
                                  // 渐变开锁按钮
                                  SizedBox(
                                    width: double.infinity,
                                    height: 40,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: _isUnlocking
                                            ? null
                                            : const LinearGradient(
                                                colors: [Color(0xFF0D9488), Color(0xFF0891B2)],
                                              ),
                                        color: _isUnlocking ? Colors.grey : null,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onPressed: _isUnlocking ? null : () => _unlock(lock, index),
                                          child: Center(
                                            child: isUnlocking
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : const Row(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.lock_open, size: 18, color: Colors.white),
                                                      SizedBox(width: 6),
                                                      Text('开锁', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // 日志区域
              if (_showLog && _log.isNotEmpty)
                Container(
                  height: 100,
                  width: double.infinity,
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.withOpacity(0.2)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _log,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLock,
        tooltip: '添加门禁',
        backgroundColor: const Color(0xFF0D9488),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}
