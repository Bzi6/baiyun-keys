import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lock_config.dart';
import '../services/api_service.dart';
import '../services/lock_protocol.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  List<LockConfig> _locks = [];
  int _selectedIndex = 0;
  bool _selectorOpen = false;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _doorNameController;
  late TextEditingController _macController;
  late TextEditingController _bluetoothNameController;
  late TextEditingController _productKeyController;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _idCardController = TextEditingController();
  final TextEditingController _openIdController = TextEditingController();
  bool _advancedOpen = false;
  bool _fetchingRemote = false;

  final TextEditingController _importTextController = TextEditingController();
  List<Map<String, dynamic>> _backupItems = [];
  List<bool> _backupChecked = [];

  @override
  void initState() {
    super.initState();
    _doorNameController = TextEditingController();
    _macController = TextEditingController();
    _bluetoothNameController = TextEditingController();
    _productKeyController = TextEditingController();
    _loadLocks();
    _loadOpenId();
  }

  Future<void> _loadLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    if (locksJson != null) {
      final List<dynamic> list = jsonDecode(locksJson);
      setState(() {
        _locks = list.map((e) => LockConfig.fromJson(e)).toList();
        if (_selectedIndex >= _locks.length) _selectedIndex = 0;
        _fillForm();
      });
    }
  }

  Future<void> _loadOpenId() async {
    final prefs = await SharedPreferences.getInstance();
    final openId = prefs.getString('custom_openid') ?? '';
    setState(() => _openIdController.text = openId);
  }

  Future<void> _saveOpenId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_openid', _openIdController.text.trim());
  }

  void _fillForm() {
    if (_locks.isEmpty || _selectedIndex >= _locks.length) {
      _doorNameController.clear();
      _macController.clear();
      _bluetoothNameController.clear();
      _productKeyController.clear();
      return;
    }
    final lock = _locks[_selectedIndex];
    _doorNameController.text = lock.doorName;
    _macController.text = lock.mac;
    _bluetoothNameController.text = lock.bluetoothName;
    _productKeyController.text = lock.productKey;
  }

  Future<void> _saveLocks() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));
  }

  void _selectLock(int index) {
    setState(() {
      _selectedIndex = index;
      _selectorOpen = false;
      _fillForm();
    });
  }

  void _addNewLock() {
    setState(() {
      _doorNameController.clear();
      _macController.clear();
      _bluetoothNameController.clear();
      _productKeyController.clear();
      _selectorOpen = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已创建新门禁，请填写参数')));
  }

  void _deleteLock() {
    if (_locks.isEmpty || _selectedIndex >= _locks.length) return;
    final lock = _locks[_selectedIndex];
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
                if (_selectedIndex >= _locks.length) _selectedIndex = _locks.length - 1;
                if (_locks.isEmpty) _selectedIndex = 0;
                _fillForm();
              });
              _saveLocks();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _saveConfig() {
    if (!_formKey.currentState!.validate()) return;

    final config = LockConfig(
      doorName: _doorNameController.text.trim(),
      mac: _macController.text.trim().toUpperCase(),
      bluetoothName: _bluetoothNameController.text.trim().toUpperCase(),
      productKey: _productKeyController.text.trim().toUpperCase(),
      unlockKey: null,
    );

    if (_locks.isNotEmpty && _selectedIndex < _locks.length) {
      setState(() => _locks[_selectedIndex] = config);
    } else {
      setState(() {
        _locks.add(config);
        _selectedIndex = _locks.length - 1;
      });
    }
    _saveLocks();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
  }

  // ========== 自动获取配置（新接口优先，支持自定义 openId） ==========
  Future<void> _fetchRemoteConfig() async {
    if (_fetchingRemote) return;

    final phone = _phoneController.text.trim();
    final idCard = _idCardController.text.trim().toUpperCase();
    final customOpenId = _openIdController.text.trim();

    if (phone.isEmpty || phone.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入正确的手机号')));
      return;
    }

    // 保存自定义 openId
    await _saveOpenId();

    setState(() => _fetchingRemote = true);

    try {
      List<Map<String, dynamic>> list = [];

      // 优先使用新接口（只需手机号，全自动）
      try {
        final result = await ApiService.fetchConfigByPhone(phone, customOpenId.isEmpty ? null : customOpenId);
        list = List<Map<String, dynamic>>.from(result['guardList'] ?? []);
      } catch (newApiErr) {
        final errMsg = newApiErr.toString();
        // 如果是手机号相关错误，直接提示，不回退旧接口
        if (errMsg.contains('未在平安白云') || errMsg.contains('参数异常') ||
            errMsg.contains('未找到') || errMsg.contains('手机号')) {
          throw Exception('新接口：$errMsg');
        }
        // 其他错误（网络/token等），回退到旧接口（需要身份证）
        if (idCard.isEmpty) {
          throw Exception('新接口失败（$errMsg），旧接口需要身份证号，请填写身份证号后重试');
        }
        final auth = await ApiService.loginOld(phone, idCard);
        list = await ApiService.fetchGuardListOld(auth);
      }

      if (list.isEmpty) {
        throw Exception('未获取到门禁信息');
      }

      // 解析门禁配置并保存
      int imported = 0;
      for (final item in list) {
        try {
          final name = (item['name'] ?? item['address'] ?? item['doorName'] ?? '自动获取门禁').toString().trim();
          final bluetoothName = (item['bluetoothName'] ?? '').toString().trim();
          final productKey = (item['productKey'] ?? item['key'] ?? '').toString().trim();

          String mac = (item['macNum'] ?? item['mac'] ?? '').toString().trim();
          if (mac.isEmpty && bluetoothName.isNotEmpty) {
            mac = ApiService.deriveMacFromBluetoothName(bluetoothName, '3E5');
          }

          if (mac.isEmpty || productKey.isEmpty) continue;

          final config = LockConfig(
            doorName: name,
            mac: mac.toUpperCase(),
            bluetoothName: bluetoothName.isNotEmpty ? bluetoothName.toUpperCase() : LockProtocol.deriveBluetoothNameFromMac(mac),
            productKey: productKey.toUpperCase(),
            unlockKey: null,
          );

          final exists = _locks.any((e) => e.mac == config.mac && e.productKey == config.productKey);
          if (!exists) {
            setState(() => _locks.add(config));
            imported++;
          }
        } catch (e) {
          continue;
        }
      }

      await _saveLocks();

      if (imported > 0) {
        setState(() {
          _selectedIndex = _locks.length - imported;
          _fillForm();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取成功！新增 $imported 个门禁，已自动选中')));
      } else {
        if (_locks.isNotEmpty) {
          setState(() {
            _selectedIndex = 0;
            _fillForm();
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取成功！门禁已存在，已自动选中')));
      }
    } catch (e) {
      final message = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $message'), duration: const Duration(seconds: 5)));
    } finally {
      if (mounted) setState(() => _fetchingRemote = false);
    }
  }

  // ========== 备份/恢复 ==========
  String _buildCopyPayload(Map<String, dynamic> config) {
    final name = (config['doorName'] ?? '').toString().trim();
    final mac = (config['mac'] ?? '').toString().trim();
    final key = (config['productKey'] ?? '').toString().trim();
    final bluetoothName = (config['bluetoothName'] ?? '').toString().trim();
    final lines = ['门禁名称：${name.isEmpty ? '未命名' : name}', 'MAC：${mac.isEmpty ? '缺失' : mac}', 'Key：${key.isEmpty ? '缺失' : key}'];
    if (bluetoothName.isNotEmpty) lines.add('蓝牙名称：$bluetoothName');
    return lines.join('\n');
  }

  String _buildCopyPayloadList(List<Map<String, dynamic>> configs) {
    if (configs.isEmpty) return '';
    if (configs.length == 1) return _buildCopyPayload(configs[0]);
    return configs.asMap().entries.map((e) => '【门禁 ${e.key + 1}】\n${_buildCopyPayload(e.value)}').join('\n\n');
  }

  Future<void> _showBackupDialog() async {
    if (_locks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可复制门禁，请先保存配置')));
      return;
    }
    _backupItems = _locks.map((e) => e.toJson()).toList();
    _backupChecked = List<bool>.filled(_backupItems.length, true);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择要备份的门禁'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: () {
                  final allChecked = _backupChecked.every((e) => e);
                  setDialogState(() => _backupChecked = List<bool>.filled(_backupItems.length, !allChecked));
                },
                child: Text(_backupChecked.every((e) => e) ? '取消全选' : '全选'),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _backupItems.length,
                  itemBuilder: (context, index) {
                    final item = _backupItems[index];
                    return CheckboxListTile(
                      title: Text(item['doorName']?.toString() ?? '门禁 ${index + 1}', style: const TextStyle(fontSize: 14)),
                      subtitle: Text(item['mac']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      value: _backupChecked[index],
                      onChanged: (value) => setDialogState(() => _backupChecked[index] = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final selected = <Map<String, dynamic>>[];
                for (var i = 0; i < _backupItems.length; i++) {
                  if (_backupChecked[i]) selected.add(_backupItems[i]);
                }
                if (selected.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先勾选门禁')));
                  return;
                }
                final copyText = _buildCopyPayloadList(selected);
                await Clipboard.setData(ClipboardData(text: copyText));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 ${selected.length} 套门禁到剪贴板')));
              },
              child: const Text('复制'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportDialog() async {
    _importTextController.text = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴备份内容'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('将之前复制的备份内容粘贴到下方：', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _importTextController,
              maxLines: 8,
              decoration: const InputDecoration(hintText: '门禁名称：xxx\nMAC：xxx\nKey：xxx', border: OutlineInputBorder(), isDense: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final text = _importTextController.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请粘贴备份内容')));
                return;
              }
              Navigator.pop(context);
              await _doImport(text);
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _doImport(String text) async {
    try {
      final doors = _parseBackupDoors(text);
      if (doors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未识别到有效的门禁配置')));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString('locks');
      List<dynamic> existing = existingJson != null ? jsonDecode(existingJson) : [];
      int added = 0;
      int skipped = 0;
      for (final door in doors) {
        final mac = door['mac']?.toString() ?? '';
        final exists = existing.any((e) => (e['mac']?.toString() ?? '') == mac && mac.isNotEmpty);
        if (!exists) {
          existing.add(door);
          added++;
        } else {
          skipped++;
        }
      }
      await prefs.setString('locks', jsonEncode(existing));
      await _loadLocks();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复成功：新增 $added 个门禁（跳过 $skipped 个重复）')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  List<Map<String, dynamic>> _parseBackupDoors(String text) {
    final doors = <Map<String, dynamic>>[];
    final lines = text.split('\n');
    Map<String, dynamic>? current;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^【门禁\s*\d+】$').hasMatch(trimmed)) {
        if (current != null && (current['mac']?.toString().isNotEmpty ?? false)) doors.add(current);
        current = {};
        continue;
      }
      if (current == null) current = {};
      if (trimmed.contains('：')) {
        final parts = trimmed.split('：');
        final key = parts[0].trim();
        final value = parts.sublist(1).join('：').trim();
        if (key.contains('蓝牙') || key.contains('bluetoothName')) {
          current['bluetoothName'] = value.toUpperCase();
        } else if (key.contains('名称') || key == 'doorName') {
          current['doorName'] = value;
        } else if (key.toUpperCase() == 'MAC' || key.contains('MAC')) {
          current['mac'] = value.toUpperCase();
        } else if (key.toUpperCase() == 'KEY' || key.contains('密钥') || key.contains('productKey')) {
          current['productKey'] = value.toUpperCase();
        }
      }
    }
    if (current != null && (current['mac']?.toString().isNotEmpty ?? false)) doors.add(current);
    return doors;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('参数配置', style: TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('蓝牙门禁参数', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
            const SizedBox(height: 16),
            _buildDoorSelector(),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(children: [
                _buildTextField('门禁名称', _doorNameController, '请输入门禁名称', Icons.door_front_door),
                _buildTextField('门禁 MAC (macNum)', _macController, '例如：3E:52:EB:90:17:E9', Icons.bluetooth, validator: (v) => v!.isEmpty ? '请输入MAC地址' : null),
                _buildTextField('蓝牙名称', _bluetoothNameController, '例如：BY2EB9017E9', Icons.devices),
                _buildTextField('门禁 Key (productKey)', _productKeyController, '例如：e34270efeaf8480d', Icons.vpn_key, validator: (v) => v!.isEmpty ? '请输入产品密钥' : null),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _showBackupDialog, icon: const Icon(Icons.copy, size: 18), label: const Text('一键复制'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2563EB), side: const BorderSide(color: Color(0xFFC8DCFF)), padding: const EdgeInsets.symmetric(vertical: 12)))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(onPressed: _showImportDialog, icon: const Icon(Icons.paste, size: 18), label: const Text('一键导入'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF10B981), side: const BorderSide(color: Color(0xFFBCEFD4)), padding: const EdgeInsets.symmetric(vertical: 12)))),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saveConfig, icon: const Icon(Icons.save, size: 18), label: const Text('保存配置'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
          ])),
          const SizedBox(height: 12),
          _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('自动获取配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
            const SizedBox(height: 8),
            const Text('优先使用新接口（只需手机号），失败时自动回退旧接口（需身份证）', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            _buildTextField('手机号', _phoneController, '请输入手机号', Icons.phone, keyboardType: TextInputType.phone),
            _buildTextField('身份证号（可选，旧接口用）', _idCardController, '请输入身份证号', Icons.credit_card),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE6EBF1))),
                child: Row(children: [
                  const Icon(Icons.settings, size: 18, color: Color(0xFF7B8796)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('高级设置（自定义 openId）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF253041)))),
                  Icon(_advancedOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: const Color(0xFF9AA5B3)),
                ]),
              ),
            ),
            if (_advancedOpen) ...[
              const SizedBox(height: 12),
              _buildTextField('openId（默认失效时填写）', _openIdController, '例如：o7fwU0bbq8M3IrfJMxIy2XwefFZM', Icons.person),
              const SizedBox(height: 8),
              const Text('获取方法：用 Stream 抓包"平安白云"小程序，找到 check_state 请求，请求体里的 openId 就是', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _fetchingRemote ? null : _fetchRemoteConfig, icon: _fetchingRemote ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_download, size: 18), label: Text(_fetchingRemote ? '获取中...' : '获取配置'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          ])),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: child);
  }

  Widget _buildDoorSelector() {
    return Column(children: [
      Row(children: [
        Expanded(child: GestureDetector(onTap: () => setState(() => _selectorOpen = !_selectorOpen), child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(12)), child: Row(children: [Expanded(child: Text(_locks.isNotEmpty && _selectedIndex < _locks.length ? _locks[_selectedIndex].doorName : '请选择门禁', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _locks.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF111827), overflow: TextOverflow.ellipsis))), Icon(_selectorOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 22, color: const Color(0xFF9CA3AF))])))),
        const SizedBox(width: 10),
        SizedBox(width: 90, child: OutlinedButton(onPressed: _deleteLock, style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFEF4444), backgroundColor: const Color(0xFFFEF2F2), side: const BorderSide(color: Color(0xFFFECACA)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('删除', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)))),
      ]),
      if (_selectorOpen) ...[
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFF8FBFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE6EBF1))), child: Column(children: _buildSelectorItems())),
      ],
    ]);
  }

  List<Widget> _buildSelectorItems() {
    final items = <Widget>[];
    for (var i = 0; i < _locks.length; i++) {
      final isActive = i == _selectedIndex;
      items.add(GestureDetector(
        onTap: () => _selectLock(i),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: isActive ? const Color(0xFFEFF6FF) : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isActive ? const Color(0xFFBFDBFE) : Colors.transparent)),
          child: Row(children: [
            Expanded(child: Text(_locks[i].doorName, style: TextStyle(fontSize: 14, color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFF6B7280), overflow: TextOverflow.ellipsis))),
            if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(12)), child: const Text('当前', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
          ]),
        ),
      ));
    }
    items.add(GestureDetector(
      onTap: _addNewLock,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBBF7D0))),
        child: const Row(children: [
          Icon(Icons.add, size: 18, color: Color(0xFF16A34A)),
          SizedBox(width: 8),
          Text('新增门禁', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
        ]),
      ),
    ));
    return items;
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, IconData icon, {String? Function(String?)? validator, TextInputType? keyboardType}) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF7B8796))),
      const SizedBox(height: 6),
      TextFormField(controller: controller, keyboardType: keyboardType, validator: validator, decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFFB0BAC7), fontSize: 13), prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9AA5B3)), filled: true, fillColor: const Color(0xFFFBFDFF), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE6EBF1))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE6EBF1))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB))))),
    ]));
  }

  @override
  void dispose() {
    _doorNameController.dispose();
    _macController.dispose();
    _bluetoothNameController.dispose();
    _productKeyController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    _openIdController.dispose();
    _importTextController.dispose();
    super.dispose();
  }
}
