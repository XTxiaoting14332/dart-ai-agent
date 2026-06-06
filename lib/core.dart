import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nwagent/global.dart';

/// Agent 能力
class Skills {
  /// 获取系统信息和当前环境变量
  Future<Map> getSystemInfo() async {
    String os = Platform.operatingSystem;
    String version = Platform.operatingSystemVersion;
    String arch = Platform.version;
    String pwd = Directory.current.path;
    String time = DateTime.now().toIso8601String();
    Map<String, String> env = Platform.environment;
    Map info = {
      'os': os,
      'version': version,
      'arch': arch,
      'pwd': pwd,
      'env': env,
      'date': time,
    };
    return info;
  }

  /// 执行系统命令
  Future<Map> runCommand(String command) async {
    String platform = Platform.operatingSystem;
    String executable;
    List<String> arguments;

    switch (platform) {
      case 'windows':
        executable = 'cmd';
        arguments = ['/c', command];
        break;
      case 'linux':
      case 'macos':
        executable = 'bash';
        arguments = ['-c', command];
        break;
      default:
        return {'success': false, 'error': 'Unsupported platform: $platform'};
    }

    try {
      ProcessResult result = await Process.run(executable, arguments);
      return {
        'success': result.exitCode == 0,
        'stdout': result.stdout,
        'stderr': result.stderr,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 读取文件内容
  Future<Map> readFile(String path) async {
    try {
      String content = await File(path).readAsString();
      return {'success': true, 'content': content};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 列出目录内容（支持递归）
  Future<Map> listDirectory(
    String path, {
    bool recursive = false,
    int maxDepth = 3,
  }) async {
    try {
      Directory dir = Directory(path);
      if (!await dir.exists()) {
        return {'success': false, 'error': '目录不存在: $path'};
      }
      List<Map<String, dynamic>> entries = [];
      await _listDir(dir, entries, 0, maxDepth, recursive);
      return {
        'success': true,
        'path': path,
        'entries': entries,
        'total': entries.length,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> _listDir(
    Directory dir,
    List<Map<String, dynamic>> entries,
    int depth,
    int maxDepth,
    bool recursive,
  ) async {
    if (recursive && depth > maxDepth) return;
    try {
      await for (var entity in dir.list(followLinks: false)) {
        String type = entity is Directory ? 'directory' : 'file';
        Map<String, dynamic> entry = {
          'name': entity.uri.pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => '',
          ),
          'path': entity.path,
          'type': type,
        };
        if (type == 'file') {
          entry['size'] = await (entity as File).length();
        }
        entries.add(entry);
        if (type == 'directory' && recursive) {
          await _listDir(
            entity as Directory,
            entries,
            depth + 1,
            maxDepth,
            true,
          );
        }
      }
    } catch (_) {
      // 跳过无权限的目录
    }
  }

  /// 搜索文件（按文件名模式或文件内容）
  Future<Map> searchFiles(
    String path, {
    String? namePattern,
    String? contentPattern,
    int maxResults = 50,
  }) async {
    try {
      Directory dir = Directory(path);
      if (!await dir.exists()) {
        return {'success': false, 'error': '目录不存在: $path'};
      }
      List<Map<String, dynamic>> results = [];
      RegExp? nameRegex = namePattern != null
          ? RegExp(namePattern, caseSensitive: false)
          : null;
      RegExp? contentRegex = contentPattern != null
          ? RegExp(contentPattern)
          : null;
      await _searchDir(dir, results, nameRegex, contentRegex, maxResults);
      return {
        'success': true,
        'results': results,
        'total': results.length,
        'truncated': results.length >= maxResults,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> _searchDir(
    Directory dir,
    List<Map<String, dynamic>> results,
    RegExp? nameRegex,
    RegExp? contentRegex,
    int maxResults,
  ) async {
    if (results.length >= maxResults) return;
    try {
      await for (var entity in dir.list(followLinks: false)) {
        if (results.length >= maxResults) return;
        if (entity is Directory) {
          await _searchDir(
            entity,
            results,
            nameRegex,
            contentRegex,
            maxResults,
          );
        } else if (entity is File) {
          String fileName = entity.uri.pathSegments.lastWhere(
            (s) => s.isNotEmpty,
            orElse: () => '',
          );
          bool nameMatch = nameRegex?.hasMatch(fileName) ?? false;
          bool contentMatch = false;
          if (contentRegex != null) {
            try {
              String content = await entity.readAsString();
              contentMatch = contentRegex.hasMatch(content);
            } catch (_) {}
          }
          // 两个条件都提供时取交集，只提供一个则匹配该条件
          bool matched;
          if (nameRegex != null && contentRegex != null) {
            matched = nameMatch && contentMatch;
          } else {
            matched = nameMatch || contentMatch;
          }
          if (matched) {
            results.add({'path': entity.path, 'name': fileName});
          }
        }
      }
    } catch (_) {}
  }

  /// 写入内容到文件
  Future<Map> writeFile(String path, String content) async {
    try {
      await File(path).writeAsString(content);
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 修改文件内容（支持批量操作）
  Future<Map> modifyFile(String path, List<Map<String, dynamic>> edits) async {
    try {
      List<String> lines = await File(path).readAsLines();

      // 按类型分组，分别处理以避免行号偏移问题
      List<Map<String, dynamic>> deletes = [];
      List<Map<String, dynamic>> replaces = [];
      List<Map<String, dynamic>> inserts = [];

      for (var edit in edits) {
        int line = edit['contentLine'] as int;
        String type = edit['type'] as String;
        if (line < 0 || line > lines.length) {
          return {
            'success': false,
            'error': '行号 $line 超出范围 (0-${lines.length})',
          };
        }
        switch (type) {
          case 'delete':
            deletes.add(edit);
            break;
          case 'replace':
            if (line >= lines.length) {
              return {
                'success': false,
                'error': '行号 $line 超出范围 (0-${lines.length - 1})',
              };
            }
            replaces.add(edit);
            break;
          case 'insert':
            inserts.add(edit);
            break;
          default:
            return {'success': false, 'error': '无效的操作类型: $type'};
        }
      }

      // 记录变更详情（用于 diff 展示）
      List<Map<String, dynamic>> changes = [];

      for (var edit in deletes) {
        int line = edit['contentLine'] as int;
        changes.add({'type': 'delete', 'line': line, 'content': lines[line]});
      }
      for (var edit in replaces) {
        int line = edit['contentLine'] as int;
        changes.add({
          'type': 'replace',
          'line': line,
          'oldContent': lines[line],
          'newContent': edit['newContent'] as String,
        });
      }
      for (var edit in inserts) {
        changes.add({
          'type': 'insert',
          'line': edit['contentLine'] as int,
          'content': edit['newContent'] as String,
        });
      }

      // delete 和 replace 从后往前处理，避免行号偏移
      deletes.sort(
        (a, b) => (b['contentLine'] as int).compareTo(a['contentLine'] as int),
      );
      replaces.sort(
        (a, b) => (b['contentLine'] as int).compareTo(a['contentLine'] as int),
      );
      // insert 从前往后处理
      inserts.sort(
        (a, b) => (a['contentLine'] as int).compareTo(b['contentLine'] as int),
      );

      for (var edit in deletes) {
        lines.removeAt(edit['contentLine'] as int);
      }
      for (var edit in replaces) {
        lines[edit['contentLine'] as int] = edit['newContent'] as String;
      }
      // insert 时行号需要补偿已删除的行数
      int deletedBefore(int line) =>
          deletes.where((d) => (d['contentLine'] as int) <= line).length;
      for (var edit in inserts) {
        int line = edit['contentLine'] as int;
        int adjusted = line - deletedBefore(line);
        lines.insert(adjusted, edit['newContent'] as String);
      }

      await File(path).writeAsString(lines.join('\n'));
      return {
        'success': true,
        'modifiedLines': edits.length,
        'changes': changes,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 基于文本匹配修改文件（不需要行号）
  /// oldString 必须在文件中唯一，除非 replaceAll=true
  Future<Map> editFile(
    String path,
    String oldString,
    String newString, {
    bool replaceAll = false,
  }) async {
    try {
      String content = await File(path).readAsString();
      int count = content.split(oldString).length - 1;
      if (count == 0) {
        return {'success': false, 'error': '未找到匹配的文本'};
      }
      if (!replaceAll && count > 1) {
        return {
          'success': false,
          'error': '匹配到 $count 处，请提供更多上下文使匹配唯一，或设置 replaceAll=true',
        };
      }
      String newContent = replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString);
      await File(path).writeAsString(newContent);

      // 计算变更行号
      List<String> oldLines = content.split('\n');
      List<String> newLines = newContent.split('\n');

      // 找到 oldString 在原文中的起始行号
      int charIndex = content.indexOf(oldString);
      int startLine = charIndex >= 0
          ? content.substring(0, charIndex).split('\n').length - 1
          : 0;
      int oldLineCount = oldString.split('\n').length;
      int newLineCount = newString.split('\n').length;

      List<Map<String, dynamic>> changes = [];
      if (oldLineCount == 1 && newLineCount == 1) {
        // 单行替换
        changes.add({
          'type': 'replace',
          'line': startLine,
          'oldContent': oldLines[startLine],
          'newContent': newLines[startLine],
        });
      } else {
        // 多行替换：标记删除旧行、插入新行
        for (int i = 0; i < oldLineCount; i++) {
          changes.add({
            'type': 'delete',
            'line': startLine + i,
            'content': oldLines[startLine + i],
          });
        }
        for (int i = 0; i < newLineCount; i++) {
          changes.add({
            'type': 'insert',
            'line': startLine + i,
            'content': newString.split('\n')[i],
          });
        }
      }

      return {
        'success': true,
        'replacements': replaceAll ? count : 1,
        'changes': changes,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Bing 搜索
  Future<Map> webSearch(String query, {int maxResults = 5}) async {
    try {
      final url = Uri.parse(
        'https://www.bing.com/search',
      ).replace(queryParameters: {'q': query, 'count': maxResults.toString()});
      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );
      if (response.statusCode != 200) {
        return {'success': false, 'error': '搜索请求失败: ${response.statusCode}'};
      }
      final html = response.body;
      final results = _parseBingResults(html, maxResults);
      return {
        'success': true,
        'query': query,
        'results': results,
        'total': results.length,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  List<Map<String, String>> _parseBingResults(String html, int maxResults) {
    final results = <Map<String, String>>[];
    // 匹配 Bing 搜索结果：标题、链接、摘要
    final itemRegex = RegExp(
      r'<li class="b_algo"[^>]*>([\s\S]*?)</li>',
      caseSensitive: false,
    );
    final titleRegex = RegExp(
      r'<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>',
      caseSensitive: false,
    );
    final snippetRegex = RegExp(
      r'<p[^>]*>([\s\S]*?)</p>',
      caseSensitive: false,
    );

    for (final match in itemRegex.allMatches(html)) {
      if (results.length >= maxResults) break;
      final block = match.group(1) ?? '';
      final titleMatch = titleRegex.firstMatch(block);
      if (titleMatch == null) continue;

      final link = titleMatch.group(1) ?? '';
      final title = _stripHtml(titleMatch.group(2) ?? '');
      final snippetMatch = snippetRegex.firstMatch(block);
      final snippet = _stripHtml(snippetMatch?.group(1) ?? '');

      if (link.startsWith('http')) {
        results.add({'title': title, 'url': link, 'snippet': snippet});
      }
    }
    return results;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#39;'), "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 抓取网页内容
  Future<Map> webFetch(String url, {int maxLength = 8000}) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );
      if (response.statusCode != 200) {
        return {'success': false, 'error': '请求失败: ${response.statusCode}'};
      }
      final html = response.body;
      final text = _extractReadableText(html);
      final truncated = text.length > maxLength
          ? text.substring(0, maxLength)
          : text;
      return {
        'success': true,
        'url': url,
        'content': truncated,
        'totalLength': text.length,
        'truncated': text.length > maxLength,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  String _extractReadableText(String html) {
    // 移除 script、style、nav、header、footer 等非内容标签
    var cleaned = html;
    cleaned = cleaned.replaceAll(
      RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<header[\s\S]*?</header>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<noscript[\s\S]*?</noscript>', caseSensitive: false),
      '',
    );
    // 提取 title
    final titleMatch = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    final title = titleMatch != null
        ? _stripHtml(titleMatch.group(1) ?? '')
        : '';
    // 提取正文（优先 article / main，fallback 到 body）
    String body = '';
    final articleMatch = RegExp(
      r'<article[^>]*>([\s\S]*?)</article>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (articleMatch != null) {
      body = articleMatch.group(1) ?? '';
    } else {
      final mainMatch = RegExp(
        r'<main[^>]*>([\s\S]*?)</main>',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (mainMatch != null) {
        body = mainMatch.group(1) ?? '';
      } else {
        final bodyMatch = RegExp(
          r'<body[^>]*>([\s\S]*?)</body>',
          caseSensitive: false,
        ).firstMatch(cleaned);
        body = bodyMatch?.group(1) ?? cleaned;
      }
    }
    // 转换 <br> <p> <h*> <li> 为换行
    body = body.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    body = body.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    body = body.replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n');
    body = body.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');
    body = body.replaceAll(RegExp(r'</li>', caseSensitive: false), '\n');
    // 去掉剩余标签
    body = _stripHtml(body);
    // 压缩多余空行
    body = body.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return title.isNotEmpty ? '$title\n\n$body' : body;
  }
}

/// 请求 AI
class DeepSeekAI {
  Stream<String> streamChat(
    List<Map<String, dynamic>> messages, {
    bool jsonMode = false,
  }) async* {
    final client = http.Client();
    final body = {
      'model': Config.model,
      'messages': messages,
      'stream': true,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    final request =
        http.Request('POST', Uri.parse('${Config.baseUrl}/chat/completions'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${Config.apiKey}',
          })
          ..body = jsonEncode(body);

    final response = await client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      client.close();
      throw Exception('DeepSeek request failed: ${response.statusCode} $body');
    }

    try {
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;

        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        if (data.isEmpty) continue;

        final json = jsonDecode(data) as Map<String, dynamic>;
        final content = json['choices']?[0]?['delta']?['content'];

        if (content is String && content.isNotEmpty) {
          yield content;
        }
      }
    } finally {
      client.close();
    }
  }
}
