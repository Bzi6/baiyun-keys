import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lock_config.dart';
import '../services/ble_service.dart';
import 'config_screen.dart';
import 'help_screen.dart';

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
  final BleService _bleService = BleService();
  bool _isUnlocking = false;
  bool _isCancelled = false;
  String _statusText = '';
  String _statusType = 'idle'; // idle, unlocking, success, error, cancelled

  @override
  void initState() {
    super.initState();
    _loadLocks();
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
      _isCancelled = false;
      _statusText = '开锁中';
      _statusType = 'unlocking';
    });

    try {
      final connected = await _bleService.connectToDevice(lock);
      if (_isCancelled) {
        await _bleService.disconnect();
        setState(() {
          _isUnlocking = false;
          _statusText = '已中断';
          _statusType = 'cancelled';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已中断当前开锁流程'), duration: Duration(seconds: 2)));
        return;
      }
      if (connected) {
        final result = await _bleService.unlock(lock);
        if (_isCancelled) {
          await _bleService.disconnect();
          setState(() {
            _isUnlocking = false;
            _statusText = '已中断';
            _statusType = 'cancelled';
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已中断当前开锁流程'), duration: Duration(seconds: 2)));
          return;
        }
        setState(() {
          _isUnlocking = false;
          _statusText = result.contains('成功') || result.contains('开启') ? '开锁成功' : result;
          _statusType = result.contains('成功') || result.contains('开启') ? 'success' : 'error';
        });
      } else {
        setState(() {
          _isUnlocking = false;
          _statusText = '连接失败';
          _statusType = 'error';
        });
      }
    } catch (e) {
      if (_isCancelled) {
        setState(() {
          _isUnlocking = false;
          _statusText = '已中断';
          _statusType = 'cancelled';
        });
      } else {
        setState(() {
          _isUnlocking = false;
          _statusText = '开锁失败';
          _statusType = 'error';
        });
      }
    } finally {
      await _bleService.disconnect();
    }
  }

  void _cancelUnlock() {
    setState(() => _isCancelled = true);
    _bleService.disconnect();
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ConfigScreen()));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const HelpScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = _currentLock;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('包子的key', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _buildMainCard(lock),
          const SizedBox(height: 12),
          if (_statusText.isNotEmpty) _buildStatusBar(),
        ]),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.code), label: '配置'),
          BottomNavigationBarItem(icon: Icon(Icons.energy_savings_leaf), label: '帮助'),
        ],
        currentIndex: 0,
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: const Color(0xFF9CA3AF),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildMainCard(LockConfig? lock) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('蓝牙门禁', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
        const SizedBox(height: 16),
        _buildDoorSelector(lock),
        const SizedBox(height: 16),
        _buildParamsSection(lock),
        const SizedBox(height: 24),
        _buildUnlockButton(),
        const SizedBox(height: 12),
        Text(
          _isUnlocking ? '正在连接和握手，请保持手机靠近门锁' : '靠近门锁后点击按钮即可尝试开锁',
          style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          textAlign: TextAlign.center,
        ),
        if (_isUnlocking) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelUnlock,
              icon: const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
              label: const Text('取消', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFFEF2F2),
                side: const BorderSide(color: Color(0xFFFECACA)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildDoorSelector(LockConfig? lock) {
    return GestureDetector(
      onTap: () => setState(() => _selectorOpen = !_selectorOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.location_on, size: 20, color: Color(0xFF10B981))),
          const SizedBox(width: 12),
          Expanded(child: Text(lock?.doorName ?? '请先添加门禁', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: lock == null ? const Color(0xFF9CA3AF) : const Color(0xFF111827), overflow: TextOverflow.ellipsis))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(12)), child: const Text('BLE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)))),
          const SizedBox(width: 8),
          Icon(_selectorOpen ? Icons.keyboard_arrow_down : Icons.chevron_right, size: 22, color: const Color(0xFF9CA3AF)),
        ]),
      ),
    );
  }

  Widget _buildParamsSection(LockConfig? lock) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('门禁信息', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
          const Spacer(),
          GestureDetector(onTap: () => setState(() => _paramsHidden = !_paramsHidden), child: Icon(_paramsHidden ? Icons.visibility_off : Icons.visibility, size: 20, color: const Color(0xFF9CA3AF))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 80, child: Text('门禁 MAC', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
          Expanded(child: Text(_paramsHidden ? _maskedMac : (lock?.mac ?? '—'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827), fontFamily: 'monospace'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 80, child: Text('门禁 Key', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))),
          Expanded(child: Text(_paramsHidden ? _maskedKey : (lock?.productKey ?? '—'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827), fontFamily: 'monospace'))),
        ]),
      ]),
    );
  }

  Widget _buildUnlockButton() {
    return Center(
      child: SizedBox(
        width: 240, height: 52,
        child: ElevatedButton(
          onPressed: _isUnlocking ? null : _unlock,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), elevation: 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_isUnlocking) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            else const Icon(Icons.lock, size: 20),
            const SizedBox(width: 10),
            Text(_isUnlocking ? '执行中...' : '立即开锁', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    Color bgColor, dotColor, textColor;
    switch (_statusType) {
      case 'unlocking':
        bgColor = const Color(0xFFEFF6FF);
        dotColor = const Color(0xFF3B82F6);
        textColor = const Color(0xFF2563EB);
        break;
      case 'success':
        bgColor = const Color(0xFFECFDF5);
        dotColor = const Color(0xFF10B981);
        textColor = const Color(0xFF059669);
        break;
      case 'cancelled':
        bgColor = const Color(0xFFECFDF5);
        dotColor = const Color(0xFF10B981);
        textColor = const Color(0xFF059669);
        break;
      case 'error':
        bgColor = const Color(0xFFFEF2F2);
        dotColor = const Color(0xFFEF4444);
        textColor = const Color(0xFFDC2626);
        break;
      default:
        bgColor = const Color(0xFFF3F4F6);
        dotColor = const Color(0xFF9CA3AF);
        textColor = const Color(0xFF6B7280);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Text(_statusText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
      ]),
    );
  }

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}
