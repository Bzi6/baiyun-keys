import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  int _selectedIndex = 0;
  bool _selectorOpen = false;
  bool _paramsHidden = false;
  bool _logEnabled = false;

  final BleService _bleService = BleService();
  String _log = '';
  bool _isUnlocking = false;
  String _statusMessage = '';
  String _statusTone = 'normal'; // normal / active / error

  @override
  void initState() {
    super.initState();
    _loadLocks();
    _loadLogPreference();
    _bleService.logStream.listen((msg) {
      if (mounted && _logEnabled) {
        setState(() {
          _log = '$_log\n$msg';
        });
      }
    });
  }

  Future<void> _loadLogPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _logEnabled = prefs.getBool('logEnabled') ?? false;
    });
  }

  Future<void> _toggleLog(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logEnabled', value);
    setState(() {
      _logEnabled = value;
      if (!value) _log = '';
    });
  }

  Future<void> _loadLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    if (locksJson != null) {
      final List<dynamic> list = jsonDecode(locksJson);
      setState(() {
        _locks = list.map((e) => LockConfig.fromJson(e)).toList();
        if (_selectedIndex >= _locks.length) _selectedIndex = 0;
      });
    }
  }

  Future<void> _saveLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));
  }

  LockConfig? get _currentLock {
    if (_locks.isEmpty || _selectedIndex >= _locks.length) return null;
    return _locks[_selectedIndex];
  }

  String get _maskedMac {
    final mac = _currentLock?.mac ?? '';
    if (mac.length < 8) return mac;
    return '${mac.substring(0, 6)}••••${mac.substring(mac.length - 2)}';
  }

  String get _maskedKey {
    final key = _currentLock?.productKey ?? '';
    if (key.length < 8) return key;
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
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
          _statusTone = result.contains('成功') || result.contains('开启') ? 'normal' : 'error';
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              setState(() {
                _locks.removeAt(_selectedIndex);
                if (_selectedIndex >= _locks.length) _selectedIndex = 0;
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

  @override
  Widget build(BuildContext context) {
    final lock = _currentLock;
    final canSubmit = lock != null;

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2FB),
      appBar: AppBar(
        title: const Text('包子的key', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Switch(value: _logEnabled, onChanged: _toggleLog, activeColor: const Color(0xFF2563EB)),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDF2FB), Color(0xFFF8FAFC)])),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // 蓝牙门禁卡片
            _buildCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('蓝牙门禁', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                const SizedBox(height: 14),

                // 门禁选择器
                GestureDetector(
                  onTap: () => setState(() => _selectorOpen = !_selectorOpen),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFFBFDFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6EBF1))),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: const Color(0xFFE9FBF2), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.location_on, size: 18, color: Color(0xFF12B981)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(lock?.doorName ?? '请先添加门禁', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: lock == null ? const Color(0xFF9AA5B3) : const Color(0xFF111827), overflow: TextOverflow.ellipsis))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFEAF2FF), borderRadius: BorderRadius.circular(20)),
                        child: const Text('BLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                      ),
                      const SizedBox(width: 6),
                      Icon(_selectorOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: const Color(0xFF9AA5B3)),
                    ]),
                  ),
                ),

                // 下拉列表
                if (_selectorOpen && _locks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFF8FBFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6EBF1))),
                    child: Column(children: _locks.asMap().entries.map((e) {
                      final isActive = e.key == _selectedIndex;
                      return GestureDetector(
                        onTap: () => setState(() { _selectedIndex = e.key; _selectorOpen = false; }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: isActive ? const Color(0xFFF0F7FF) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isActive ? const Color(0xFFC8DCFF) : Colors.transparent)),
                          child: Row(children: [
                            Expanded(child: Text(e.value.doorName, style: TextStyle(fontSize: 13, color: isActive ? const Color(0xFF253041) : const Color(0xFF7B8796), overflow: TextOverflow.ellipsis))),
                            if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFE9FBF2), borderRadius: BorderRadius.circular(20)), child: const Text('当前', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0E9F6E)))),
                          ]),
                        ),
                      );
                    }).toList()),
                  ),
                ],

                // 门禁信息面板
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6EBF1))),
                  child: Column(children: [
                    Row(children: [
                      const Text('门禁信息', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9AA5B3))),
                      const Spacer(),
                      GestureDetector(onTap: () => setState(() => _paramsHidden = !_paramsHidden), child: Icon(_paramsHidden ? Icons.visibility_off : Icons.visibility, size: 18, color: const Color(0xFF9AA5B3))),
                    ]),
                    const SizedBox(height: 8),
                    _buildParamItem('门禁 MAC', _paramsHidden ? _maskedMac : (lock?.mac ?? '—')),
                    _buildParamItem('门禁 Key', _paramsHidden ? _maskedKey : (lock?.productKey ?? '—')),
                  ]),
                ),

                // 开锁按钮
                const SizedBox(height: 18),
                Center(
                  child: SizedBox(
                    width: 220, height: 50,
                    child: ElevatedButton(
                      onPressed: (!canSubmit || _isUnlocking) ? null : _unlock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (_isUnlocking) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        else const Icon(Icons.lock_open, size: 18),
                        const SizedBox(width: 8),
                        Text(_isUnlocking ? '执行中...' : '立即开锁', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  canSubmit ? (_isUnlocking ? '正在连接和握手，请保持手机靠近门锁' : '靠近门锁后点击按钮即可尝试开锁') : '请先前往配置页补全门禁参数',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF7B8796)),
                  textAlign: TextAlign.center,
                ),

                // 编辑/删除按钮
                if (lock != null) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: TextButton.icon(onPressed: _editLock, icon: const Icon(Icons.edit, size: 16), label: const Text('编辑', style: TextStyle(fontSize: 13)), style: TextButton.styleFrom(foregroundColor: const Color(0xFF2563EB)))),
                    Expanded(child: TextButton.icon(onPressed: _deleteLock, icon: const Icon(Icons.delete, size: 16), label: const Text('删除', style: TextStyle(fontSize: 13)), style: TextButton.styleFrom(foregroundColor: const Color(0xFFE14B55)))),
                  ]),
                ],
              ]),
            ),

            // 状态卡片
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStatusCard(),
            ],

            // 调试日志卡片
            if (_logEnabled) ...[
              const SizedBox(height: 12),
              _buildCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.article, size: 16, color: Color(0xFF7B8796)),
                    const SizedBox(width: 6),
                    const Text('调试日志', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5EDF6))), child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: _isUnlocking ? const Color(0xFF2563EB) : const Color(0xFF8793A3), borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 4),
                      Text(_isUnlocking ? '运行中' : '等待日志', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7B8796))),
                    ])),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    height: 160,
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF0A1728), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF14243A))),
                    child: SingleChildScrollView(
                      child: Text(
                        _log.isEmpty ? '暂无日志，点击「立即开锁」开始调试' : _log,
                        style: const TextStyle(color: Color(0xFF65D98D), fontSize: 11, fontFamily: 'monospace', height: 1.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(onPressed: () => setState(() => _log = ''), child: const Text('清空日志', style: TextStyle(fontSize: 13, color: Color(0xFF1F6FFF)))),
                    const SizedBox(width: 40),
                    TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: _log)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志已复制'))); }, child: const Text('复制日志', style: TextStyle(fontSize: 13, color: Color(0xFF00866B)))),
                  ]),
                ]),
              ),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLock,
        tooltip: '添加门禁',
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF1)),
        boxShadow: [BoxShadow(color: const Color(0xFF1F2937).withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _buildParamItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7B8796)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF253041), fontFamily: 'monospace', overflow: TextOverflow.ellipsis))),
      ]),
    );
  }

  Widget _buildStatusCard() {
    Color bgColor, borderColor, textColor;
    switch (_statusTone) {
      case 'active':
        bgColor = const Color(0xFFF3F8FF); borderColor = const Color(0xFFC8DDFF); textColor = const Color(0xFF2563EB); break;
      case 'error':
        bgColor = const Color(0xFFFFF1F2); borderColor = const Color(0xFFFFD1D6); textColor = const Color(0xFFD23B48); break;
      default:
        bgColor = const Color(0xFFECFDF5); borderColor = const Color(0xFFBCEFD4); textColor = const Color(0xFF0C9868); break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: textColor, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(child: Text(_statusMessage, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
      ]),
    );
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}
