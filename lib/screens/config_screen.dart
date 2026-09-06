import 'package:flutter/material.dart';
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

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _idcardController = TextEditingController();
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
  }

  @override
  void dispose() {
    _doorNameController.dispose();
    _macController.dispose();
    _bluetoothNameController.dispose();
    _productKeyController.dispose();
    _unlockKeyController.dispose();
    _phoneController.dispose();
    _idcardController.dispose();
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
    final phone = _phoneController.text.trim();
    final idcard = _idcardController.text.trim().toUpperCase();

    if (phone.isEmpty || idcard.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入手机号和身份证号')),
      );
      return;
    }

    setState(() {
      _fetching = true;
    });

    try {
      // 1. 登录
      final auth = await ApiService.login(phone, idcard);

      // 2. 获取门禁列表（方法名是 fetchEntranceGuardList）
      final list = await ApiService.fetchEntranceGuardList(
        auth['token']!,
        auth['loginUser']!,
      );

      if (list.isEmpty) {
        throw Exception('未获取到门禁信息');
      }

      // 3. 取第一个门禁自动填充（字段映射和小程序一致）
      final item = list[0];
      final name = (item['address'] ?? item['name'] ?? '自动获取门禁').toString().trim();
      final mac = (item['macNum'] ?? '').toString().trim();
      final productKey = (item['productKey'] ?? '').toString().trim();
      final bluetoothName = (item['bluetoothName'] ?? '').toString().trim();

      if (mac.isEmpty || productKey.isEmpty) {
        throw Exception('返回的门锁参数不完整');
      }

      setState(() {
        _doorNameController.text = name;
        _macController.text = mac.toUpperCase();
        _bluetoothNameController.text = bluetoothName.isNotEmpty
            ? bluetoothName.toUpperCase()
            : LockProtocol.deriveBluetoothNameFromMac(mac);
        _productKeyController.text = productKey.toUpperCase();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功获取 ${list.length} 个门禁，已填充第一个')),
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
                  _buildInput(
                    controller: _phoneController,
                    label: '手机号',
                    hint: '请输入绑定手机号',
                  ),
                  const SizedBox(height: 16),
                  _buildInput(
                    controller: _idcardController,
                    label: '身份证号',
                    hint: '请输入身份证号码',
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
                      '1.本功能仅调用官方接口获取数据，不含任何后门，也不会将个人身份信息保存在本地；\n2.门禁参数仅保存在当前设备，建议成功获取后立即复制备份；\n3.本功能会为你自动填充门禁配置。',
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
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('请在首页右上角菜单使用备份功能')),
                              );
                            },
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
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('请在首页右上角菜单使用恢复功能')),
                              );
                            },
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
