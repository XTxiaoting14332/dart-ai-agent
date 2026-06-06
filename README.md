# 🚀 NWAgent - NightWind Agent

[![Dart](https://img.shields.io/badge/dart-v3.12+-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/XTxiaoting14332/dart-ai-agent/pulls)

> 一个基于纯 Dart 开发的极简、轻量的本地 AI Agent 框架。通过大语言模型驱动的 ReAct 循环，自动帮你在本地执行任务。

## ✨ 核心特性

- **🧠 智能 ReAct 循环**：思考-行动-观察，拥有自主决策和修正错误的能力。
- **🛠️ 10+ 内置超级技能**：本地文件修改、系统终端命令执行、网络数据搜索抓取等。
- **👾 子代理派发机制**：遇到复杂任务时，主 Agent 会自动孵化专属子代理（探索者、研究员、程序员等）分工协作。
- **🔒 安全可控审批**：执行危险命令或修改敏感文件需用户确认，也支持一键放行列表。
- **🎨 强大的终端 REPL 模式**：
  - 支持多会话隔离管理（可随时切换、恢复历史对话）。
  - 支持纯原生控制台的**方向键（↑/↓）历史回放**。
  - 支持终端 Markdown 富文本彩色渲染。
- **🌐 HTTP 接口支持**：不仅是个 CLI 工具，也是个后端 API 服务，支持无缝集成到任何项目中。

## 📦 快速开始

### 1. 安装与获取

确保你已安装 [Dart SDK](https://dart.dev/get-dart)（>= 3.12.0）。

```bash
git clone https://github.com/XTxiaoting14332/dart-ai-agent.git
cd dart-ai-agent
dart pub get
```

### 2. 配置文件

初次运行后，程序会在你的用户主目录（`~/.nwagent/` 或 `C:\Users\用户名\.nwagent\`）下自动生成 `config.json` 文件及 `sessions/` 对话数据存放目录。

默认配置如下，请务必填入你的 `apiKey`：

```json
{
  "baseUrl": "https://api.deepseek.com",
  "apiKey": "填写你的大模型 API KEY",
  "provider": "deepseek",
  "host": "0.0.0.0",
  "port": 9080,
  "model": "deepseek-v4-flash",
  "token": "你的接口鉴权Token",
  "repl": true,
  "debug": false
}
```

*注意：本工具强烈建议搭配 DeepSeek 等支持极强代码与指令遵循能力的模型使用。*

## 🚀 玩法指北

### 🎮 玩法一：终端极客模式 (REPL)

修改配置 ` "repl": true `，直接在终端里和你的电脑对话：

```bash
dart run bin/nwagent.dart
```

**多会话管理参数：**
- `dart run bin/nwagent.dart`：默认每次开启一个**全新**的纯净会话。
- `dart run bin/nwagent.dart -c`：**恢复并继续**最后一次未聊完的会话。
- `dart run bin/nwagent.dart -l`：列出当前系统里所有的历史会话 UUID 和时间。
- `dart run bin/nwagent.dart -s <UUID>`：精准跳回某个具体的历史对话节点。
- `dart run bin/nwagent.dart -h`：查看命令行参数帮助。

**REPL 内置快捷指令：**
- `↑` / `↓`：浏览你的输入历史
- `/exit` 或 `exit`：安全且快速退出程序
- `/clear`：清空当前会话的上下文历史并清屏
- `/help`：查看 REPL 内部帮助

### 🌐 玩法二：API 后端模式

修改配置 `"repl": false` 并运行程序，即可将其作为 HTTP 服务后台挂起。

**请求示例 (CURL)：**
```bash
curl -X POST http://localhost:9080/agent/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <你的config中的token>" \
  -d '{
    "sessionId": "任意自定义会话ID",
    "message": "帮我看看当前目录下有哪些文件"
  }'
```

接口返回的是标准化 JSON，包含了 Agent 的执行步骤总结 (`summary`) 和最终回复 (`msg`)。

## 📁 目录架构

```text
.
├── bin/
│   └── nwagent.dart      # CLI 命令行和 HTTP 服务的主入口
├── lib/
│   ├── agents.dart       # Agent 大脑：ReAct 循环、子代理派发调度
│   ├── core.dart         # 能力封装：大模型请求、系统命令、文件/网络等底层实现
│   ├── global.dart       # 全局状态：数据路径算法、静态配置映射
│   ├── http_api.dart     # HTTP API：接口业务逻辑控制器
│   └── logger.dart       # 彩色日志系统
└── pubspec.yaml          # 项目依赖
```
*(注：项目运行产生的数据统一存放在系统 `~/.nwagent/` 目录下，不在项目代码仓库中制造垃圾。)*

## 🤝 参与贡献

欢迎 Fork 和提 PR！如果你觉得这个小工具好用，别忘了给个 ⭐️ Star！

## 📄 开源协议

本项目采用 MIT 许可证，自由使用，详情参见 LICENSE 文件。
