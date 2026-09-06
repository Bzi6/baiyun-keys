import 'dart:convert';
import 'package:http/http.dart' as http;

/// 平安白云 API 服务
class ApiService {
  static const String baseUrl = 'https://www.pinganbaiyun.cn';
  static const String newBaseUrl = 'https://xcx.pinganbaiyun.cn';

  /// 模拟微信小程序 User-Agent
  static const String miniProgramUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
      'MicroMessenger/8.0.76(0x18004c37) NetType/4G Language/zh_CN';

  /// ========== 旧接口（已停用，保留备用）==========

  static Future<Map<String, String>> login(String phone, String idcardNo) async {
    final payload = {
      'phone': phone,
      'idcardNo': idcardNo,
      'sex': 0,
      'deviceInfo': {
        'osVersion': '26.0',
        'wifiMac': '02:00:00:00:00:00',
        'brand': 'Apple',
        'os': 0,
        'udid': '2E382B94-EE0D-4918-9B9D-DDBE42E3E429',
        'appVersion': '1.3.6',
        'imsi': '46015',
        'model': 'iPhone15,3',
      },
      'faceUploadCount': 0,
      'isreal': 0,
      'age': 0,
      'appVersion': '1.3.6',
    };

    final response = await http.post(
      Uri.parse('$baseUrl/baiyunuser/account/login/v1'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': miniProgramUA,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('网络错误: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data['code'] != '0000') {
      throw Exception(data['msg'] ?? '登录失败');
    }

    final token = data['extension']?.toString() ?? '';
    final obj = data['obj'];
    String loginUser = '';
    if (obj is Map && obj['id'] != null) {
      loginUser = obj['id'].toString();
    }

    if (token.isEmpty || loginUser.isEmpty) {
      throw Exception('登录返回数据缺失');
    }

    return {'token': token, 'loginUser': loginUser};
  }

  static Future<List<dynamic>> fetchEntranceGuardList(String token, String loginUser) async {
    final response = await http.post(
      Uri.parse('$baseUrl/baiyunuser/entranceguard/getList'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': miniProgramUA,
        'TOKEN': token,
        'LOGIN_USER': loginUser,
      },
      body: jsonEncode({'pageNum': 0, 'pages': 0, 'pageSize': 0}),
    );

    if (response.statusCode != 200) {
      throw Exception('网络错误: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data['obj'] is List && (data['obj'] as List).isNotEmpty) {
      return data['obj'] as List<dynamic>;
    }
    throw Exception('未获取到门禁信息');
  }

  /// ========== 新接口（通过抓包的 token 和加密 key 获取）==========

  /// 新接口：通过 cloud_shield_token 和加密 key 获取门禁列表
  static Future<List<dynamic>> fetchGuardListNewApi(String cloudShieldToken, String encryptedKey) async {
    if (cloudShieldToken.trim().isEmpty || encryptedKey.trim().isEmpty) {
      throw Exception('请先在高级设置中填写 cloud_shield_token 和加密 key');
    }

    final response = await http.post(
      Uri.parse('$newBaseUrl/p_021_health_passport/api_007_wbyw_002/get_guard_list_by_phone'),
      headers: {
        'Content-Type': 'application/json',
        'cloud_shield_token': cloudShieldToken.trim(),
        'User-Agent': miniProgramUA,
        'Referer': 'https://servicewechat.com/wx7966fab772d83beb/1324/page-frame.html',
      },
      body: jsonEncode({'key': encryptedKey.trim()}),
    );

    if (response.statusCode != 200) {
      throw Exception('网络错误: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);

    // 响应是数组，取第一个元素的 data_list
    if (data is List && data.isNotEmpty) {
      final first = data[0];
      if (first is Map && first['data_list'] is List && (first['data_list'] as List).isNotEmpty) {
        return first['data_list'] as List<dynamic>;
      }
    }

    // 也可能直接是对象
    if (data is Map && data['data_list'] is List && (data['data_list'] as List).isNotEmpty) {
      return data['data_list'] as List<dynamic>;
    }

    throw Exception('未获取到门禁信息，请检查 cloud_shield_token 和加密 key 是否正确');
  }

  /// 从蓝牙名称推导 MAC 地址
  /// bluetoothName 格式: BY + MAC后9位（去掉冒号）
  /// macPrefix: MAC前3位字符（如 "3E5"）
  static String deriveMacFromBluetoothName(String bluetoothName, String macPrefix) {
    final clean = bluetoothName.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (clean.length < 11) return '';
    // BY 后面是 9 位 MAC 后缀
    final macSuffix = clean.substring(2, 11);
    final fullMac = macPrefix.toUpperCase() + macSuffix;
    if (fullMac.length != 12) return '';
    // 格式化为 AA:BB:CC:DD:EE:FF
    return '${fullMac.substring(0, 2)}:${fullMac.substring(2, 4)}:${fullMac.substring(4, 6)}:${fullMac.substring(6, 8)}:${fullMac.substring(8, 10)}:${fullMac.substring(10, 12)}';
  }
}
