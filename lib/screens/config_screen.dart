import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lock_config.dart';
import '../services/api_service.dart';
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

  // 方式一：手机号 + 身份证
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _idCardController = TextEditingController();
  bool _fetchingOld = false;

  // 方式二：抓包参数
  final TextEditingController _openIdController = TextEditingController();
  final TextEditingController _encryptedKeyController = TextEditingController();
  final TextEditingController _macPrefixController = TextEditingController(text: '3E5');
  bool _advancedOpen = false;
  bool _fetchingNew = false;

  // 备份选择
  List<Map<String, dynamic>> _backupItems = [];
  List<bool> _backupChecked = [];

  // 导入输入
  final TextEditingController _importTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _doorNameController = TextEditingController(text: widget.config?.doorName ?? '');
    _macController = TextEditingController(text: widget.config?.mac ?? '');
    _bluetoothNameController = TextEditingController(text: widget.config?.bluetoothName ?? '');
    _productKeyController = TextEditingController(text: widget.config?.productKey ?? '');
    _unlockKeyController = TextEditingController(text: widget.config?.unlockKey ?? '');
    _loadAdvancedSettings();
  }

  Future<void> _loadAdvancedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _openIdController.text = prefs.getString('adv_openId') ?? '';
      _encryptedKeyController.text = prefs.getString('adv_encryptedKey') ?? '';
      _macPrefixController.text = prefs.getString('adv_macPrefix') ?? '3E5';
    });
  }

  Future<void> _saveAdvancedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adv_openId', _openIdController.text.trim());
    await prefs.setString('adv_encryptedKey', _encryptedKeyController.text.trim());
    await prefs.setString('adv_macPrefix', _macPrefixController.text.trim());
  }

  // ========== 方式一：旧接口（手机号 + 身份证） ==========
  Future<void> _fetchRemoteConfigOld() async {
    final phone = _phoneController.text.trim();
    final idCard = _idCardController.text.trim().toUpperCase();

    if (phone.isEmpty || phone.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入正确的手机号')));
      return;
    }
    if (idCard.isEmpty || idCard.length < 15) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入正确的身份证号')));
      return;
    }

    setState(() => _fetchingOld = true);
    try {
      final auth = await ApiService.loginOld(phone, idCard);
      final list = await ApiService.fetchGuardListOld(auth);
      if (list.isEmpty) throw Exception('未获取到门禁信息（该账号可能没有门禁，或旧接口已停用）');

      final item = list[0];
      final name = (item['doorName'] ?? item['name'] ?? item['address'] ?? '自动获取门禁').toString().trim();
      final mac = (item['macNum'] ?? item['mac'] ?? '').toString().trim();
      final productKey = (item['productKey'] ?? item['key'] ?? '').toString().trim();
      final bluetoothName = (item['bluetoothName'] ?? '').toString().trim();

      if (mac.isEmpty || productKey.isEmpty) throw Exception('返回的门锁参数不完整');

      setState(() {
        _doorNameController.text = name;
        _macController.text = mac.toUpperCase();
        _bluetoothNameController.text = bluetoothName.isNotEmpty ? bluetoothName.toUpperCase() : LockProtocol.deriveBluetoothNameFromMac(mac);
        _productKeyController.text = productKey.toUpperCase();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功获取 ${list.length} 个门禁，已填充第一个')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _fetchingOld = false);
    }
  }

  // ========== 方式二：新接口（抓包参数） ==========
  Future<void> _fetchRemoteConfigNew() async {
    final openId = _openIdController.text.trim();
    final encryptedKey = _encryptedKeyController.text.trim();
    final macPrefix = _macPrefixController.text.trim();

    if (openId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在高级设置中填写 openId')));
      return;
    }
    if (encryptedKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写加密 key（每次抓包都会变化，需重新抓取）')));
      return;
    }

    setState(() => _fetchingNew = true);
    try {
      await _saveAdvancedSettings();
      final accessToken = await ApiService.getAccessToken(openId);
      final list = await ApiService.fetchGuardListNewApi(accessToken, encryptedKey);
      if (list.isEmpty) throw Exception('未获取到门禁信息');

      final item = list[0];
      final name = (item['name'] ?? item['address'] ?? '自动获取门禁').toString().trim();
      final bluetoothName = (item['bluetoothName'] ?? '').toString().trim();
      final productKey = (item['productKey'] ?? '').toString().trim();

      if (bluetoothName.isEmpty || productKey.isEmpty) throw Exception('返回的门锁参数不完整');

      final mac = macPrefix.isNotEmpty ? ApiService.deriveMacFromBluetoothName(bluetoothName, macPrefix) : '';

      setState(() {
        _doorNameController.text = name;
        if (mac.isNotEmpty) _macController.text = mac.toUpperCase();
        _bluetoothNameController.text = bluetoothName.toUpperCase();
        _productKeyController.text = productKey.toUpperCase();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('成功获取 ${list.length} 个门禁，已填充第一个')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _fetchingNew = false);
    }
  }

  // ========== 备份与恢复（按小程序源码逻辑） ==========
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
    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    if (locksJson == null || locksJson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可复制门禁，请先保存配置')));
      return;
    }
    final List<dynamic> list = jsonDecode(locksJson);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无可复制门禁，请先保存配置')));
      return;
    }

    _backupItems = list.map((e) => e as Map<String, dynamic>).toList();
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
              decoration: const InputDecoration(
                hintText: '门禁名称：xxx\nMAC：xxx\nKey：xxx',
                border: OutlineInputBorder(),
                isDense: true,
              ),
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

      // 显示导入结果
      final lines = ['成功导入 $added 套门禁'];
      if (skipped > 0) lines.add('已跳过重复：$skipped 套');
      for (var i = 0; i < doors.length && i < 5; i++) {
        lines.add('【门禁 ${i + 1}】${doors[i]['doorName'] ?? '未命名'}');
      }
      if (doors.length > 5) lines.add('...共 ${doors.length} 套');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入结果'),
          content: Text(lines.join('\n'), style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定')),
          ],
        ),
      );
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
        if (current != null && (current['mac']?.toString().isNotEmpty ?? false)) {
          doors.add(current);
        }
        current = {};
        continue;
      }

      if (current == null) current = {};

      if (trimmed.contains('：')) {
        final parts = trimmed.split('：');
        final key = parts[0].trim();
        final value = parts.sublist(1).join('：').trim();

        if (key.contains('名称') || key == 'doorName') {
          current['doorName'] = value;
        } else if (key.toUpperCase() == 'MAC' || key.contains('MAC')) {
          current['mac'] = value.toUpperCase();
        } else if (key.toUpperCase() == 'KEY' || key.contains('密钥') || key.contains('productKey')) {
          current['productKey'] = value.toUpperCase();
        } else if (key.contains('蓝牙') || key.contains('bluetoothName')) {
          current['bluetoothName'] = value.toUpperCase();
        }
      }
    }

    if (current != null && (current['mac']?.toString().isNotEmpty ?? false)) {
      doors.add(current);
    }

    return doors;
  }

  // ========== 保存配置 ==========
  void _saveConfig() {
    if (!_formKey.currentState!.validate()) return;

    final config = LockConfig(
      doorName: _doorNameController.text.trim(),
      mac: _macController.text.trim().toUpperCase(),
      bluetoothName: _bluetoothNameController.text.trim().toUpperCase(),
      productKey: _productKeyController.text.trim().toUpperCase(),
      unlockKey: _unlockKeyController.text.trim().isNotEmpty ? _unlockKeyController.text.trim().toUpperCase() : null,
    );

    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2FB),
      appBar: AppBar(
        title: Text(widget.config == null ? '添加门禁' : '编辑门禁', style: const TextStyle(color: Color(0xFF111827), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDF2FB), Color(0xFFF8FAFC)])),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // 基础配置
            _buildCard(child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('基础配置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                const SizedBox(height: 14),
                _buildTextField('门禁名称', _doorNameController, '例如：营溪营中街126号', Icons.door_front_door),
                _buildTextField('MAC 地址', _macController, '例如：3E:52:EB:90:17:E9', Icons.bluetooth, validator: (v) => v!.isEmpty ? '请输入MAC地址' : null),
                _buildTextField('蓝牙名称', _bluetoothNameController, '例如：BY2EB9017E9', Icons.devices),
                _buildTextField('产品密钥 (productKey)', _productKeyController, '例如：e34270efeaf8480d', Icons.vpn_key, validator: (v) => v!.isEmpty ? '请输入产品密钥' : null),
                _buildTextField('开锁密钥（可选）', _unlockKeyController, '如与产品密钥相同可留空', Icons.key),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(onPressed: _showBackupDialog, icon: const Icon(Icons.copy, size: 18), label: const Text('一键复制'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2563EB), side: const BorderSide(color: Color(0xFFC8DCFF)), padding: const EdgeInsets.symmetric(vertical: 12)))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: _showImportDialog, icon: const Icon(Icons.paste, size: 18), label: const Text('一键导入'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF10B981), side: const BorderSide(color: Color(0xFFBCEFD4)), padding: const EdgeInsets.symmetric(vertical: 12)))),
                ]),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _saveConfig, icon: const Icon(Icons.save, size: 18), label: const Text('保存配置'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
              ]),
            )),
            const SizedBox(height: 12),
            // 方式一：旧接口
            _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('自动获取配置（方式一：手机号+身份证）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
              const SizedBox(height: 12),
              _buildTextField('手机号', _phoneController, '请输入手机号', Icons.phone, keyboardType: TextInputType.phone),
              _buildTextField('身份证号', _idCardController, '请输入身份证号', Icons.credit_card),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _fetchingOld ? null : _fetchRemoteConfigOld,
                icon: _fetchingOld ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_download, size: 18),
                label: Text(_fetchingOld ? '获取中...' : '获取配置'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFE08A))), child: const Text('注意：旧接口可能已部分停用，部分账号可能返回空或被拒绝。如果获取失败，请尝试下方方式二（抓包参数）。', style: TextStyle(fontSize: 11, color: Color(0xFF8A6D00)))),
            ])),
            const SizedBox(height: 12),
            // 方式二：新接口
            _buildCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('自动获取配置（方式二：抓包参数）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _advancedOpen = !_advancedOpen),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE6EBF1))), child: Row(children: [
                  const Icon(Icons.settings, size: 18, color: Color(0xFF7B8796)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('高级设置（抓包参数）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF253041)))),
                  Icon(_advancedOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: const Color(0xFF9AA5B3)),
                ])),
              ),
              if (_advancedOpen) ...[
                const SizedBox(height: 12),
                _buildTextField('openId', _openIdController, '微信小程序的 openId', Icons.person),
                _buildTextField('加密 key（每次抓包都会变化）', _encryptedKeyController, 'RSA加密的key，末尾带RSA_STRTOK@@@', Icons.lock),
                _buildTextField('MAC前缀（默认3E5）', _macPrefixController, '例如：3E5', Icons.tag),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFC8DCFF))), child: const Text('使用方法：用 Stream 抓包平安白云小程序，复制 get_guard_list_by_phone 请求里的 key 字段，以及 check_state 请求里的 openId。注意 key 每次打开小程序都会变化，获取前需重新抓包。', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB)))),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _fetchingNew ? null : _fetchRemoteConfigNew,
                icon: _fetchingNew ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_download, size: 18),
                label: Text(_fetchingNew ? '获取中...' : '获取配置'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ])),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE6EBF1)), boxShadow: [BoxShadow(color: const Color(0xFF1F2937).withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: child,
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, IconData icon, {String? Function(String?)? validator, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF7B8796))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFB0BAC7), fontSize: 13),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9AA5B3)),
            filled: true,
            fillColor: const Color(0xFFFBFDFF),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE6EBF1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE6EBF1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB))),
          ),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _doorNameController.dispose();
    _macController.dispose();
    _bluetoothNameController.dispose();
    _productKeyController.dispose();
    _unlockKeyController.dispose();
    _phoneController.dispose();
    _idCardController.dispose();
    _openIdController.dispose();
    _encryptedKeyController.dispose();
    _macPrefixController.dispose();
    _importTextController.dispose();
    super.dispose();
  }
}
