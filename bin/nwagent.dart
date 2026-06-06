import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:nwagent/logger.dart';
import 'package:nwagent/global.dart';
import 'package:nwagent/agents.dart';
import 'package:nwagent/http_api.dart';
import 'package:uuid/uuid.dart';

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};

Middleware createCorsMiddleware() {
  return createMiddleware(
    requestHandler: (Request request) {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: _corsHeaders);
      }
      return null;
    },
    responseHandler: (Response response) {
      return response.change(headers: _corsHeaders);
    },
  );
}

// 初始化鉴权中间件
Middleware handleAuth({required String token}) {
  return (Handler handler) {
    return (Request request) {
      if (request.method == 'OPTIONS') {
        return handler(request);
      }

      final authHeader = request.headers['authorization'];
      if (authHeader != null && authHeader.startsWith('Bearer ')) {
        final String tokenValue = authHeader.split('Bearer ').last;
        if (tokenValue == token) {
          return handler(request);
        }
      }

      return Response(
        401,
        body: '{"error": "401 Unauthorized!"}',
        headers: {'Content-Type': 'application/json'},
      );
    };
  };
}

// 统一 Log 输出
Middleware customLogRequests() {
  return (Handler innerHandler) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      final response = await innerHandler(request);
      final latency = watch.elapsed;
      Logger.api(
        request.method,
        response.statusCode,
        '${request.url}\t\t${latency.inMilliseconds}ms',
      );
      return response;
    };
  };
}

const _replUserPrompt = 'User > ';
const _replAssistantPrompt = 'Agent > ';
const _replSeparatorChar = '─';
const _escSignal = '__esc__';

