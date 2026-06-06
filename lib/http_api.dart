import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nwagent/agents.dart';


/// HTTP API 方法
class HttpApi {
  /// 发送消息给 agent 并获取结果
  ///
  /// [sessionId] 用于保证每次 HTTP 请求时对话一致
  /// [message] 用户的消息
  ///
  /// 返回 JSON 格式：
  /// ```json
  /// {
  ///   "successd": true,
  ///   "msg": "agent 最终回复给用户的消息",
  ///   "summary": ["步骤1", "步骤2", ...]
  /// }
  /// ```
  static Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    required String message,
    String? sessionsDirPath,
  }) async {
    try {
      // 创建会话目录：sessions/<sessionId>/
      final effectiveDirPath = sessionsDirPath ?? p.join(Directory.current.path, 'sessions');
      final sessionsDir = Directory(effectiveDirPath);
      if (!await sessionsDir.exists()) {
        await sessionsDir.create(recursive: true);
      }

      final sessionDir = Directory(p.join(sessionsDir.path, sessionId));
      if (!await sessionDir.exists()) {
        await sessionDir.create(recursive: true);
      }

      final sessionFile = File(p.join(sessionDir.path, 'messages.json'));

      // 初始化 agents
      final agents = Agents();

      // 加载已有会话（如果存在）
      if (await sessionFile.exists()) {
        agents.loadSession(sessionFile);
      }

      // 收集 agent 回复和步骤
      final responseBuffer = StringBuffer();
      final steps = <String>[];

      // 步骤描述的正则：匹配 ANSI 转义码包裹的步骤
      // 格式: ESC[2m  1. 步骤描述ESC[0m
      final stepRegex = RegExp(
        '\\x1B\\[2m\\s*\\d+\\.\\s*(.+?)\\x1B\\[0m',
        dotAll: true,
      );

      // 监听 agent 输出
      await for (final chunk in agents.mainAgent(message)) {
        // 检查是否包含步骤描述
        final stepMatches = stepRegex.allMatches(chunk);
        if (stepMatches.isNotEmpty) {
          for (final match in stepMatches) {
            final stepContent = match.group(1)?.trim();
            if (stepContent != null && stepContent.isNotEmpty) {
              steps.add(stepContent);
            }
          }
        }

        // 移除 ANSI 转义码后的纯文本
        final cleanChunk = chunk
            .replaceAll(RegExp('\\x1B\\[[0-9;]*m'), '')
            .trim();
        if (cleanChunk.isNotEmpty && !stepRegex.hasMatch(chunk)) {
          // 非步骤内容，可能是回复
          responseBuffer.write(cleanChunk);
          responseBuffer.write('\n');
        }
      }

      // 保存会话
      agents.saveSession();

      // 获取最终回复（取最后一段非空内容作为 msg）
      final allText = responseBuffer.toString().trim();
      final msg = allText.isNotEmpty ? allText : '任务已完成';

      return {
        'successd': true,
        'msg': msg,
        'summary': steps,
      };
    } catch (e) {
      return {
        'successd': false,
        'msg': '请求处理失败: $e',
        'summary': <String>[],
      };
    }
  }
}
