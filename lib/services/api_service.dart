import 'dart:convert';
import 'package:http/http.dart' as http;

/// 平安白云 API 服务（含新旧两个接口）
class ApiService {
  // ========== 旧接口：手机号 + 身份证号 ==========
  static const String oldBaseUrl = 'https://www.pinganbaiyun.cn';

  /// 旧接口登录
  static Future<String> loginOld(String phone, String idCard) async {
    final response = await http.post(
      Uri.parse('$oldBaseUrl/baiyunuser/account/login/v1'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'idCard': idCard}),
    );
    if (response.statusCode != 200) {
      throw Exception('登录失败: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['code'] == 200 && data['obj'] != null) {
      final obj = data['obj'];
      if (obj is Map && obj['token'] != null) {
        return obj['token'].toString();
      }
    }
    final msg = data is Map ? (data['msg'] ?? data['message'] ?? '登录失败') : '登录失败';
    throw Exception(msg.toString());
  }

  /// 旧接口获取门禁列表
  static Future<List<dynamic>> fetchGuardListOld(String token) async {
    final response = await http.post(
      Uri.parse('$oldBaseUrl/baiyunuser/entranceguard/getList'),
      headers: {'Content-Type': 'application/json', 'token': token},
      body: jsonEncode({}),
    );
    if (response.statusCode != 200) {
      throw Exception('获取门禁列表失败: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is Map && data['code'] == 200 && data['obj'] is List) {
      return data['obj'] as List<dynamic>;
    }
    final msg = data is Map ? (data['msg'] ?? data['message'] ?? '未获取到门禁信息') : '未获取到门禁信息';
    throw Exception(msg.toString());
  }

  // ========== 新接口：openId + 加密 key（抓包参数） ==========
  static const String newBaseUrl = 'https://xcx.pinganbaiyun.cn';

  static const String miniProgramUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
      'MicroMessenger/8.0.76(0x18004c37) NetType/4G Language/zh_CN';

  /// 通过 openId 获取 access_token
  static Future<String> getAccessToken(String openId) async {
    final response = await http.post(
      Uri.parse('$newBaseUrl/mini_program/api_01/check_state'),
      headers: {'Content-Type': 'application/json', 'User-Agent': miniProgramUA},
      body: jsonEncode({'openId': openId, 'oper_type': 'INDEX'}),
    );
    if (response.statusCode != 200) {
      throw Exception('获取access_token失败: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final first = data[0];
      if (first is Map && first['access_token'] != null) {
        return first['access_token'].toString();
      }
    }
    throw Exception('获取access_token失败，请检查 openId 是否正确');
  }

  /// 通过 openId + access_token 登录
  static Future<Map<String, String>> loginByOpenId(String openId, String accessToken) async {
    final response = await http.post(
      Uri.parse('$newBaseUrl/p_021_health_passport/api_007_wbyw_002/go_home_service_login'),
      headers: {
        'Content-Type': 'application/json',
        'cloud_shield_token': accessToken,
        'User-Agent': miniProgramUA,
      },
      body: jsonEncode({'openId': openId, 'login_token': ''}),
    );
    if (response.statusCode != 200) {
      throw Exception('登录失败: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final first = data[0];
      if (first is Map) {
        return {
          'token': first['token']?.toString() ?? '',
          'name': first['name']?.toString() ?? '',
          'phone': first['phone']?.toString() ?? '',
          'id_card': first['id_card']?.toString() ?? '',
        };
      }
    }
    throw Exception('登录失败，返回数据异常');
  }

  /// 新接口获取门禁列表
  static Future<List<dynamic>> fetchGuardListNewApi(String accessToken, String encryptedKey) async {
    if (accessToken.trim().isEmpty || encryptedKey.trim().isEmpty) {
      throw Exception('请先填写 openId 和加密 key');
    }
    final response = await http.post(
      Uri.parse('$newBaseUrl/p_021_health_passport/api_007_wbyw_002/get_guard_list_by_phone'),
      headers: {
        'Content-Type': 'application/json',
        'cloud_shield_token': accessToken.trim(),
        'User-Agent': miniProgramUA,
        'Referer': 'https://servicewechat.com/wx7966fab772d83beb/1324/page-frame.html',
      },
      body: jsonEncode({'key': encryptedKey.trim()}),
    );
    if (response.statusCode != 200) {
      throw Exception('网络错误: HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is List && data.isNotEmpty) {
      final first = data[0];
      if (first is Map && first['data_list'] is List && (first['data_list'] as List).isNotEmpty) {
        return first['data_list'] as List<dynamic>;
      }
    }
    if (data is Map && data['data_list'] is List && (data['data_list'] as List).isNotEmpty) {
      return data['data_list'] as List<dynamic>;
    }
    throw Exception('未获取到门禁信息，请检查加密 key 是否正确（key每次抓包都会变化，需重新抓取）');
  }

  /// 从蓝牙名称推导 MAC 地址
  static String deriveMacFromBluetoothName(String bluetoothName, String macPrefix) {
    final clean = bluetoothName.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (clean.length < 11) return '';
    final macSuffix = clean.substring(2, 11);
    final fullMac = macPrefix.toUpperCase() + macSuffix;
    if (fullMac.length != 12) return '';
    return '${fullMac.substring(0, 2)}:${fullMac.substring(2, 4)}:${fullMac.substring(4, 6)}:${fullMac.substring(6, 8)}:${fullMac.substring(8, 10)}:${fullMac.substring(10, 12)}';
  }
}
