// 全局变量
import 'dart:io';
import 'package:path/path.dart' as p;

/// 配置项
class Config {
  // baseUrl
  static String baseUrl = 'https://api.deepseek.com';

  // 模型供应商
  static String provider = 'deepseek';

  // apiKey
  static String apiKey = '';

  // 模型名称
  static String model = 'deepseek-v4-flash';

  // 思考强度
  static String reasoningEffort = 'medium';

  // REPL 模式
  static bool repl = true;

  // 调试模式
  static bool debug = false;

  // 端口
  static int port = 9080;

  // 监听地址
  static String host = '0.0.0.0';

  // 认证 token
  static String token = '';

  // 敏感文件阻止列表
  static List<String> blockedFiles = [];

  // 应用程序数据目录
  static String get appDataDir {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      return p.join(home, '.nwagent');
    }
    return p.join(Directory.current.path, '.nwagent');
  }
}
