# 架构与加载机制详解

本文面向想深入了解实现机制的读者（技术面试官 / 二次开发者）。运行时底座为 DeerFlow，本文聚焦**本项目自定义部分如何被框架加载与执行**。

## 1. 一次对话的完整链路

```
用户消息（含附件）
  → Next.js 控制台 /api/* 代理
  → FastAPI Gateway（鉴权、线程持久化）
  → LangGraph 图：输入预处理 → Agent(ReAct 循环) → 输出
                        │
            ┌───────────┼───────────────┐
            ▼           ▼               ▼
        人设注入     技能发现/激活     工具注册表
        SOUL.md     SKILL.md 索引     沙箱工具 + MCP 工具
```

Agent 每一轮：模型看到系统提示词（含人设摘要与可用技能索引）→ 决定直接回答或调用工具 → 工具结果回到模型 → 直到产出最终回复（SSE 流式返回前端）。

## 2. 智能体的磁盘布局与加载

```
.deer-flow/users/{user_id}/
├── agents/resume/
│   ├── config.yaml     # 元数据与能力声明
│   └── SOUL.md         # 人设正文
└── skills/custom/      # 用户级自定义技能
    ├── candidate-report/
    ├── batch-screening/
    └── interview-prep/
```

- 框架扫描 `agents/` 目录，加载 `config.yaml`（名称受 `^[A-Za-z0-9-]+$` 约束）与 `SOUL.md`；**新建/修改文件后新开会话即生效**，无需注册。
- `config.yaml` 未声明的字段继承全局：如不指定 `model` 则使用全局默认模型；`tool_groups` 不写则继承全部已启用工具（本项目收敛为 `file:read` + `file:write`）。

## 3. SOUL.md：行为契约而非功能清单

SOUL.md 解决的是"模型默认行为不符合岗位要求"的问题，写法上以**约束、反例与优先级**为主：

- 身份与服务对象，并显式声明"我不是什么"（分析工具，不是决策者）；
- 什么情况下不动作（未被明确要求不给推荐结论）；
- 准则冲突时的优先级（客观 > 主观、谨慎 > 高效、合规 > 便捷）。

这类约束在普通 Prompt 里容易被长对话稀释，放进框架级人设文件后每次会话稳定注入。

## 4. Skill 系统

### 4.1 包结构

每个技能是一个目录，入口为带 YAML frontmatter 的 `SKILL.md`：

```yaml
---
name: batch-screening            # 与目录同名
description: ...                 # 最重要：模型据此判断何时激活
allowed-tools: [Read, Write]     # 技能激活时的工具权限边界
argument-hint: "..."             # 调用提示
---
```

`description` 同时服务于两种激活路径：

1. **被动发现（默认）**：技能元数据渲染进系统提示词的技能区块，模型按语义自主选用；
2. **斜杠激活**：用户输入 `/batch-screening ...` 时强制加载该技能正文，仅当轮生效。

### 4.2 模板文件的作用

`templates/*.md` 是技能包的一部分，运行在沙箱中的 Agent 可用文件工具读取模板后按结构产出。把"输出长什么样"从模型的自由发挥变成**固定契约**，不同候选人/批次的报告格式一致，可直接被下游（HR、CSV 流水线）消费。

### 4.3 权限隔离

- Lead Agent 的 `skills` 白名单在沙箱文件系统层再做一次投影（projection）：即使技能目录存在，不在白名单内的也不会投影进该会话沙箱；
- 技能的 `allowed-tools` 是动态收紧的：技能激活期间，脚本只能用声明的工具。

## 5. MCP 数据通道

### 5.1 为什么是 MCP

MCP（Model Context Protocol）是"模型 ↔ 外部系统"的标准工具协议，本项目通过 stdio 传输接入官方 `mcp-server-sqlite`：

- Gateway 启动/首跑时以子进程方式拉起 server，完成 `initialize` + `tools/list` 握手；
- 发现的工具加服务名前缀注入工具注册表：`candidate-db_read_query`、`candidate-db_write_query`、`candidate-db_create_table`、`candidate-db_list_tables`、`candidate-db_describe_table`、`candidate-db_append_insight`；
- 模型按工具 JSON Schema 生成**结构化调用参数**（而非自由文本 SQL 拼接后走 shell），Gateway 代理执行并回传结果。

### 5.2 路由与安全

- `routing.keywords`（入库、SQL、统计、聚合……）+ `mode: prefer` 让工具检索在相关意图下优先暴露数据库工具，无关对话不占用上下文；
- `mcp_plugins: ["candidate-db"]` 在智能体级做了插件白名单：该 Agent 只能看到这一个 MCP 来源的工具；
- 子进程以最小环境变量启动（注入 uv 缓存目录与镜像，不继承宿主密钥类环境变量）；
- 数据库表刻意不设计联系方式列，落实数据最小化。

### 5.3 已踩过的坑（真实记录）

- PyPI 上的 `mcp-server-sqlite` 与最新版 `mcp` SDK 存在 API 漂移：新版本移除了其使用的 `Server.list_resources` 装饰器，server 启动即 `AttributeError`。解决方案是 `uvx --with mcp==1.2.1 mcp-server-sqlite` 锁定兼容版本，已固化在配置中。
- Windows 下 stdio MCP 的 `command` 必须是可执行文件绝对路径（`uvx` 不在 GUI 进程的 PATH 上）；JSON 配置中的反斜杠需双写。

## 6. 状态与数据边界

| 数据 | 存储位置 | 是否跨会话 |
|---|---|---|
| 智能体 / 技能定义 | 用户空间文件 | 持久（文件即配置） |
| 对话线程与产物 | `.deer-flow/users/{uid}/threads/` | 持久 |
| 候选人结构化档案 | `candidates.db` | 持久（显式入库才写） |
| 长期记忆 facts | 本智能体已关闭（`memory_enabled: false`） | 否 |
| 简历原文 | 不上传数据库、不进记忆 | 仅会话内 |

## 7. 可演进方向

- **知识库（RAG）**：接入岗位画像库/历史面评库，匹配时引入历史录用样本；
- **多智能体协作**：lead（简历筛选）+ subagent（背调话术/薪酬分析），通过 `allowed_subagents` 编排；
- **渠道化**：接入飞书机器人，HR 在群里转发简历文件即触发分析；
- **离线批处理**：用 MCP 任务契约（submit/status/cancel）支持大批量简历的异步评分；
- **评估体系**：建立标注好的简历-JD 评分集，回归评估每次 Prompt/模型变更。
