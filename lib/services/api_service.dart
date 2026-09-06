import 'dart:convert';
import 'package:http/http.dart' as http;

/// 平安白云 API 服务（对应小程序 utils/api.js）
class ApiService {
  static const String baseUrl = 'https://www.pinganbaiyun.cn';

  /// 模拟微信小程序 User-Agent（必须带，否则接口返回维护提示）
  static const String miniProgramUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
      'MicroMessenger/8.0.40(0x18002824) NetType/WIFI Language/zh_CN miniProgram';

  /// 登录，返回 {token, loginUser}
  static Future<Map<String, String>> login(String phone, String idcardNo) async {
    final payload = {
      'phone': phone,
      'idcardNo': idcardNo,
      'sex': 0,
      'deviceInfo': {
        'osVersion': '17.0',
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
    // 小程序判断登录成功用 code === '0000'
    if (data['code'] != '0000') {
      throw Exception(data['msg'] ?? '登录失败');
    }

    final token = data['extension']?.toString() ?? '';
    // loginUser 在 data.obj.id 里
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

  /// 递归查找门禁列表（对应小程序 collectEntranceGuardItems）
  static List<dynamic> _collectGuardItems(dynamic source) {
    final merged = <dynamic>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map) return;
      if (node['data_list'] is List) {
        merged.addAll(node['data_list']);
      }
      if (node['obj'] != null) {
        walk(node['obj']);
      }
    }
    walk(source);
    return merged;
  }

  /// 获取门禁列表
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

    // 先尝试递归查找 data_list
    final merged = _collectGuardItems(data);
    if (merged.isNotEmpty) return merged;

    // 备选：如果 obj 是数组直接返回
    if (data['obj'] is List) {
      return data['obj'] as List<dynamic>;
    }

    // 备选：如果 code 不是 0000 抛错
    if (data['code'] != null && data['code'] != '0000') {
      throw Exception(data['msg'] ?? '获取门禁列表失败');
    }

    return [];
  }
}
