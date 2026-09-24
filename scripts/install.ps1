<#
.SYNOPSIS
    将 resume-agent（人设 + 3 个 Skill + candidate-db MCP）一键安装到本地 DeerFlow 实例。

.DESCRIPTION
    1. 复制 persona/SOUL.md、config/agent.config.yaml 到用户空间 agents/resume/
    2. 复制 skills/* 到用户空间 skills/custom/
    3. 合并 candidate-db MCP 配置到 deer-flow 根目录 extensions_config.json（自动写入本机绝对路径）
    4. 创建 candidates.db 并初始化表结构（优先 sqlite3，回退 Python）
    5. 提示开启 agents_api 与重启 Gateway

.PARAMETER DeerFlowRoot
    deer-flow 项目根目录（含 backend/、config.yaml）。默认尝试脚本所在盘的常见目录。

.PARAMETER UserId
    DeerFlow 用户 ID（backend/.deer-flow/users/ 下的目录名）。不指定时若只有一个用户则自动选择。

.EXAMPLE
    .\scripts\install.ps1 -DeerFlowRoot "D:\deer-flow"
#>
[CmdletBinding()]
param(
    [string]$DeerFlowRoot = "d:\ROG魔霸新锐\Documents\deepflow\deer-flow",
    [string]$UserId = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Assert-Path($path, $label) {
    if (-not (Test-Path $path)) { throw "$label 不存在：$path" }
}

Assert-Path $DeerFlowRoot "DeerFlow 根目录"
Assert-Path (Join-Path $DeerFlowRoot "backend") "DeerFlow backend 目录"

# --- 1. 定位用户空间 ---
$usersDir = Join-Path $DeerFlowRoot "backend\.deer-flow\users"
Assert-Path $usersDir "用户空间目录（请确认 DeerFlow 已初始化并创建过管理员账号）"

if (-not $UserId) {
    $userDirs = Get-ChildItem $usersDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "memory.json") }
    if ($userDirs.Count -eq 1) { $UserId = $userDirs[0].Name }
    else { throw "无法自动确定用户 ID，请用 -UserId 指定。候选：$((Get-ChildItem $usersDir -Directory).Name -join ', ')" }
}
$userHome = Join-Path $usersDir $UserId
Assert-Path $userHome "用户目录"
Write-Host "[1/4] 目标用户：$UserId" -ForegroundColor Cyan

# --- 2. 复制 Agent 与 Skill ---
$agentDir = Join-Path $userHome "agents\resume"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
Copy-Item (Join-Path $ProjectRoot "persona\SOUL.md") (Join-Path $agentDir "SOUL.md") -Force
Copy-Item (Join-Path $ProjectRoot "config\agent.config.yaml") (Join-Path $agentDir "config.yaml") -Force

$customSkillsDir = Join-Path $userHome "skills\custom"
New-Item -ItemType Directory -Force -Path $customSkillsDir | Out-Null
Copy-Item (Join-Path $ProjectRoot "skills\*") $customSkillsDir -Recurse -Force
Write-Host "[2/4] Agent 与 3 个 Skill 已复制" -ForegroundColor Cyan

# --- 3. 合并 MCP 配置 ---
$extPath = Join-Path $DeerFlowRoot "extensions_config.json"
$ext = if (Test-Path $extPath) { Get-Content $extPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{ middlewares = @(); mcpServers = [pscustomobject]@{}; skills = [pscustomobject]@{} } }
if (-not $ext.mcpServers) { $ext | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force }
if (-not $ext.skills) { $ext | Add-Member -NotePropertyName skills -NotePropertyValue ([pscustomobject]@{}) -Force }

$dbPath = (Join-Path $DeerFlowRoot "backend\.deer-flow\data\candidates.db") -replace '\\', '\\'
$dataDir = Join-Path $DeerFlowRoot "backend\.deer-flow\data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$uvx = (Get-Command uvx.exe -ErrorAction SilentlyContinue)
$uvxCmd = if ($uvx) { $uvx.Source } else { Join-Path $env:USERPROFILE ".local\bin\uvx.exe" }

$mcpServer = [ordered]@{
    enabled             = $true
    type                = "stdio"
    command             = $uvxCmd
    args                = @("--with", "mcp==1.2.1", "mcp-server-sqlite", "--db-path", (Join-Path $DeerFlowRoot "backend\.deer-flow\data\candidates.db"))
    cwd                 = Join-Path $DeerFlowRoot "backend"
    env                 = [ordered]@{}
    tool_name_prefix    = $true
    session_init_timeout = 120
    tool_call_timeout    = 60
    description          = "本地 SQLite 候选人库：批量简历的结构化档案入库、SQL 聚合查询与跨批次对比"
    capability           = [ordered]@{ id = "candidate-db" }
    routing              = [ordered]@{ mode = "prefer"; priority = 60; keywords = @("数据库", "SQL", "入库", "存到数据库", "统计", "聚合", "候选人查询", "批次对比") }
}
$ext.mcpServers | Add-Member -NotePropertyName "candidate-db" -NotePropertyValue ([pscustomobject]$mcpServer) -Force
foreach ($s in @("candidate-report", "batch-screening", "interview-prep")) {
    $ext.skills | Add-Member -NotePropertyName $s -NotePropertyValue ([pscustomobject]@{ enabled = $true }) -Force
}
# 用 .NET 写 UTF-8 无 BOM（PS 5.1 的 Set-Content -Encoding UTF8 会带 BOM，导致 Python json 解析失败）
$jsonOut = $ext | ConvertTo-Json -Depth 12
[System.IO.File]::WriteAllText($extPath, $jsonOut, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[3/4] extensions_config.json 已合并 candidate-db（command=$uvxCmd）" -ForegroundColor Cyan

# --- 4. 初始化数据库 ---
$dbFile = Join-Path $dataDir "candidates.db"
$schema = Join-Path $ProjectRoot "integrations\candidate-db\schema.sql"
$sqlite = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
if ($sqlite) {
    Get-Content $schema -Raw | & $sqlite.Source $dbFile
} else {
    $py = @'
import pathlib, sqlite3, sys
db, schema = sys.argv[1], sys.argv[2]
sql = pathlib.Path(schema).read_text(encoding="utf-8")
con = sqlite3.connect(db)
con.executescript(sql)
con.commit()
con.close()
print("db initialized:", db)
'@
    $tmpPy = Join-Path $env:TEMP "_resume_agent_init_db.py"
    Set-Content -Path $tmpPy -Value $py -Encoding UTF8
    $uv = Join-Path $env:USERPROFILE ".local\bin\uv.exe"
    if (Test-Path $uv) { & $uv run --no-sync python $tmpPy $dbFile $schema } else { python $tmpPy $dbFile $schema }
}
Write-Host "[4/4] candidates.db 已就绪" -ForegroundColor Cyan

Write-Host ""
Write-Host "安装完成。剩余两步：" -ForegroundColor Green
Write-Host "  1) 确认 $DeerFlowRoot\config.yaml 中 agents_api.enabled = true"
Write-Host "  2) 重启 Gateway（新会话选择「简历分析助手」即可）"
