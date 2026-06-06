import 'dart:convert';
import 'dart:io';

import 'package:nwagent/core.dart';
import 'package:nwagent/global.dart';

/// Agent 定义
class TaskSubagentResult {
  final Map<String, dynamic> task;
  final Map<String, dynamic> result;

  TaskSubagentResult({required this.task, required this.result});
}

enum TaskApprovalDecision { yes, alwaysAllow, alwaysAllowAll, no }

typedef TaskApprovalPrompt =
    Future<TaskApprovalDecision> Function(
      String ability,
      Map<String, dynamic> params,
    );

class Agents {
  Agents({
    this.taskApprovalPrompt,
    this.statusReporter,
    this.onTaskComplete,
    Set<String>? alwaysAllowedAbilities,
  }) : alwaysAllowedAbilities = alwaysAllowedAbilities ?? <String>{};

  final DeepSeekAI ai = DeepSeekAI();
  final Skills skills = Skills();
  final TaskApprovalPrompt? taskApprovalPrompt;
  final void Function(String message)? statusReporter;
  final void Function(
    String ability,
    Map<String, dynamic> params,
    Map<String, dynamic> result,
  )?
  onTaskComplete;
  final Set<String> alwaysAllowedAbilities;
  static const int _maxSteps = 10;
  static const int _maxSubSteps = 5;

  final String systemJsonPrompt = """
你是一个本地 AI Agent 的编排器。用户会提出需求，你需要通过调用能力（Skills）来完成它。

你采用 ReAct 循环模式：每次只决定一个动作，看到执行结果后再决定下一步。

输出严格 JSON，不要输出解释文字，不要使用注释，不要在 JSON 外包裹任何内容。

=== 可用能力 ===

1. getSystemInfo - 获取系统信息、当前工作目录、环境变量、宿主机的日期和时间。参数：{}
2. runCommand - 执行系统命令。参数：{"command":"命令"}
3. readFile - 读取文件内容。参数：{"path":"文件路径"}
4. writeFile - 写入文件。参数：{"path":"路径","content":"内容"}
5. modifyFile - 按行号批量修改文件。参数：{"path":"路径","edits":[{"contentLine":0,"newContent":"新","type":"replace|insert|delete"}]}
6. editFile - 基于文本匹配修改文件（推荐）。参数：{"path":"路径","oldString":"原文","newString":"新文","replaceAll":false}
7. listDirectory - 列出目录内容。参数：{"path":".","recursive":false,"maxDepth":3}
8. searchFiles - 搜索文件。参数：{"path":".","namePattern":"正则","contentPattern":"正则","maxResults":50}
9. webSearch - Bing 搜索。参数：{"query":"关键词","maxResults":5}
10. webFetch - 抓取网页内容。参数：{"url":"网址","maxLength":8000}

=== 输出格式 ===

每次输出以下三种之一：

1. 执行一个能力：
{
  "thought": "你的思考过程（不会展示给用户）",
  "action": {"ability": "能力名称", "params": {}}
}

2. 派发子代理处理复杂子任务：
{
  "thought": "你的思考过程",
  "spawn": {"type": "explorer|researcher|editor|coder|general", "task": "子任务描述"}
}
子代理类型：
- explorer: 代码探索、项目分析（可用 listDirectory, searchFiles, readFile, runCommand）
- researcher: 网络搜索、信息收集（可用 webSearch, webFetch, runCommand）
- editor: 文件修改（可用 readFile, editFile, modifyFile, writeFile）
- coder: 先理解用户的需求，并对提示词进行优化，确保代码符合用户的需求（可用 readFile, editFile, modifyFile, writeFile）
- general: 通用任务（可用全部能力）

3. 给出最终回答：
{
  "thought": "你的思考过程",
  "answer": "给用户的回答"
}

=== 规则 ===

- 每次只输出一个动作，不要一次规划多个任务。
- 看到 Observation 结果后再决定下一步，不要凭猜测行动。
- 简单任务直接用 action 调用能力，复杂探索任务用 spawn 派发子代理。
- 如果用户只是普通聊天，直接输出 answer。
- 修改文件优先用 editFile（不需要行号）；需要批量按行操作用 modifyFile。
- 分析源码时：先 listDirectory 了解结构 → readFile 关键文件 → 基于实际代码分析。或者直接 spawn explorer 子代理。
- 搜索互联网用 webSearch，抓取详情用 webFetch。
- 不要编造不存在的能力名称。params 必须是对象。所有字段用双引号。
- 当 Observation 返回 success:false 时，说明操作失败了。你必须分析失败原因，换一种方法重试，不要放弃。例如：runCommand 失败可以尝试其他命令；readFile 路径不对可以先 listDirectory 或 searchFiles 找到正确路径；editFile 匹配失败可以先 readFile 确认内容再重试。不要在同一个失败的方法上反复重试超过2次。
""";
  final List<Map<String, dynamic>> messages = [
    {
      'role': 'system',
      'content':
          '你是一个本地 AI Agent，名叫 NightWind Agent，简称 NWAgent。你可以通过调用预定义的能力（Skills）来完成用户的需求。请根据用户的输入规划需要执行的任务，并调用相应的能力来完成。',
    },
  ];

