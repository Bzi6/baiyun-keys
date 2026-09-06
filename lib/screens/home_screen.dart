import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLocks();
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
      appBar: AppBar(
        title: const Text('包子的key'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: _locks.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.key, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('还没有添加门禁', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        SizedBox(height: 8),
                        Text('点击右下角按钮添加', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _locks.length,
                    itemBuilder: (context, index) {
                      final lock = _locks[index];
                      final isUnlocking = _unlockingIndex == index;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.door_front_door, color: Colors.teal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      lock.doorName,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _editLock(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                    onPressed: () => _deleteLock(index),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('MAC: ${lock.mac}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text('蓝牙名称: ${lock.bluetoothName}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isUnlocking ? null : () => _unlock(lock, index),
                                  icon: isUnlocking
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.lock_open),
                                  label: Text(isUnlocking ? '开锁中...' : '开锁'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
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
          if (_log.isNotEmpty)
            Container(
              height: 120,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.grey[900],
              child: SingleChildScrollView(
                child: Text(
                  _log,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLock,
        tooltip: '添加门禁',
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
