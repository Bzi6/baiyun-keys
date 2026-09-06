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
  final BleService _bleService = BleService();
  String _log = '';
  bool _isUnlocking = false;
  int? _unlockingIndex;
  bool _logEnabled = false;

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
      });
    }
  }

  Future<void> _saveLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2FB),
      appBar: AppBar(
        title: const Text('包子的key',
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Switch(
            value: _logEnabled,
            onChanged: _toggleLog,
            activeColor: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
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
        child: Column(
          children: [
            Expanded(
              child: _locks.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.key, size: 64, color: Color(0xFF94A3B8)),
                          SizedBox(height: 16),
                          Text('还没有添加门禁',
                              style: TextStyle(fontSize: 18, color: Color(0xFF64748B))),
                          SizedBox(height: 8),
                          Text('点击右下角按钮添加',
                              style: TextStyle(color: Color(0xFF94A3B8))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _locks.length,
                      itemBuilder: (context, index) {
                        final lock = _locks[index];
                        final isUnlocking = _unlockingIndex == index;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE6EBF1).withOpacity(0.5)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A).withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFECFDF5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.door_front_door,
                                          color: Color(0xFF10B981), size: 22),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        lock.doorName,
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A)),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          size: 20, color: Color(0xFF64748B)),
                                      onPressed: () => _editLock(index),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          size: 20, color: Color(0xFFEF4444)),
                                      onPressed: () => _deleteLock(index),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text('MAC: ${lock.mac}',
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8), fontSize: 12)),
                                const SizedBox(height: 4),
                                Text('蓝牙名称: ${lock.bluetoothName}',
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8), fontSize: 12)),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _isUnlocking
                                        ? null
                                        : () => _unlock(lock, index),
                                    icon: isUnlocking
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.lock_open),
                                    label: Text(isUnlocking ? '开锁中...' : '开锁',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600, fontSize: 15)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
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
            if (_logEnabled && _log.isNotEmpty)
              Container(
                height: 140,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: const Color(0xFF0F172A),
                child: SingleChildScrollView(
                  child: Text(
                    _log,
                    style: const TextStyle(
                        color: Color(0xFF4ADE80), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
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

  @override
  void dispose() {
    _bleService.dispose();
    super.dispose();
  }
}