  File? sessionFile;

  void loadSession(File file) {
    sessionFile = file;

    if (!file.existsSync()) return;

    final data = jsonDecode(file.readAsStringSync()) as List;
    messages
      ..clear()
      ..addAll(data.cast<Map<String, dynamic>>());
  }

  void saveSession() {
    final file = sessionFile;
    if (file == null) return;

    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(messages),
    );
  }

  /// 主Agent — ReAct 循环
  Stream<String> mainAgent(String userMessage) async* {
    messages.add({'role': 'user', 'content': userMessage});

    final finalAnswer = StringBuffer();
    final steps = <String>[]; // 收集步骤描述
    const dim = '\x1B[2m';
    const reset = '\x1B[0m';

    for (int step = 0; step < _maxSteps; step++) {
      final planMessages = [
        {'role': 'system', 'content': systemJsonPrompt},
        ...messages,
      ];

      statusReporter?.call(
        'Thinking...${step > 0 ? " (step ${step + 1})" : ""}',
      );

      if (Config.debug) {
        yield '[debug] Step ${step + 1} planning:\n';
        yield '${const JsonEncoder.withIndent('  ').convert(planMessages)}\n\n';
      }

      final planText = StringBuffer();
      await for (final chunk in ai.streamChat(planMessages, jsonMode: true)) {
        planText.write(chunk);
      }

      Map<String, dynamic> plan;
      try {
        plan = jsonDecode(planText.toString()) as Map<String, dynamic>;
      } catch (e) {
        messages.add({'role': 'assistant', 'content': planText.toString()});
        messages.add({
          'role': 'user',
          'content': '你的输出不是合法 JSON，请重新输出。只输出 JSON，不要其他文字。',
        });
        continue;
      }

      if (Config.debug) {
        yield '[debug] Agent plan:\n';
        yield '${const JsonEncoder.withIndent('  ').convert(plan)}\n\n';
      }

      // 检查是否要给出最终回答
      if (plan.containsKey('answer')) {
        final answer = plan['answer'] as String? ?? '';
        finalAnswer.write(answer);
        messages.add({'role': 'assistant', 'content': answer});
        // 如果有多于1步，回答前空一行分隔
        if (steps.length > 1) yield '\n';
        yield answer;
        break;
      }

      // 执行动作或派发子代理
      Map<String, dynamic> result;
      final thought = plan['thought'] as String? ?? '';
      if (plan.containsKey('spawn')) {
        final spawn = Map<String, dynamic>.from(plan['spawn'] as Map);
        statusReporter?.call('Spawning ${spawn['type']} sub-agent...');
        result = await _runSubAgent(spawn);
      } else if (plan.containsKey('action')) {
        final action = Map<String, dynamic>.from(plan['action'] as Map);
        statusReporter?.call(_actionStatus(action));
        final taskResult = await _executeTaskSubagent(action);
        result = Map<String, dynamic>.from(taskResult.result);

        onTaskComplete?.call(
          action['ability'] as String? ?? '',
          Map<String, dynamic>.from(action['params'] as Map? ?? {}),
          result,
        );
      } else {
        messages.add({'role': 'assistant', 'content': jsonEncode(plan)});
        messages.add({
          'role': 'user',
          'content': '请输出 action、spawn 或 answer 之一。',
        });
        continue;
      }

      // 输出步骤描述（LLM 的 thought 总结）
      final stepLabel = thought.isNotEmpty ? thought : '执行中...';
      steps.add(stepLabel);
      yield '$dim  ${steps.length}. $stepLabel$reset\n';

      if (Config.debug) {
        yield '[debug] Result:\n';
        yield '${const JsonEncoder.withIndent('  ').convert(result)}\n\n';
      }

      messages.add({'role': 'assistant', 'content': jsonEncode(plan)});
      messages.add({
        'role': 'user',
        'content': 'Observation: ${jsonEncode(result)}',
      });
    }

    if (finalAnswer.isEmpty) {
      // 循环结束还没 answer，让 LLM 总结
      if (steps.length > 1) yield '\n';
      messages.add({
        'role': 'user',
        'content': '你已经执行了多步操作，请根据以上所有 Observation 的结果，直接回答用户的原始问题。不要输出 JSON。',
      });
      statusReporter?.call('Responding...');
      final response = StringBuffer();
      await for (final chunk in ai.streamChat(messages)) {
        response.write(chunk);
        yield chunk;
      }
      messages.add({'role': 'assistant', 'content': response.toString()});
    }

    saveSession();
  }

  Future<TaskSubagentResult> _executeTaskSubagent(
    Map<String, dynamic> task,
  ) async {
    final normalizedTask = Map<String, dynamic>.from(task);
    final ability = normalizedTask['ability'] as String? ?? '';
    final params = Map<String, dynamic>.from(
      normalizedTask['params'] as Map? ?? const {},
    );

    if (_requiresApproval(ability) && !alwaysAllowedAbilities.contains(ability)) {
      final decision = await _promptTaskApproval(ability, params);
      switch (decision) {
        case TaskApprovalDecision.no:
          return TaskSubagentResult(
            task: normalizedTask,
            result: {
              'success': false,
              'cancelled': true,
              'error': 'User declined',
            },
          );
        case TaskApprovalDecision.alwaysAllow:
          alwaysAllowedAbilities.add(ability);
          break;
        case TaskApprovalDecision.alwaysAllowAll:
          alwaysAllowedAbilities.addAll(
            {'runCommand', 'writeFile', 'modifyFile', 'editFile'},
          );
          break;
        case TaskApprovalDecision.yes:
          break;
      }
    }

    statusReporter?.call(_actionStatus(normalizedTask));
    final result = await _runSkill(ability, params);
    return TaskSubagentResult(task: normalizedTask, result: result);
  }

  /// 生成带参数描述的状态提示
  String _actionStatus(Map<String, dynamic> action) {
    final ability = action['ability'] as String? ?? '';
    final params = Map<String, dynamic>.from(action['params'] as Map? ?? {});
    switch (ability) {
      case 'readFile':
        return 'Reading ${params['path'] ?? ''}...';
      case 'writeFile':
        return 'Writing ${params['path'] ?? ''}...';
      case 'editFile':
        return 'Editing ${params['path'] ?? ''}...';
      case 'modifyFile':
        return 'Modifying ${params['path'] ?? ''}...';
      case 'listDirectory':
        return 'Listing ${params['path'] ?? '.'}...';
      case 'searchFiles':
        final name = params['namePattern'] as String?;
        final content = params['contentPattern'] as String?;
        final query = name ?? content ?? '';
        return 'Searching "$query"...';
      case 'webSearch':
        return 'Searching "${params['query'] ?? ''}"...';
      case 'webFetch':
        return 'Fetching ${params['url'] ?? ''}...';
      case 'runCommand':
        return 'Running `${params['command'] ?? ''}`...';
      case 'getSystemInfo':
        return 'Getting system info...';
      default:
        return 'Running $ability...';
    }
  }

  bool _requiresApproval(String ability) {
    return ability == 'runCommand' ||
        ability == 'writeFile' ||
        ability == 'modifyFile' ||
        ability == 'editFile';
  }

  Future<TaskApprovalDecision> _promptTaskApproval(
    String ability,
    Map<String, dynamic> params,
  ) async {
    if (alwaysAllowedAbilities.contains(ability)) {
      return TaskApprovalDecision.yes;
    }

    final prompt = taskApprovalPrompt;
    if (prompt == null) {
      return TaskApprovalDecision.yes;
    }

    return prompt(ability, params);
  }

  Future<Map<String, dynamic>> _runSkill(
    String ability,
    Map<String, dynamic> params,
  ) async {
    switch (ability) {
      case 'getSystemInfo':
        return Map<String, dynamic>.from(await skills.getSystemInfo());
      case 'runCommand':
        return Map<String, dynamic>.from(
          await skills.runCommand(params['command'] as String? ?? ''),
        );
      case 'readFile':
        return Map<String, dynamic>.from(
          await skills.readFile(params['path'] as String? ?? ''),
        );
      case 'writeFile':
        return Map<String, dynamic>.from(
          await skills.writeFile(
            params['path'] as String? ?? '',
            params['content'] as String? ?? '',
          ),
        );
      case 'modifyFile':
        List<Map<String, dynamic>> edits;
        if (params['edits'] != null) {
          edits = (params['edits'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          // 单个修改
          edits = [
            {
              'contentLine': params['contentLine'] as int? ?? 0,
              'newContent': params['newContent'] as String? ?? '',
              'type': params['type'] as String? ?? 'replace',
            },
          ];
        }
        return Map<String, dynamic>.from(
          await skills.modifyFile(params['path'] as String? ?? '', edits),
        );
      case 'editFile':
        return Map<String, dynamic>.from(
          await skills.editFile(
            params['path'] as String? ?? '',
            params['oldString'] as String? ?? '',
            params['newString'] as String? ?? '',
            replaceAll: params['replaceAll'] as bool? ?? false,
          ),
        );
      case 'listDirectory':
        return Map<String, dynamic>.from(
          await skills.listDirectory(
            params['path'] as String? ?? '.',
            recursive: params['recursive'] as bool? ?? false,
            maxDepth: params['maxDepth'] as int? ?? 3,
          ),
        );
      case 'searchFiles':
        return Map<String, dynamic>.from(
          await skills.searchFiles(
            params['path'] as String? ?? '.',
            namePattern: params['namePattern'] as String?,
            contentPattern: params['contentPattern'] as String?,
            maxResults: params['maxResults'] as int? ?? 50,
          ),
        );
      case 'webSearch':
        return Map<String, dynamic>.from(
          await skills.webSearch(
            params['query'] as String? ?? '',
            maxResults: params['maxResults'] as int? ?? 5,
          ),
        );
      case 'webFetch':
        return Map<String, dynamic>.from(
          await skills.webFetch(
            params['url'] as String? ?? '',
            maxLength: params['maxLength'] as int? ?? 8000,
          ),
        );
      default:
        return {'success': false, 'error': 'Unknown ability: $ability'};
    }
  }

  /// 派发子代理
  Future<Map<String, dynamic>> _runSubAgent(Map<String, dynamic> spawn) async {
    final type = spawn['type'] as String? ?? 'general';
    final task = spawn['task'] as String? ?? '';

    final availableSkills = _subAgentSkills(type);
    final systemPrompt = _subAgentPrompt(type);

    // 子代理有独立的消息列表
    final subMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': task},
    ];

    String summary = '';

    for (int step = 0; step < _maxSubSteps; step++) {
      statusReporter?.call('Sub-agent($type) step ${step + 1}...');

      final planText = StringBuffer();
      await for (final chunk in ai.streamChat(subMessages, jsonMode: true)) {
        planText.write(chunk);
      }

      Map<String, dynamic> plan;
      try {
        plan = jsonDecode(planText.toString()) as Map<String, dynamic>;
      } catch (e) {
        subMessages.add({'role': 'assistant', 'content': planText.toString()});
        subMessages.add({'role': 'user', 'content': '输出不是合法 JSON，请重试。'});
        continue;
      }

      if (Config.debug) {
        // ignore: avoid_print
        print('[debug] Sub-agent($type) step ${step + 1}: ${jsonEncode(plan)}');
      }

      // 子代理给出最终回答
      if (plan.containsKey('answer')) {
        summary = plan['answer'] as String? ?? '';
        break;
      }

      // 执行能力
      if (plan.containsKey('action')) {
        final action = Map<String, dynamic>.from(plan['action'] as Map);
        final ability = action['ability'] as String? ?? '';

        // 检查该能力是否对该子代理类型可用
        if (!availableSkills.contains(ability)) {
          subMessages.add({'role': 'assistant', 'content': jsonEncode(plan)});
          subMessages.add({
            'role': 'user',
            'content': '你不能使用 $ability 能力。可用能力: ${availableSkills.join(", ")}',
          });
          continue;
        }

        final result = await _runSkill(
          ability,
          Map<String, dynamic>.from(action['params'] as Map? ?? {}),
        );

        subMessages.add({'role': 'assistant', 'content': jsonEncode(plan)});
        subMessages.add({
          'role': 'user',
          'content': 'Observation: ${jsonEncode(result)}',
        });
      } else {
        subMessages.add({'role': 'assistant', 'content': jsonEncode(plan)});
        subMessages.add({'role': 'user', 'content': '请输出 action 或 answer。'});
      }
    }

    // 如果循环结束还没得到 answer，让 LLM 总结
    if (summary.isEmpty) {
      subMessages.add({
        'role': 'user',
        'content': '请根据以上所有 Observation 总结你的发现。不要输出 JSON。',
      });
      final response = StringBuffer();
      await for (final chunk in ai.streamChat(subMessages)) {
        response.write(chunk);
      }
      summary = response.toString();
    }

    return {'type': type, 'task': task, 'summary': summary};
  }

  /// 子代理可用的能力列表
  Set<String> _subAgentSkills(String type) {
    switch (type) {
      case 'explorer':
        return {'listDirectory', 'searchFiles', 'readFile', 'runCommand'};
      case 'researcher':
        return {'webSearch', 'webFetch', 'runCommand'};
      case 'editor':
        return {'readFile', 'editFile', 'modifyFile', 'writeFile'};
      case 'coder':
        return {'readFile', 'editFile', 'modifyFile', 'writeFile'};
      case 'general':
      default:
        return {
          'getSystemInfo',
          'runCommand',
          'readFile',
          'writeFile',
          'modifyFile',
          'editFile',
          'listDirectory',
          'searchFiles',
          'webSearch',
          'webFetch',
        };
    }
  }

  /// 子代理系统提示
  String _subAgentPrompt(String type) {
    switch (type) {
      case 'explorer':
        return '''你是一个代码探索子代理。你的任务是深入探索项目代码，找出关键信息。
你可以使用的能力：listDirectory, searchFiles, readFile, runCommand。
你应该主动递归探索目录结构，读取关键文件，不要只看表面。
如果某个操作失败了（success:false），分析原因并换一种方法重试，不要放弃。例如：路径不对可以先 listDirectory 或 searchFiles 找到正确路径。
输出格式为严格 JSON：{"thought":"思考","action":{"ability":"能力","params":{}}} 或 {"thought":"思考","answer":"总结"}''';

      case 'researcher':
        return '''你是一个网络研究子代理。你的任务是搜索互联网并收集信息。
你可以使用的能力：webSearch, webFetch, runCommand。
先搜索获取链接，再抓取相关页面提取详情。
如果某个操作失败了（success:false），分析原因并换一种方法重试。例如：webFetch 失败可以尝试其他 URL 或用 webSearch 重新搜索。
输出格式为严格 JSON：{"thought":"思考","action":{"ability":"能力","params":{}}} 或 {"thought":"思考","answer":"总结"}''';

      case 'editor':
        return '''你是一个文件编辑子代理。你的任务是精确修改文件。
你可以使用的能力：readFile, editFile, modifyFile, writeFile。
必须先 readFile 确认内容，再用 editFile/modifyFile 修改。修改前不要猜测文件内容。
如果 editFile 匹配失败，先 readFile 确认实际内容再重试。不要在同一个失败的方法上反复重试超过2次。
输出格式为严格 JSON：{"thought":"思考","action":{"ability":"能力","params":{}}} 或 {"thought":"思考","answer":"总结"}''';
      case 'coder':
        return '''你是一个代码编辑子代理。你的任务是根据用户需求写代码或修改代码。
你可以使用的能力：readFile, editFile, modifyFile, writeFile。
修改代码前必须先 readFile 确认内容，再用 editFile/modifyFile 修改。修改前不要猜测文件内容。
如果操作失败了，分析原因并换一种方法重试。例如：editFile 匹配失败可以先 readFile 确认实际内容。
输出格式为严格 JSON：{"thought":"思考","action":{"ability":"能力","params":{}}} 或 {"thought":"思考","answer":"总结"}''';

      case 'general':
      default:
        return '''你是一个通用子代理。你可以使用所有能力来完成任务。
如果某个操作失败了（success:false），分析原因并换一种方法重试，不要放弃。
输出格式为严格 JSON：{"thought":"思考","action":{"ability":"能力","params":{}}} 或 {"thought":"思考","answer":"总结"}''';
    }
  }
}
