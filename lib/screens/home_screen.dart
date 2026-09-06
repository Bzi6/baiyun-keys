import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lock_config.dart';
import '../services/ble_service.dart';
import '../services/lock_protocol.dart';
import 'config_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LockConfig> _locks = [];
  int _selectedIndex = 0;
  bool _selectorOpen = false;
  bool _paramsHidden = true;
  bool _logEnabled = false;
  bool _isUnlocking = false;
  String _log = '';
  String _statusMessage = '';
  String _statusTone = 'normal';

  final BleService _bleService = BleService();

  @override
  void initState() {
    super.initState();
    _loadLocks();
    _loadSettings();
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
        _locks = list.map((e) => LockConfig.fromJson(e as Map<String, dynamic>)).toList();
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logEnabled = prefs.getBool('logEnabled') ?? false;
      _paramsHidden = prefs.getBool('paramsHidden') ?? true;
    });
  }

  Future<void> _saveLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));
  }

  Future<void> _toggleLog() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logEnabled = !_logEnabled;
    });
    await prefs.setBool('logEnabled', _logEnabled);
  }

  LockConfig? get _currentLock {
    if (_locks.isEmpty || _selectedIndex >= _locks.length) return null;
    return _locks[_selectedIndex];
  }

  String _maskText(String text) {
    if (text.length <= 6) return '••••••';
    return '${text.substring(0, 3)}••••••${text.substring(text.length - 3)}';
  }

  Future<void> _unlock() async {
    final lock = _currentLock;
    if (lock == null) return;

    setState(() {
      _isUnlocking = true;
      _log = '';
      _statusMessage = '正在连接和握手，请保持手机靠近门锁';
      _statusTone = 'active';
    });

    try {
      final connected = await _bleService.connectToDevice(lock);
      if (connected) {
        final result = await _bleService.unlock(lock);
        setState(() {
          _statusMessage = result;
          _statusTone =
              result.contains('成功') || result.contains('开启') ? 'normal' : 'error';
        });
      } else {
        setState(() {
          _statusMessage = '连接失败，请确认设备已开启且在附近';
          _statusTone = 'error';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '开锁失败: $e';
        _statusTone = 'error';
      });
    } finally {
      await _bleService.disconnect();
      if (mounted) {
        setState(() {
          _isUnlocking = false;
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
        _selectedIndex = _locks.length - 1;
      });
      _saveLocks();
    }
  }

  void _editLock() async {
    final lock = _currentLock;
    if (lock == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ConfigScreen(config: lock)),
    );
    if (result != null && result is LockConfig) {
      setState(() {
        _locks[_selectedIndex] = result;
      });
      _saveLocks();
    }
  }

  void _deleteLock() {
    final lock = _currentLock;
    if (lock == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除门禁'),
        content: Text('确定要删除「${lock.doorName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _locks.removeAt(_selectedIndex);
                if (_selectedIndex >= _locks.length) {
                  _selectedIndex = _locks.isEmpty ? 0 : _locks.length - 1;
                }
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

  /// 生成单个门禁的备份文本（和小程序格式一致）
  String _buildBackupText(LockConfig config) {
    final name = config.doorName.trim().isEmpty ? '未命名' : config.doorName.trim();
    final mac = config.mac.trim().isEmpty ? '缺失' : config.mac.trim();
    final key = config.productKey.trim().isEmpty ? '缺失' : config.productKey.trim();
    final bluetoothName = config.bluetoothName.trim();

    final lines = ['门禁名称：$name', 'MAC：$mac', 'Key：$key'];

    // 蓝牙名称只有与MAC推导不一致时才包含（和小程序一致）
    final derived = LockProtocol.deriveBluetoothNameFromMac(mac);
    if (bluetoothName.isNotEmpty &&
        derived.isNotEmpty &&
        bluetoothName.toUpperCase() != derived.toUpperCase()) {
      lines.add('蓝牙名称：$bluetoothName');
    }

    return lines.join('\n');
  }

  /// 一键复制备份（和小程序格式一致）
  void _copyBackup() async {
    if (_locks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可备份的门禁')),
      );
      return;
    }

    String backupText;
    if (_locks.length == 1) {
      backupText = _buildBackupText(_locks[0]);
    } else {
      backupText = _locks
          .asMap()
          .entries
          .map((e) => '【门禁 ${e.key + 1}】\n${_buildBackupText(e.value)}')
          .join('\n\n');
    }

    await Clipboard.setData(ClipboardData(text: backupText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板，请妥善保存')),
      );
    }
  }

  /// 一键导入恢复（和小程序源码一致，简单解析）
  void _importBackup() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴门禁参数'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: '请粘贴一键复制的门禁参数文本',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, controller.text),
            child: const Text('开始导入'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    final lines = result.split(RegExp(r'\r?\n'));
    final blocks = <Map<String, String>>[];
    var current = <String, String>{
      'doorName': '',
      'mac': '',
      'key': '',
      'bluetoothName': '',
    };

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (RegExp(r'^【门禁\s*\d+】$').hasMatch(line)) {
        if (current['mac']!.isNotEmpty && current['key']!.isNotEmpty) {
          blocks.add(Map.from(current));
        }
        current = {
          'doorName': '',
          'mac': '',
          'key': '',
          'bluetoothName': '',
        };
        continue;
      }

      final nameMatch = RegExp(r'^门禁名称[：:]\s*(.+)$').firstMatch(line);
      if (nameMatch != null) {
        current['doorName'] = nameMatch.group(1)!.trim();
        continue;
      }

      final macMatch = RegExp(r'^MAC[：:]\s*(.+)$').firstMatch(line);
      if (macMatch != null) {
        current['mac'] = macMatch.group(1)!.trim();
        continue;
      }

      final keyMatch = RegExp(r'^Key[：:]\s*(.+)$').firstMatch(line);
      if (keyMatch != null) {
        current['key'] = keyMatch.group(1)!.trim();
        continue;
      }

      final bluetoothMatch = RegExp(r'^蓝牙名称[：:]\s*(.+)$').firstMatch(line);
      if (bluetoothMatch != null) {
        current['bluetoothName'] = bluetoothMatch.group(1)!.trim();
        continue;
      }
    }

    // 处理最后一个
    if (current['mac']!.isNotEmpty && current['key']!.isNotEmpty) {
      blocks.add(Map.from(current));
    }

    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未识别到有效门禁参数')),
      );
      return;
    }

    var added = 0;
    setState(() {
      for (final b in blocks) {
        final mac = b['mac']!.toUpperCase();
        final exists = _locks.any((l) => l.mac.toUpperCase() == mac);
        if (exists) continue;

        final bluetoothName = b['bluetoothName']!.isNotEmpty
            ? b['bluetoothName']!.toUpperCase()
            : LockProtocol.deriveBluetoothNameFromMac(mac);

        _locks.add(LockConfig(
          doorName: b['doorName']!.isEmpty ? '导入门禁' : b['doorName']!,
          mac: mac,
          bluetoothName: bluetoothName,
          productKey: b['key']!.toUpperCase(),
        ));
        added++;
      }
    });

    _saveLocks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $added 个门禁')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = _currentLock;

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2FB),
      appBar: AppBar(
        title: const Text('包子的key',
            style: TextStyle(
                color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF0F172A)),
            onSelected: (value) {
              if (value == 'backup') _copyBackup();
              if (value == 'restore') _importBackup();
              if (value == 'log') _toggleLog();
              if (value == 'edit' && lock != null) _editLock();
              if (value == 'delete' && lock != null) _deleteLock();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'backup', child: Text('一键复制备份')),
              const PopupMenuItem(value: 'restore', child: Text('一键导入恢复')),
              if (lock != null) const PopupMenuItem(value: 'edit', child: Text('编辑当前门禁')),
              if (lock != null) const PopupMenuItem(value: 'delete', child: Text('删除当前门禁')),
              PopupMenuItem(
                  value: 'log',
                  child: Text(_logEnabled ? '关闭调试日志' : '开启调试日志')),
            ],
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEDF2FB), Color(0xFFF8FAFC)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE6EBF1)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1F2937).withOpacity(0.045),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '蓝牙门禁',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectorOpen = !_selectorOpen;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFDFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE6EBF1)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9FBF2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_on,
                                size: 18, color: Color(0xFF0E9F6E)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              lock?.doorName ?? '暂无门禁',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111827)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'BLE',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _selectorOpen
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: const Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectorOpen && _locks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE6EBF1)),
                      ),
                      child: Column(
                        children: List.generate(_locks.length, (i) {
                          final isActive = i == _selectedIndex;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedIndex = i;
                                _selectorOpen = false;
                              });
                            },
                            child: Container(
                              margin: EdgeInsets.only(
                                  bottom: i == _locks.length - 1 ? 0 : 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? const Color(0xFFF0F7FF)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isActive
                                      ? const Color(0xFFC8DCFF)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _locks[i].doorName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isActive
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFF253041),
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF12B981),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        '当前',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (lock != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE6EBF1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '门禁信息',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF9AA5B3)),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  setState(() {
                                    _paramsHidden = !_paramsHidden;
                                  });
                                  await prefs.setBool(
                                      'paramsHidden', _paramsHidden);
                                },
                                child: Icon(
                                  _paramsHidden
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 18,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '门禁 MAC',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7B8796)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _paramsHidden ? _maskText(lock.mac) : lock.mac,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF253041),
                                fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '门禁 Key',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7B8796)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _paramsHidden
                                ? _maskText(lock.productKey)
                                : lock.productKey,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF253041),
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: GestureDetector(
                      onTap: _isUnlocking || lock == null ? null : _unlock,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _isUnlocking || lock == null
                                ? [
                                    const Color(0xFFCBD5E1),
                                    const Color(0xFFCBD5E1)
                                  ]
                                : [
                                    const Color(0xFF17C878),
                                    const Color(0xFF10A86B)
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: _isUnlocking || lock == null
                              ? null
                              : [
                                  BoxShadow(
                                    color: const Color(0xFF10B981)
                                        .withOpacity(0.22),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isUnlocking)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              else
                                const Icon(Icons.lock_open,
                                    size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                _isUnlocking
                                    ? '执行中...'
                                    : (lock == null ? '请先添加门禁' : '立即开锁'),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    lock == null
                        ? '点击右下角按钮添加门禁'
                        : (_isUnlocking
                            ? '正在连接和握手，请保持手机靠近门锁'
                            : '靠近门锁后点击按钮即可尝试开锁'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF7B8796)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_statusMessage.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _statusTone == 'error'
                      ? const Color(0xFFFFF1F2)
                      : (_statusTone == 'active'
                          ? const Color(0xFFF3F8FF)
                          : const Color(0xFFECFDF5)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _statusTone == 'error'
                        ? const Color(0xFFFFD1D6)
                        : (_statusTone == 'active'
                            ? const Color(0xFFC8DDFF)
                            : const Color(0xFFBCEFD4)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _statusTone == 'error'
                            ? const Color(0xFFD23B48)
                            : (_statusTone == 'active'
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF0C9868)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _statusTone == 'error'
                              ? const Color(0xFFD23B48)
                              : (_statusTone == 'active'
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF0C9868)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (_logEnabled)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE6EBF1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.article,
                                size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            const Text(
                              '调试日志',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _log));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('日志已复制')),
                                );
                              },
                              child: const Text('复制',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _log = '';
                                });
                              },
                              child: const Text('清空',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 150,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1728),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _log.isEmpty
                              ? '暂无日志，点击「立即开锁」开始调试'
                              : _log,
                          style: const TextStyle(
                              color: Color(0xFF65D98D),
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLock,
        backgroundColor: const Color(0xFF2563EB),
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
