# NWAgent (NightWind Agent)

[![Dart](https://img.shields.io/badge/dart-v3.12+-blue.svg)](https://dart.dev)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/XTxiaoting14332/dart-ai-agent/pulls)

NWAgent 是一个基于 Dart 开发的本地 AI Agent 框架。它通过大语言模型（LLM）驱动 ReAct (Reason+Act) 循环，使 Agent 能够理解自然语言需求，并自主调用系统能力来完成任务。

## 功能特性

- **ReAct 执行逻辑**：Agent 基于观察结果进行推理，并决定下一步的动作，支持错误自我修正。
- **内置底层能力**：支持文件读写与批量修改、系统命令执行、目录搜索以及网络数据抓取。
- **子代理机制**：在处理复杂任务时，主 Agent 可派发专职子代理（如搜索型、编码型）进行并行协作。
- **敏感操作控制**：执行系统命令或修改文件前会强制请求用户审批，支持将高频安全命令加入白名单。
- **交互式命令行 (REPL)**：
  - 支持多会话隔离与管理，可随时暂停、切换或恢复历史任务。
  - 支持原生终端的方向键（↑/↓）历史指令回溯。
  - 具备终端 Markdown 解析与代码高亮支持。
- **HTTP 服务模式**：可作为 RESTful API 后端运行，便于与其他系统或客户端集成。

## 安装指南

NWAgent 提供了针对各主流操作系统的预编译二进制文件，无需配置开发环境。

1. 访问本仓库的 [Releases 页面](https://github.com/XTxiaoting14332/dart-ai-agent/releases) 下载对应的可执行文件。
2. 将二进制文件放置到合适的系统目录中。
3. （仅 Linux / macOS 用户）在终端中赋予文件执行权限：
   ```bash
   chmod +x nwagent
   ```

## 配置文件

首次执行 `./nwagent` 后，程序会在用户的主目录（如 `~/.nwagent/` 或 `C:\Users\用户名\.nwagent\`）下自动生成 `config.json` 配置文件及 `sessions/` 历史数据目录。

默认配置参数如下。请修改其中的 `apiKey` 字段：

```json
{
  "baseUrl": "https://api.deepseek.com",
  "apiKey": "YOUR_API_KEY",
  "provider": "deepseek",
  "host": "0.0.0.0",
  "port": 9080,
  "model": "deepseek-v4-flash",
  "token": "YOUR_AUTH_TOKEN",
  "repl": true,
  "debug": false
}
```
*注：由于系统自动化执行对模型的逻辑推理和指令遵循能力要求极高，建议使用 DeepSeek 等处于第一梯队的模型服务。*

## 使用方法

### REPL 命令行模式

确保配置文件中 `"repl": true`，然后在终端执行：

```bash
./nwagent
```

**会话管理参数：**
- `./nwagent`：默认行为，开启一个全新的会话。
- `./nwagent -c` (或 `--continue`)：恢复并继续上一次活动的会话。
- `./nwagent -s <UUID>` (或 `--session <UUID>`)：恢复指定的历史会话。
- `./nwagent -l` (或 `--list`)：列出所有已保存的历史会话 UUID 及最后修改时间。
- `./nwagent -h` (或 `--help`)：查看命令行参数列表。

**内置交互指令：**
- `/exit` 或 `exit`：结束当前进程并安全退出。
- `/clear`：清空当前会话的上下文记录并清理终端屏幕。
- `/help`：打印 REPL 内部支持的指令列表。

### HTTP 接口模式

将配置文件中的 `"repl": false`，启动 `./nwagent` 后，它将作为后台 HTTP 服务运行。

**调用示例：**
```bash
curl -X POST http://localhost:9080/agent/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_AUTH_TOKEN>" \
  -d '{
    "sessionId": "custom-session-id",
    "message": "请列出当前目录下的所有文件"
  }'
```
接口将返回规范化的 JSON 结构，包含任务执行的汇总过程及最终结果。

## 源码编译

如果需要进行二次开发或自行编译代码，请先安装 [Dart SDK](https://dart.dev/get-dart)（版本 >= 3.12.0）。

1. 克隆代码库并安装依赖：
   ```bash
   git clone https://github.com/XTxiaoting14332/dart-ai-agent.git
   cd dart-ai-agent
   dart pub get
   ```
2. 通过 Dart 运行源码：
   ```bash
   dart run bin/nwagent.dart
   ```
3. 编译为独立执行文件：
   ```bash
   dart compile exe bin/nwagent.dart -o build/nwagent
   ```

## 开源协议

本项目基于 GNU General Public License v3.0 (GPLv3) 开源许可协议发布。详细条款请参见仓库内的 [LICENSE](LICENSE) 文件。
