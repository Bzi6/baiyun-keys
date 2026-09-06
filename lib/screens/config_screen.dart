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

      // 2. 获取门禁列表
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
