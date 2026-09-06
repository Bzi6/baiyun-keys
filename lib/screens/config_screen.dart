import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lock_config.dart';
import '../services/lock_protocol.dart';
import '../services/api_service.dart';

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

  final TextEditingController _cloudShieldTokenController = TextEditingController();
  final TextEditingController _encryptedKeyController = TextEditingController();
  final TextEditingController _macPrefixController = TextEditingController(text: '3E5');
  bool _advancedExpanded = false;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _doorNameController =
        TextEditingController(text: widget.config?.doorName ?? '');
    _macController = TextEditingController(text: widget.config?.mac ?? '');
    _bluetoothNameController =
        TextEditingController(text: widget.config?.bluetoothName ?? '');
    _productKeyController =
        TextEditingController(text: widget.config?.productKey ?? '');
    _unlockKeyController =
        TextEditingController(text: widget.config?.unlockKey ?? '');
    _loadAdvancedSettings();
  }

  Future<void> _loadAdvancedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cloudShieldTokenController.text = prefs.getString('cloudShieldToken') ?? '';
      _encryptedKeyController.text = prefs.getString('encryptedKey') ?? '';
      _macPrefixController.text = prefs.getString('macPrefix') ?? '3E5';
    });
  }

  Future<void> _saveAdvancedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloudShieldToken', _cloudShieldTokenController.text.trim());
    await prefs.setString('encryptedKey', _encryptedKeyController.text.trim());
    await prefs.setString('macPrefix', _macPrefixController.text.trim());
  }

  @override
  void dispose() {
    _doorNameController.dispose();
    _macController.dispose();
    _bluetoothNameController.dispose();
    _productKeyController.dispose();
    _unlockKeyController.dispose();
    _cloudShieldTokenController.dispose();
    _encryptedKeyController.dispose();
    _macPrefixController.dispose();
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

  Future<void> _fetchRemoteConfig() async {
    final token = _cloudShieldTokenController.text.trim();
    final key = _encryptedKeyController.text.trim();
    final macPrefix = _macPrefixController.text.trim();

    if (token.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先展开高级设置，填写 cloud_shield_token 和加密 key')),
      );
      setState(() {
        _advancedExpanded = true;
      });
      return;
    }

    if (macPrefix.isEmpty || macPrefix.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MAC前缀必须是3位字符（如 3E5）')),
      );
      return;
    }

    setState(() {
      _fetching = true;
    });

    try {
      await _saveAdvancedSettings();
      final list = await ApiService.fetchGuardListNewApi(token, key);

      if (list.isEmpty) {
        throw Exception('未获取到门禁信息');
      }

      final item = list[0];
      final name = (item['address'] ?? item['name'] ?? '自动获取门禁').toString().trim();
      final productKey = (item['productKey'] ?? '').toString().trim();
      final bluetoothName = (item['bluetoothName'] ?? '').toString().trim();

      if (productKey.isEmpty || bluetoothName.isEmpty) {
        throw Exception('返回的门锁参数不完整');
      }

      final mac = ApiService.deriveMacFromBluetoothName(bluetoothName, macPrefix);

      setState(() {
        _doorNameController.text = name;
        _macController.text = mac;
        _bluetoothNameController.text = bluetoothName.toUpperCase();
        _productKeyController.text = productKey.toUpperCase();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功获取 ${list.length} 个门禁，已填充第一个，MAC: $mac')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _fetching = false;
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

  String _buildBackupText(LockConfig config) {
    final name = config.doorName.trim().isEmpty ? '未命名' : config.doorName.trim();
    final mac = config.mac.trim().isEmpty ? '缺失' : config.mac.trim();
    final key = config.productKey.trim().isEmpty ? '缺失' : config.productKey.trim();
    final bluetoothName = config.bluetoothName.trim();

    final lines = ['门禁名称：$name', 'MAC：$mac', 'Key：$key'];

    final derived = LockProtocol.deriveBluetoothNameFromMac(mac);
    if (bluetoothName.isNotEmpty &&
        derived.isNotEmpty &&
        bluetoothName.toUpperCase() != derived.toUpperCase()) {
      lines.add('蓝牙名称：$bluetoothName');
    }

    return lines.join('\n');
  }

  Future<void> _copyBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    if (locksJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可备份的门禁')),
      );
      return;
    }

    final List<dynamic> list = jsonDecode(locksJson);
    final locks = list.map((e) => LockConfig.fromJson(e as Map<String, dynamic>)).toList();

    if (locks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可备份的门禁')),
      );
      return;
    }

    String backupText;
    if (locks.length == 1) {
      backupText = _buildBackupText(locks[0]);
    } else {
      backupText = locks
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

  Future<void> _importBackup() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('粘贴门禁参数'),
              content: TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '请粘贴一键复制的门禁参数文本',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setDialogState(() {});
                },
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
            );
          },
        );
      },
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

    if (current['mac']!.isNotEmpty && current['key']!.isNotEmpty) {
      blocks.add(Map.from(current));
    }

    if (blocks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未识别到有效门禁参数')),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final locksJson = prefs.getString('locks');
    List<LockConfig> locks = [];
    if (locksJson != null) {
      final List<dynamic> list = jsonDecode(locksJson);
      locks = list.map((e) => LockConfig.fromJson(e as Map<String, dynamic>)).toList();
    }

    var added = 0;
    for (final b in blocks) {
      final mac = b['mac']!.toUpperCase();
      final exists = locks.any((l) => l.mac.toUpperCase() == mac);
      if (exists) continue;

      final bluetoothName = b['bluetoothName']!.isNotEmpty
          ? b['bluetoothName']!.toUpperCase()
          : LockProtocol.deriveBluetoothNameFromMac(mac);

      locks.add(LockConfig(
        doorName: b['doorName']!.isEmpty ? '导入门禁' : b['doorName']!,
        mac: mac,
        bluetoothName: bluetoothName,
        productKey: b['key']!.toUpperCase(),
      ));
      added++;
    }

    final list = locks.map((e) => e.toJson()).toList();
    await prefs.setString('locks', jsonEncode(list));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $added 个门禁')),
      );
    }
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? note,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569)),
            ),
            if (note != null) ...[
              const SizedBox(width: 6),
              Text(
                note,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: suffixIcon,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFE6EBF1).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF2FB),
      appBar: AppBar(
        title: Text(
          widget.config == null ? '添加门禁' : '编辑门禁',
          style: const TextStyle(
              color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
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
            _buildCard(
              title: '蓝牙门禁参数',
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInput(
                      controller: _doorNameController,
                      label: '门禁名称',
                      hint: '如 默认大门',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入门禁名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildInput(
                      controller: _macController,
                      label: '门禁 MAC',
                      note: '(macNum)',
                      hint: 'AA:BB:CC:DD:EE:FF',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.auto_fix_high, size: 20),
                        onPressed: _autoFillBluetoothName,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入 MAC 地址';
                        }
                        if (!LockProtocol.isValidMac(value.trim())) {
                          return 'MAC 格式不正确';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildInput(
                      controller: _bluetoothNameController,
                      label: '蓝牙名称',
                      hint: '如 BY123456789',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入蓝牙名称';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildInput(
                      controller: _productKeyController,
                      label: '门禁 Key',
                      note: '(productKey)',
                      hint: '16~32 位十六进制',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入产品密钥';
                        }
                        if (!LockProtocol.isValidKey(value.trim())) {
                          return '密钥格式不正确';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildInput(
                      controller: _unlockKeyController,
                      label: '开锁密钥',
                      note: '(可选)',
                      hint: '如与产品密钥相同可留空',
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFF93C5FD)),
                                backgroundColor: const Color(0xFFEFF6FF),
                                foregroundColor: const Color(0xFF1D4ED8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('分享门禁',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Text('保存配置',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildCard(
              title: '自动获取配置',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _advancedExpanded = !_advancedExpanded;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.settings,
                                    size: 18, color: Color(0xFF64748B)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '高级设置（抓包参数）',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155)),
                                  ),
                                ),
                                Icon(
                                  _advancedExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_advancedExpanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                const Divider(height: 1),
                                const SizedBox(height: 16),
                                _buildInput(
                                  controller: _cloudShieldTokenController,
                                  label: 'cloud_shield_token',
                                  hint: '从抓包获取，如 xcx.xxx',
                                ),
                                const SizedBox(height: 16),
                                _buildInput(
                                  controller: _encryptedKeyController,
                                  label: '加密 key',
                                  hint: '从抓包获取，请求体里的 key 字段',
                                ),
                                const SizedBox(height: 16),
                                _buildInput(
                                  controller: _macPrefixController,
                                  label: 'MAC 前缀（3位）',
                                  note: '默认 3E5',
                                  hint: '如 3E5',
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFFDE68A)),
                                  ),
                                  child: const Text(
                                    '用 Stream 抓包平安白云小程序，找到 get_guard_list_by_phone 请求，复制请求头里的 cloud_shield_token 和请求体里的 key 填到这里。只需要抓一次，会自动保存。',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF92400E),
                                        height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _fetching ? null : _fetchRemoteConfig,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                        ),
                        child: _fetching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('获取配置',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFFC7D2FE).withOpacity(0.5)),
                    ),
                    child: const Text(
                      '1.本功能仅调用官方接口获取数据，不含任何后门；\n2.门禁参数仅保存在当前设备，建议成功获取后立即复制备份；\n3.需要先在高级设置中填写抓包获取的 token 和 key。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildCard(
              title: '备份/恢复',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _copyBackup,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFFBFDBFE)),
                              backgroundColor: const Color(0xFFF8FBFF),
                              foregroundColor: const Color(0xFF2563EB),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('一键复制',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: _importBackup,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: Color(0xFFBFDBFE)),
                              backgroundColor: const Color(0xFFF8FBFF),
                              foregroundColor: const Color(0xFF2563EB),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('一键导入',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFFC7D2FE).withOpacity(0.5)),
                    ),
                    child: const Text(
                      '一键复制可生成参数文本，建议保存到微信收藏；一键导入可粘贴备份文本恢复门禁配置，不会覆盖已有门禁。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
