-- 候选人库表结构（candidate-db MCP Server 使用）
-- 初始化：sqlite3 .deer-flow/data/candidates.db < mcp/schema.sql
-- 刻意不包含手机号/邮箱等敏感联系信息列：隐私最小化，联系动作留在 HR 侧系统完成。

CREATE TABLE IF NOT EXISTS candidates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,                  -- 候选人姓名
  job_position TEXT,                   -- 目标岗位 / 批次名称
  education TEXT,                      -- 最高学历
  years_experience REAL,               -- 总工作年限
  latest_company TEXT,                 -- 最近一家公司
  latest_title TEXT,                   -- 最近职位
  core_skills TEXT,                    -- 核心技能（JSON 数组字符串）
  score_skills REAL,                   -- 技能匹配 0-100（权重 35%）
  score_experience REAL,               -- 经验匹配 0-100（权重 25%）
  score_project REAL,                  -- 项目匹配 0-100（权重 25%）
  score_stability REAL,                -- 稳定性/成长 0-100（权重 15%）
  score_total REAL,                    -- 综合得分
  tier TEXT CHECK(tier IN ('A','B','C')), -- A 优先面试 / B 可面 / C 待观察
  highlights TEXT,                     -- 亮点（结构化评估结论）
  concerns TEXT,                       -- 疑点与建议核实项
  source_file TEXT,                    -- 简历来源文件名
  created_at TEXT DEFAULT (datetime('now','localtime'))
);

-- 常用聚合查询示例（Agent 通过 MCP read_query 工具自主执行）：
-- SELECT tier, COUNT(*) FROM candidates WHERE job_position='高级前端' GROUP BY tier;
-- SELECT education, COUNT(*) FROM candidates GROUP BY education;
-- SELECT ROUND(AVG(years_experience),1) FROM candidates WHERE job_position='高级前端';
-- SELECT name, score_total FROM candidates ORDER BY score_total DESC LIMIT 5;
