import 'package:flutter/material.dart';
import '../models/lock_config.dart';
import '../services/lock_protocol.dart';

class ConfigScreen extends StatefulWidget {
  final LockConfig? config;
  const ConfigScreen({super.key, this.config});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _doorNameController;
  late TextEditingController _macController;
  late TextEditingController _bluetoothNameController;
  late TextEditingController _productKeyController;
  late TextEditingController _unlockKeyController;

  @override
  void initState() {
    super.initState();
    _doorNameController = TextEditingController(text: widget.config?.doorName ?? '');
    _macController = TextEditingController(text: widget.config?.mac ?? '');
    _bluetoothNameController = TextEditingController(text: widget.config?.bluetoothName ?? '');
    _productKeyController = TextEditingController(text: widget.config?.productKey ?? '');
    _unlockKeyController = TextEditingController(text: widget.config?.unlockKey ?? '');
  }

  @override
  void dispose() {
    _doorNameController.dispose();
    _macController.dispose();
    _bluetoothNameController.dispose();
    _productKeyController.dispose();
    _unlockKeyController.dispose();
    super.dispose();
  }

  void _autoFillBluetoothName() {
    final mac = _macController.text.trim();
    if (LockProtocol.isValidMac(mac)) {
      final derived = LockProtocol.deriveBluetoothNameFromMac(mac);
      if (derived.isNotEmpty) {
        setState(() {
          _bluetoothNameController.text = derived;
        });
      }
    }
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final config = LockConfig(
        doorName: _doorNameController.text.trim(),
        mac: _macController.text.trim().toUpperCase(),
        bluetoothName: _bluetoothNameController.text.trim().toUpperCase(),
        productKey: _productKeyController.text.trim().toUpperCase(),
        unlockKey: _unlockKeyController.text.trim().isEmpty
            ? null
            : _unlockKeyController.text.trim().toUpperCase(),
      );
      Navigator.pop(context, config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config == null ? '添加门禁' : '编辑门禁'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _doorNameController,
              decoration: const InputDecoration(
                labelText: '门禁名称',
                hintText: '例如：家里大门',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.door_front_door),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入门禁名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _macController,
              decoration: InputDecoration(
                labelText: 'MAC 地址',
                hintText: '例如：AA:BB:CC:DD:EE:FF',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.bluetooth),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.auto_fix_high),
                  tooltip: '自动填充蓝牙名称',
                  onPressed: _autoFillBluetoothName,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入 MAC 地址';
                }
                if (!LockProtocol.isValidMac(value.trim())) {
                  return 'MAC 地址格式不正确，应为 AA:BB:CC:DD:EE:FF';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bluetoothNameController,
              decoration: const InputDecoration(
                labelText: '蓝牙名称',
                hintText: '例如：BY123456789',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.bluetooth_searching),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入蓝牙名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _productKeyController,
              decoration: const InputDecoration(
                labelText: '产品密钥 (Product Key)',
                hintText: '16位十六进制',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入产品密钥';
                }
                if (!LockProtocol.isValidKey(value.trim())) {
                  return '密钥格式不正确，应为16-32位十六进制';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _unlockKeyController,
              decoration: const InputDecoration(
                labelText: '开锁密钥 (可选)',
                hintText: '如与产品密钥相同可留空',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  if (!LockProtocol.isValidKey(value.trim())) {
                    return '密钥格式不正确，应为16-32位十六进制';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('配置说明：', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('• MAC 地址：门禁设备的蓝牙 MAC 地址'),
                    const Text('• 蓝牙名称：门禁设备广播的蓝牙名称'),
                    const Text('• 产品密钥：用于加密通信的 16 位密钥'),
                    const Text('• 点击 MAC 输入框右侧图标可自动推导蓝牙名称'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
