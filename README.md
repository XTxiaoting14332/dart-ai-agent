# 🚀 NWAgent - NightWind Agent

[![Dart](https://img.shields.io/badge/dart-v3.12+-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/your-repo/nwagent/pulls)

> 一个基于 Dart 的本地 AI Agent 框架，通过 LLM 驱动的 ReAct 循环完成任务。

## ✨ 功能特性

- **🧠 ReAct 循环**：思考-行动-观察，逐步解决复杂问题
- **🛠️ 10+ 内置技能**：文件操作、命令执行、网络搜索、网页抓取等
- **👾 子代理派发**：自动派发探索、研究、编辑子代理处理子任务
- **🔒 安全审批**：敏感操作需用户确认，支持始终允许列表
- **💾 会话管理**：自动保存对话历史，支持 `/clear` 清空
- **🌐 HTTP API**：RESTful 接口，可与任何客户端集成
- **🎨 REPL 模式**：彩色命令行交互，支持历史记录

## 📦 安装

### 前置条件

- [Dart SDK](https://dart.dev/get-dart) >= 3.12.0-278.0.dev

### 步骤

```bash
# 克隆仓库
git clone https://github.com/your-repo/nwagent.git
cd nwagent

# 获取依赖
dart pub get
```

## ⚙️ 配置

编辑 `config.json`（首次运行自动生成）：

```json
{
  "baseUrl": "https://api.deepseek.com",
  "apiKey": "your-api-key-here",
  "provider": "openai",
  "host": "0.0.0.0",
  "port": 8080,
  "model": "deepseek-chat",
  "token": "",
  "repl": false,
  "debug": false
}
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `baseUrl` | API 基础地址 | DeepSeek |
| `apiKey` | API 密钥（必填） | - |
| `provider` | 提供者（当前仅 openai） | openai |
| `host` | 监听地址 | 0.0.0.0 |
| `port` | 监听端口 | 8080 |
| `model` | 模型名称 | deepseek-chat |
| `token` | 身份验证令牌（可选） | - |
| `repl` | 启用 REPL 模式 | false |
| `debug` | 调试输出 | false |

## 🚀 使用

### HTTP 服务器模式（默认）

```bash
dart run bin/nwagent.dart
```

请求示例：

```bash
curl -X POST http://localhost:8080/agent/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "列出当前目录下的文件"}]}'
```

### REPL 模式

设置 `"repl": true` 后运行：

```bash
dart run bin/nwagent.dart
```

输入问题即可交互，输入 `/clear` 清空历史，`/exit` 退出。

## 📁 项目结构

```
.
├── bin/                # 入口文件
├── lib/                # 核心库
│   ├── agents.dart     # Agent 逻辑（ReAct 循环）
│   ├── core.dart       # 技能实现与 LLM 客户端
│   ├── global.dart     # 全局配置
│   └── logger.dart     # 日志工具
├── sessions/           # 对话历史（自动生成）
├── config.json         # 配置文件
├── pubspec.yaml        # 项目元数据
└── README.md           # 本文件
```

## 🤝 贡献

欢迎提交 Issue 或 Pull Request。请保持代码风格一致并通过测试。

## 📄 许可

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。