// ANSI 颜色
const _red = '\x1B[31m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _dim = '\x1B[2m';
const _bold = '\x1B[1m';
const _reset = '\x1B[0m';

/// 渲染文件修改的 diff 输出
void _renderFileDiff(String path, Map<String, dynamic> result) {
  if (result['success'] != true) return;
  final changes = result['changes'] as List?;
  if (changes == null || changes.isEmpty) return;

  stdout.writeln();
  stdout.writeln('$_bold$_dim--- $path$_reset');

  // 按行号排序
  final sorted = List<Map<String, dynamic>>.from(changes)
    ..sort((a, b) => (a['line'] as int).compareTo(b['line'] as int));

  for (final change in sorted) {
    final line = (change['line'] as int) + 1; // 显示从 1 开始
    final type = change['type'] as String;
    switch (type) {
      case 'delete':
        stdout.writeln(
          '  $_dim$line$_reset $_red- ${change['content']}$_reset',
        );
        break;
      case 'insert':
        stdout.writeln(
          '  $_dim$line$_reset $_green+ ${change['content']}$_reset',
        );
        break;
      case 'replace':
        stdout.writeln(
          '  $_dim$line$_reset $_red- ${change['oldContent']}$_reset',
        );
        stdout.writeln(
          '  $_dim$line$_reset $_green+ ${change['newContent']}$_reset',
        );
        break;
    }
  }

  stdout.writeln();
}

int _replTerminalWidth({int fallback = 80}) {
  if (!stdout.hasTerminal) return fallback;
  final width = stdout.terminalColumns;
  return width < 20 ? 20 : width;
}

String _replSeparator() {
  return _replSeparatorChar * _replTerminalWidth();
}

void _writeReplInputBoundary() {
  stdout.writeln(_replSeparator());
}

String _replContentToString(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;

  try {
    return jsonEncode(content);
  } catch (_) {
    return content.toString();
  }
}

String _spinnerFrame(int tick) {
  const frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  return frames[tick % frames.length];
}

String? _replRoleLabel(String role) {
  switch (role) {
    case 'user':
      return _replUserPrompt;
    case 'assistant':
      return _replAssistantPrompt;
    case 'system':
      return null;
    default:
      return '${role.toUpperCase()} > ';
  }
}

List<String> _wrapReplLine(String text, int maxWidth) {
  final width = maxWidth < 20 ? 20 : maxWidth;
  final runes = text.runes.toList();

  if (runes.isEmpty) return [''];

  final lines = <String>[];
  for (var index = 0; index < runes.length; index += width) {
    final end = index + width > runes.length ? runes.length : index + width;
    lines.add(String.fromCharCodes(runes.sublist(index, end)));
  }
  return lines;
}

String _renderMarkdownForTerminal(String text) {
  if (!stdout.hasTerminal) return text;

  const reset = '\x1B[0m';
  const bold = '\x1B[1m';
  const dim = '\x1B[2m';
  const cyan = '\x1B[36m';
  const yellow = '\x1B[33m';

  var output = text;

  output = output.replaceAllMapped(RegExp(r'```(?:\w+)?\n?([\s\S]*?)```'), (
    match,
  ) {
    final code = match.group(1) ?? '';
    final lines = code.trimRight().split('\n');
    return '\n${lines.map((line) => '$dim  $line$reset').join('\n')}\n';
  });

  output = output.replaceAllMapped(
    RegExp(r'`([^`\n]+)`'),
    (match) => '$yellow${match.group(1)}$reset',
  );

  output = output.replaceAllMapped(
    RegExp(r'\*\*([^*\n]+)\*\*'),
    (match) => '$bold${match.group(1)}$reset',
  );

  output = output.replaceAllMapped(
    RegExp(r'^#{1,6}\s+(.+)$', multiLine: true),
    (match) => '$bold$cyan${match.group(1)}$reset',
  );

  output = output.replaceAllMapped(
    RegExp(r'^\s*[-*]\s+(.+)$', multiLine: true),
    (match) => '• ${match.group(1)}',
  );

  return output;
}

void _writeReplMessage(String role, dynamic content) {
  final label = _replRoleLabel(role);
  if (label == null) return;

  final text = _renderMarkdownForTerminal(
    _replContentToString(content),
  ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final terminalWidth = _replTerminalWidth();
  final indent = ' ' * label.length;
  var isFirstLine = true;

  for (final logicalLine in text.split('\n')) {
    final prefix = isFirstLine ? label : indent;
    final wrappedLines = _wrapReplLine(
      logicalLine,
      terminalWidth - prefix.length,
    );

    for (var index = 0; index < wrappedLines.length; index++) {
      stdout.writeln('${index == 0 ? prefix : indent}${wrappedLines[index]}');
    }

    isFirstLine = false;
  }
}

void _renderReplStatus(String text, {int tick = 0}) {
  if (!stdout.hasTerminal) {
    stdout.writeln('[${_spinnerFrame(tick)}] $text');
    return;
  }

  stdout.write('\r\x1b[2K');
  stdout.write('${_spinnerFrame(tick)} $text');
}

void _clearReplStatusLine() {
  if (!stdout.hasTerminal) return;
  stdout.write('\r\x1b[2K');
}

void _displayReplHistory(Agents agent, Directory sessionDir) {
  final visibleMessages = agent.messages.where((message) {
    return message['role'] != 'system';
  }).toList();

  stdout.writeln('Session: ${p.basename(sessionDir.path)}');

  if (visibleMessages.isEmpty) {
    stdout.writeln('No previous chat history.');
    return;
  }

  // stdout.writeln('Chat history:');
  // stdout.writeln();

  for (final message in visibleMessages) {
    _writeReplMessage(
      message['role'] as String? ?? 'unknown',
      message['content'],
    );
    stdout.writeln();
  }
}

int _utf8SequenceLength(int firstByte) {
  if ((firstByte & 0x80) == 0) return 1;
  if ((firstByte & 0xE0) == 0xC0) return 2;
  if ((firstByte & 0xF0) == 0xE0) return 3;
  if ((firstByte & 0xF8) == 0xF0) return 4;
  return 1;
}

final List<String> _replCommandHistory = [];

Future<String?> readReplLine({
  String prompt = _replUserPrompt,
  bool showBoundary = true,
}) async {
  final input = StringBuffer();
  int historyIndex = _replCommandHistory.length;

  void replaceInput(String text) {
    stdout.write('\r\x1b[2K$prompt$text');
    input.clear();
    input.write(text);
  }

  if (showBoundary) {
    _writeReplInputBoundary();
  }

  stdout.write(prompt);

  // 检查终端是否可用
  bool rawMode = false;
  bool oldLineMode = true;
  bool oldEchoMode = true;

  try {
    oldLineMode = stdin.lineMode;
    oldEchoMode = stdin.echoMode;
    stdin.lineMode = false;
    stdin.echoMode = false;
    rawMode = true;
  } catch (_) {
    // 终端模式设置失败，回退到普通输入
    final line = stdin.readLineSync();
    return line;
  }

  try {
    while (true) {
      final byte = stdin.readByteSync();

      if (byte == -1) return null;

      if (byte == 10 || byte == 13) {
        final value = input.toString();
        if (value.trim().isNotEmpty) {
          if (_replCommandHistory.isEmpty || _replCommandHistory.last != value) {
            _replCommandHistory.add(value);
          }
        }
        if (showBoundary && stdout.hasTerminal) {
          stdout.write('\r\x1b[2K\x1b[1A\r\x1b[2K');
          stdout.writeln('$prompt$value');
        } else {
          stdout.writeln();
        }
        return value;
      }

      if (byte == 3) {
        stdout.writeln();
        return null;
      }

      // ESC → 可能是打断输入，或者是方向键
      if (byte == 27) {
        // 读取下一个字节，如果是 '[' 则可能是方向键
        final next1 = stdin.readByteSync();
        if (next1 == 91) { // '['
          final next2 = stdin.readByteSync();
          if (next2 == 65) { // UP
            if (historyIndex > 0) {
              historyIndex--;
              replaceInput(_replCommandHistory[historyIndex]);
            }
            continue;
          } else if (next2 == 66) { // DOWN
            if (historyIndex < _replCommandHistory.length - 1) {
              historyIndex++;
              replaceInput(_replCommandHistory[historyIndex]);
            } else if (historyIndex == _replCommandHistory.length - 1) {
              historyIndex++;
              replaceInput('');
            }
            continue;
          } else if (next2 == 67 || next2 == 68) {
            // Right / Left (暂不支持光标左右移动，直接忽略)
            continue;
          }
        }
        // 不是方向键，当作 ESC 退出信号
        stdout.writeln();
        return _escSignal;
      }

      if (byte == 127 || byte == 8) {
        if (input.isNotEmpty) {
          final runes = input.toString().runes.toList()..removeLast();
          input
            ..clear()
            ..write(String.fromCharCodes(runes));
          stdout.write('\r\x1b[2K$prompt$input');
        }
        continue;
      }

      if (byte < 32) continue;

      final bytes = [byte];
      while ((bytes.first & 0x80) != 0 &&
          bytes.length < _utf8SequenceLength(bytes.first)) {
        final next = stdin.readByteSync();
        if (next == -1) break;
        bytes.add(next);
      }

      final text = utf8.decode(bytes, allowMalformed: true);
      input.write(text);
      stdout.write(text);
    }
  } finally {
    if (rawMode) {
      try {
        stdin.lineMode = oldLineMode;
        stdin.echoMode = oldEchoMode;
      } catch (_) {}
    }
  }
}

Directory getReplSessionDir({bool createNew = false, String? sessionId}) {
  final sessionsDir = Directory(p.join(Config.appDataDir, 'sessions'));

  if (!sessionsDir.existsSync()) {
    sessionsDir.createSync();
  }

  if (sessionId != null) {
    final dir = Directory(p.join(sessionsDir.path, sessionId));
    if (!dir.existsSync()) {
      dir.createSync();
    }
    return dir;
  }

  if (!createNew) {

  final existingSessions =
      sessionsDir
          .listSync()
          .whereType<Directory>()
          .where((dir) => File(p.join(dir.path, 'messages.json')).existsSync())
          .toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

      if (existingSessions.isNotEmpty) {
        return existingSessions.first;
      }
  }

  final id = Uuid().v4();
  final sessionDir = Directory(p.join(sessionsDir.path, id))..createSync();
  return sessionDir;
}

String _formatParamValue(dynamic value, {int maxLen = 80}) {
  if (value == null) return '$_dim(null)$_reset';
  if (value is String) {
    final display = value.length > maxLen
        ? '${value.substring(0, maxLen)}...'
        : value;
    return '"$_yellow$display$_reset"';
  }
  if (value is num || value is bool) return '$_green$value$_reset';
  if (value is List) return '$_dim[${value.length} items]$_reset';
  if (value is Map) return '$_dim{${value.length} keys}$_reset';
  return value.toString();
}

Future<TaskApprovalDecision> _promptTaskApproval(
  String ability,
  Map<String, dynamic> params,
) async {
  stdout.writeln();
  stdout.writeln('  $_bold$_cyan$ability$_reset');
  for (final entry in params.entries) {
    stdout.writeln(
      '    $_dim${entry.key}:$_reset ${_formatParamValue(entry.value)}',
    );
  }
  stdout.writeln();
  stdout.writeln(
    '  $_green[y]$_reset Yes  $_yellow[a]$_reset Always  $_yellow[aa]$_reset Always all  $_red[n]$_reset No',
  );

  while (true) {
    final answer = await readReplLine(prompt: '> ', showBoundary: false);
    if (answer == null || answer == '__esc__') return TaskApprovalDecision.no;

    switch (answer.trim().toLowerCase()) {
      case 'y':
      case 'yes':
        return TaskApprovalDecision.yes;
      case 'aa':
        return TaskApprovalDecision.alwaysAllowAll;
      case 'a':
      case 'always allow':
        return TaskApprovalDecision.alwaysAllow;
      case 'n':
      case 'no':
      case '':
        return TaskApprovalDecision.no;
      default:
        stdout.writeln('Please choose y, a, aa, or n.');
        break;
    }
  }
}

Future<void> startRepl({bool createNew = false, String? sessionId}) async {
  final sessionDir = getReplSessionDir(createNew: createNew, sessionId: sessionId);
  final sessionFile = File(p.join(sessionDir.path, 'messages.json'));
  final alwaysAllowedAbilities = <String>{};
  String? currentStatus;
  var statusTick = 0;
  Timer? statusTimer;

  void startStatus(String text) {
    currentStatus = text;
    _renderReplStatus(text, tick: statusTick);
    statusTimer?.cancel();
    statusTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (currentStatus == null) return;
      statusTick++;
      _renderReplStatus(currentStatus!, tick: statusTick);
    });
  }

  void stopStatus() {
    statusTimer?.cancel();
    statusTimer = null;
    currentStatus = null;
    _clearReplStatusLine();
  }

  final agent = Agents(
    taskApprovalPrompt: _promptTaskApproval,
    statusReporter: startStatus,
    onTaskComplete: (ability, params, result) {
      if ((ability == 'modifyFile' || ability == 'editFile') &&
          result['success'] == true) {
        _renderFileDiff(params['path'] as String? ?? '', result);
      }
    },
    alwaysAllowedAbilities: alwaysAllowedAbilities,
  )..loadSession(sessionFile);

  Logger.info('REPL session: ${p.basename(sessionDir.path)}');
  Logger.info(
    'REPL mode started. Type /exit or /quit to stop. Type /help for commands.',
  );
  _displayReplHistory(agent, sessionDir);

  while (true) {
    final input = await readReplLine(prompt: _replUserPrompt);

    if (input == null) break;
    // ESC 打断输入
    if (input == '__esc__') {
      stdout.writeln('$_dim(cancelled)$_reset');
      continue;
    }

    final message = input.trim();
    if (message.isEmpty) continue;

    // 命令处理（不区分大小写）
    final cmd = message.toLowerCase();
    if (cmd == '/exit' || cmd == '/quit' || cmd == 'exit' || cmd == 'quit' || cmd == '、exit' || cmd == '、quit') {
      exit(0);
    }
    if (cmd == '/help') {
      stdout.writeln();
      stdout.writeln('$_bold Commands $_reset');
      stdout.writeln('  $_cyan/help$_reset    Show this help message');
      stdout.writeln(
        '  $_cyan/exit$_reset    Exit the REPL  (${_dim}or /quit$_reset)',
      );
      stdout.writeln('  $_cyan/clear$_reset   Clear chat history and screen');
      stdout.writeln();
      continue;
    }
    if (cmd == '/clear') {
      agent.messages.removeWhere((msg) => msg['role'] != 'system');
      alwaysAllowedAbilities.clear();
      // 重建会话目录
      if (!sessionDir.existsSync()) {
        sessionDir.createSync();
      }
      if (sessionFile.existsSync()) {
        sessionFile.writeAsStringSync('[]');
      }
      // 清屏
      stdout.write('\x1B[2J\x1B[H');
      stdout.writeln('Chat history cleared.');
      continue;
    }

    try {
      final reply = StringBuffer();
      var assistantStarted = false;
      startStatus('Thinking...');

      await for (final chunk in agent.mainAgent(message)) {
        if (chunk.startsWith('[debug]')) {
          stdout.write(chunk);
          continue;
        }

        if (!assistantStarted) {
          stopStatus();
          stdout.write(_replAssistantPrompt);
          assistantStarted = true;
        }

        reply.write(chunk);
      }

      if (!assistantStarted) {}

      if (!assistantStarted) {
        stopStatus();
        stdout.write(_replAssistantPrompt);
      }

      stdout.write(_renderMarkdownForTerminal(reply.toString()));
      stdout.writeln();
      stdout.writeln();
    } catch (e) {
      stopStatus();
      Logger.error('REPL error: $e');
    }
  }
}

