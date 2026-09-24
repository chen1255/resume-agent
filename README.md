# ResumeAgent · 智能简历筛选助手

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一套面向 **HR 招聘场景**的垂直 Agent 资产包：结构化简历解析、JD 量化匹配评分、多候选人批量横向对比、标准化评估报告 / 面试题包生成，并通过 **MCP 协议**操作本地候选人数据库完成聚合分析。

`Prompt Engineering · Skill 设计 · MCP · SQLite · LangGraph · FastAPI · Next.js`

> **项目边界（先说清楚）**：本仓库是一套**独立设计的 Agent 应用资产**——人设、技能包、数据库通道、评分流程、安装脚本均为本项目原创；Agent 运行时（LangGraph 引擎、沙箱、Web 控制台）通过安装脚本部署到开源框架 [DeerFlow](https://github.com/bytedance/deer-flow) 上运行，仓库本身不包含、也未派生 DeerFlow 的任何源码。

---

## 演示路径（5 分钟）

> 截图 / GIF 占位（放到 `assets/` 后在此引用）：`01-report.png`、`02-batch.png`、`03-mcp-sql.png`、`04-interview.png`

仓库自带 [examples/](examples/) 演示材料（**全部为虚构人物**）：1 份高级前端 JD + 3 份拉开差距的简历（强匹配 / 跨栈转型 / 存疑包装）。安装后按以下顺序体验：

1. **单人评估**：上传 `简历1-林昭.md` + 粘贴 JD → 得到结构化档案、JD 逐项匹配、四维评分、亮点与建议核实项；
2. **批量筛选**：一次提供 3 份简历 + JD → 统一标准评分总表、A/B/C 分层、批次统计，可导出 CSV；
3. **MCP 数据库分析**：输入"把这批候选人入库，统计学历分布和平均年限"→ Agent 自主调用 SQLite MCP 工具执行 SQL；
4. **面试题包**：输入"给 A 类候选人出一份 60 分钟一面题包"→ 四类题目，每题带考察点、期望/危险信号与评分锚点。

---

## 能力一览

| 能力 | 实现方式 | 关键约束 |
|---|---|---|
| 简历解析与结构化档案 | 人设 + `candidate-report` 技能 | 缺失字段标"未提供"，禁止臆造；事实/推断分离标注 |
| JD 量化匹配 | 技能内固定评分模型 | 技能 35% / 经验 25% / 项目 25% / 稳定性 15%，每项给分必须引用简历依据 |
| 批量横向对比 | `batch-screening` 技能 | 所有候选人同一权重表；硬门槛只标"存疑"不自动淘汰；可导出 CSV |
| 面试题生成 | `interview-prep` 技能 | 疑点追问 / 硬技能 / 场景题 / STAR 行为题四类，含 1-5 分评分锚点 |
| 结构化数据入库与聚合 | candidate-db（MCP / SQLite） | 参数化工具调用 + 智能体级插件白名单；敏感联系信息不建表 |
| 隐私保护 | 配置与技能双重约束 | 默认关闭长期记忆；禁止性别/年龄/籍贯/婚育等无关维度评分 |

---

## 仓库结构

```
resume-agent/
├── persona/
│   └── SOUL.md                    智能体人设：身份 / 能力 / 行为边界 / 语气 / 准则优先级
├── config/
│   └── agent.config.yaml          能力配置：工具组、技能白名单、MCP 绑定、记忆开关
├── skills/                        可复用技能包（目录名即技能名，含输出模板）
│   ├── candidate-report/          单候选人标准化评估
│   ├── batch-screening/           批量筛选 / 横向对比 / 分层 / CSV 导出
│   └── interview-prep/            结构化面试题包与评分表
├── integrations/candidate-db/
│   ├── mcp.example.json           MCP Server 配置模板
│   └── schema.sql                 candidates 表结构与常用查询
├── examples/                      开箱即用的虚构演示材料
│   ├── JD-高级前端工程师.md
│   └── resumes/（3 份）
├── scripts/
│   └── install.ps1                一键部署到本地 DeerFlow 实例（复制/合并/建库全自动）
├── docs/
│   ├── architecture.md            架构、加载机制与真实踩坑记录
│   └── interview-qa.md            面试 14 问参考回答
└── assets/                        演示截图位
```

三层行为塑造：**SOUL.md 决定"我是谁、边界在哪"；Skill 决定"专业动作的标准流程与输出契约"；MCP 决定"能连通什么外部系统"**。详见 [docs/architecture.md](docs/architecture.md)。

---

## 安装

### 前置条件

- 已部署 DeerFlow（Python 3.12+ / uv / Node 22+ / pnpm），且已在 Web 控制台创建管理员账号
- LLM API Key（OpenAI 兼容，DeepSeek / OpenAI 等均可）
- `uvx`（随 uv 安装）

### 方式一：一键脚本（Windows PowerShell）

```powershell
git clone https://github.com/chen1255/resume-agent.git
cd resume-agent
# 将 -DeerFlowRoot 改为你的 deer-flow 目录
.\scripts\install.ps1 -DeerFlowRoot "D:\path\to\deer-flow"
```

脚本自动完成：复制人设与技能 → 合并 MCP 配置（自动写本机路径）→ 创建并初始化 `candidates.db`。完成后确认 `config.yaml` 中 `agents_api.enabled: true` 并重启 Gateway。

### 方式二：手工安装

1. `persona/SOUL.md` 与 `config/agent.config.yaml` → `backend/.deer-flow/users/{你的用户ID}/agents/resume/`（配置文件重命名为 `config.yaml`）；
2. `skills/*` → `backend/.deer-flow/users/{你的用户ID}/skills/custom/`；
3. `sqlite3 backend/.deer-flow/data/candidates.db < integrations/candidate-db/schema.sql`；
4. 参照 [integrations/candidate-db/mcp.example.json](integrations/candidate-db/mcp.example.json) 合并 deer-flow 根目录 `extensions_config.json`，修改 `--db-path` 为本机绝对路径；
5. 重启 Gateway，新建会话选择「**简历分析助手**」。

> 平台备注：`mcp-server-sqlite` 需锁 `mcp==1.2.1`（新版 SDK API 漂移会导致旧 server 启动报 `AttributeError`），脚本与模板均已处理。

---

## 设计取舍

1. **证据绑定而非自由打分**——Skill 强制每个评分附简历原文依据 + 事实/推断标注，让结论可被 HR 审计，幻觉一眼可见；
2. **分层建议而非自动淘汰**——Agent 定位是分析工具，A/B/C 分层 + 置信度辅助人工，是刻意的 Human-in-the-loop 设计；
3. **MCP 而非放开 Shell**——数据库操作收敛在带 Schema、白名单、路由前缀的结构化工具里，攻击面远小于命令执行；
4. **数据最小化**——关闭长期记忆防止候选人信息跨会话泄漏，联系方式等敏感列不建表。

更多机制与踩坑见 [docs/architecture.md](docs/architecture.md)；面试可能被追问的问题见 [docs/interview-qa.md](docs/interview-qa.md)。

## License

[MIT](LICENSE)