void main(List<String> args) {
  bool createNewSession = true;
  String? sessionId;
  bool listSessions = false;
  bool showHelp = false;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '-c' || args[i] == '--continue') {
      createNewSession = false;
    } else if (args[i] == '-s' || args[i] == '--session') {
      if (i + 1 < args.length) {
        sessionId = args[i + 1];
        createNewSession = false;
        i++;
      }
    } else if (args[i] == '-l' || args[i] == '--list') {
      listSessions = true;
    } else if (args[i] == '-h' || args[i] == '--help') {
      showHelp = true;
    }
  }

  if (showHelp) {
    stdout.writeln('Usage: nwagent [options]');
    stdout.writeln();
    stdout.writeln('Options:');
    stdout.writeln('  -c, --continue       Continue the last session.');
    stdout.writeln('  -s, --session <id>   Resume a specific session.');
    stdout.writeln('  -l, --list           List all existing sessions.');
    stdout.writeln('  -h, --help           Show this help message.');
    stdout.writeln();
    stdout.writeln('If no options are provided, a new session is created by default.');
    exit(0);
  }

  if (listSessions) {
    final sessionsDir = Directory(p.join(Config.appDataDir, 'sessions'));
    if (sessionsDir.existsSync()) {
      final existingSessions = sessionsDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      stdout.writeln('Existing sessions:');
      for (final dir in existingSessions) {
        stdout.writeln('  - ${p.basename(dir.path)} (Last modified: ${dir.statSync().modified})');
      }
    } else {
      stdout.writeln('No sessions found.');
    }
    exit(0);
  }

  runZonedGuarded(
    () async {
      // 创建配置文件
      File configFile = File(p.join(Config.appDataDir, 'config.json'));
      if (!configFile.parent.existsSync()) {
        configFile.parent.createSync(recursive: true);
      }
      if (!configFile.existsSync()) {
        var uuid = Uuid();
        String token = uuid.v4().replaceAll('-', '').substring(0, 8);
        Map<String, dynamic> configContent = {
          "baseUrl": "https://api.deepseek.com",
          "apiKey": "",
          "provider": "deepseek",
          "host": "0.0.0.0",
          "port": 9080,
          "model": "deepseek-v4-flash[1m]",
          "token": token,
          "reasoningEffort": "medium",
          "repl": false,
          "debug": false,
          "blockedFiles": [".env", ".env.dev", ".env.prod", "config.json", "credentials.json", "id_rsa", "id_rsa.pub"]
        };
        configFile.writeAsStringSync(jsonEncode(configContent));
        Logger.info('Created default config.json');
      }
      // 读取配置文件
      String configString = configFile.readAsStringSync();
      Map<String, dynamic> config = jsonDecode(configString);
      Config.baseUrl = config['baseUrl'] ?? Config.baseUrl;
      Config.apiKey = config['apiKey'] ?? Config.apiKey;
      Config.provider = config['provider'] ?? Config.provider;
      Config.host = config['host'] ?? Config.host;
      Config.port = config['port'] ?? Config.port;
      Config.model = config['model'] ?? Config.model;
      Config.token = config['token'] ?? Config.token;
      Config.repl = config['repl'] ?? Config.repl;
      Config.debug = config['debug'] ?? Config.debug;
      
      if (config['blockedFiles'] is List) {
        Config.blockedFiles = List<String>.from(config['blockedFiles']);
      } else if (config['blockedFiles'] == null) {
        // 提供默认阻止列表，如果你想要严格控制
        Config.blockedFiles = ['.env', '.env.dev', '.env.prod', 'config.json', 'credentials.json', 'id_rsa', 'id_rsa.pub'];
      }
      
      String host = Config.host;
      int port = Config.port;
      if (Config.apiKey.isEmpty) {
        Logger.error('API key is missing in config.json!');
        Future.delayed(Duration(seconds: 5), () => exit(1));
      }

      if (Config.repl || createNewSession || sessionId != null) {
        await startRepl(createNew: createNewSession, sessionId: sessionId);
        return;
      }

      // 会话目录
      Directory sessionsDir = Directory(p.join(Config.appDataDir, 'sessions'));
      if (!sessionsDir.existsSync()) {
        sessionsDir.createSync();
        Logger.info('Created sessions directory');
      }

      // 定义错误处理的中间件
      Middleware handleErrors() {
        return (Handler handler) {
          return (Request request) async {
            try {
              // 处理请求
              return await handler(request);
            } catch (e, stackTrace) {
              // 捕获错误并记录到 Logger
              Logger.error(
                'Internal Server Error: $e\nStack Trace:\n$stackTrace',
              );
              // 返回 HTTP 500 错误
              return Response(
                500,
                body: '{"error": "500 Internal Server Error"}',
                headers: {'Content-Type': 'application/json'},
              );
            }
          };
        };
      }

      // 创建路由
      var router = Router();

      // ping
      router.get('/agent/v1/ping', (Request request) {
        return Response.ok('pong!', encoding: utf8);
      });

      // 请求AI模型
      router.post('/agent/v1/chat/completions', (Request request) async {
        try {
          // 解析请求体
          final body = await request.readAsString();
          final json = jsonDecode(body) as Map<String, dynamic>;

          // 获取参数
          final sessionId = json['sessionId'] as String?;
          final message = json['message'] as String?;

          // 验证参数
          if (sessionId == null || sessionId.isEmpty) {
            return Response.badRequest(
              body: '{"error": "sessionId is required"}',
              headers: {'Content-Type': 'application/json'},
            );
          }
          if (message == null || message.isEmpty) {
            return Response.badRequest(
              body: '{"error": "message is required"}',
              headers: {'Content-Type': 'application/json'},
            );
          }

          // 调用 HttpApi 处理消息
          final result = await HttpApi.sendMessage(
            sessionId: sessionId,
            message: message,
            sessionsDirPath: sessionsDir.path,
          );

          // 返回结果
          return Response.ok(
            jsonEncode(result),
            headers: {'Content-Type': 'application/json'},
          );
        } catch (e) {
          Logger.error('Error handling chat completions: $e');
          return Response.internalServerError(
            body: '{"error": "Internal Server Error"}',
            headers: {'Content-Type': 'application/json'},
          );
        }
      });

      // 定义404错误处理
      router.all('/<catchall|.*>', (Request request) {
        return Response.notFound('404 Not Found: ${request.url}');
      });

      // 配置中间件
      var httpHandler = const Pipeline()
          .addMiddleware(createCorsMiddleware())
          .addMiddleware(customLogRequests())
          .addMiddleware(handleAuth(token: Config.token))
          .addMiddleware(handleErrors())
          .addHandler(router.call);

      // 启动服务器
      await io.serve(
        (Request request) {
          return httpHandler(request);
        },
        Config.host,
        Config.port,
      );
      if (host.contains(":")) {
        Logger.info(
          'HTTP server listening on http://[$host]:$port (Ctrl+C to quit)',
        );
      } else {
        Logger.info('Serving at http://$host:$port (Ctrl+C to quit)');
      }
    },
    (error, stackTrace) {
      Logger.error('Uncaught exception: $error\n$stackTrace');
    },
  );
}
