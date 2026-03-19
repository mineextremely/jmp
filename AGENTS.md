# JMP 项目上下文文档

## 项目概述

JMP（Java Manage PowerShell）是一个用 PowerShell 编写的 Java 版本管理工具，专门用于在 Windows 系统上快速切换和管理多个 Java 安装版本。它类似于 jenv 或 sdkman，但专门为 Windows 环境优化。

**技术栈**：
- **语言**：PowerShell 5.1+
- **平台**：Windows
- **架构**：模块化设计（命令层、核心层、功能层）
- **数据存储**：JSON 配置文件

**核心特性**：
- 多种扫描策略（Everything ES、fd 工具、fallback）
- 自动下载并安装 fd 工具以提升扫描速度
- 智能供应商识别（支持 Temurin、Zulu、Oracle、GraalVM、Liberica、Corretto、Microsoft 等）
- 版本快速切换（会话级和持久化）
- 版本模糊匹配
- 供应商优先级配置
- 兼容 PowerShell 5.1 和 PowerShell 7+

## 项目结构

```
jmp/
├── jmp.bat                    # Windows 批处理启动器
├── jmp.ps1                    # PowerShell 主入口脚本
├── config/
│   └── vendor-priority.json   # 供应商优先级配置
├── src/
│   ├── commands/              # 命令实现层
│   │   ├── Invoke-Current.ps1 # 显示当前 Java 版本
│   │   ├── Invoke-Help.ps1    # 显示帮助信息
│   │   ├── Invoke-List.ps1    # 列出所有 Java 安装
│   │   ├── Invoke-Pin.ps1     # 固定 Java 版本到环境变量
│   │   ├── Invoke-Scan.ps1    # 扫描 Java 安装
│   │   ├── Invoke-Unpin.ps1   # 移除固定的 Java 版本
│   │   ├── Invoke-Unuse.ps1   # 清除当前会话的 Java 设置
│   │   ├── Invoke-Use.ps1     # 切换 Java 版本
│   │   └── Invoke-Version.ps1 # 显示版本信息
│   ├── core/                  # 核心模块
│   │   ├── Args.ps1           # 参数解析
│   │   ├── Bootstrap.ps1      # 模块加载引导
│   │   ├── Context.ps1        # 上下文对象工厂
│   │   └── Version.ps1        # 版本显示工具
│   ├── env/                   # 环境相关
│   │   └── Set.ps1            # 环境变量设置
│   ├── io/                    # 输入输出
│   │   └── Log.ps1            # 日志输出工具
│   ├── java/                  # Java 相关功能
│   │   ├── Find.ps1           # Java 查找函数
│   │   ├── Match.ps1          # 版本匹配函数
│   │   ├── Scanner.ps1        # Java 扫描函数（三种扫描策略）
│   │   └── Vendor.ps1         # 供应商检测
│   └── util/                  # 工具函数
│       └── Fs.ps1             # 文件系统工具（JSON 读写）
└── java-versions.json         # 扫描结果缓存（运行时生成）
```

## 构建和运行

### 安装

1. 克隆仓库：
```bash
git clone https://github.com/mineextremely/jmp.git
cd jmp
```

2. 将项目目录添加到系统 PATH 环境变量，或直接运行 `jmp.bat`

### 基本使用

```bash
# 扫描系统中的 Java 安装
jmp scan

# 列出所有已发现的 Java 安装
jmp list

# 切换到 Java 17（使用优先级最高的供应商）
jmp use 17

# 切换到 Temurin 版本的 Java 17
jmp use 17 temurin

# 清除当前会话的 Java 设置
jmp unuse

# 固定 Java 21 到用户环境
jmp pin 21

# 固定到系统环境（需要管理员权限）
jmp pin 21 system

# 显示当前激活的 Java 版本
jmp current

# 显示版本信息
jmp version

# 显示帮助
jmp help
```

### 调试模式

使用 `-debug` 参数启用调试输出：
```bash
jmp -debug scan
```

### 扫描模式

```bash
# 自动模式（默认）：优先 ES，然后 fd，最后 fallback
jmp scan

# 跳过 ES，尝试 fd 或 fallback
jmp scan -fallback 1

# 直接使用 fallback
jmp scan -fallback 2
```

## 开发规范

### 命名约定

- **函数命名**：PascalCase，动词-名词格式
  - 命令层：`Invoke-CommandName`（如 `Invoke-Scan`、`Invoke-Use`）
  - 功能层：`Action-Noun`（如 `Parse-JavaVersion`、`Detect-Vendor`）

- **变量命名**：PascalCase（如 `$ScriptRoot`、`$EnableDebug`）

- **文件命名**：
  - 命令层：`Invoke-CommandName.ps1`（如 `Invoke-Scan.ps1`）
  - 核心层：`ModuleName.ps1`（如 `Scanner.ps1`、`Vendor.ps1`）

### 文件编码

- 所有 `.ps1` 文件使用 UTF-8 编码
- 配置文件使用 UTF-8 编码

### 代码组织

- **Bootstrap.ps1**：自动加载 `src/` 目录下所有 `.ps1` 文件（排除自身）
- **Context**：使用哈希表传递上下文信息，包含 `Args`、`Debug`、`FallbackMode` 等
- **模块加载**：通过 `.` 运算符导入脚本，确保函数可用性

### 调试支持

- 使用 `$Global:JmpDebug` 全局变量控制调试输出
- 使用 `Log-Debug` 函数输出调试信息
- 调试模式通过 `-debug` 参数启用

## 核心架构

### 扫描策略

JMP 支持三种扫描策略，按优先级自动降级：

1. **Everything (ES)**：
   - 最快的扫描方式
   - 需要 Everything 服务正常运行
   - 通过 `es -json -count 1000 -full-path-and-name -name java.exe` 搜索

2. **fd 工具**：
   - 快速文件搜索工具
   - 如果不存在会自动询问用户是否下载
   - 逐盘搜索所有驱动器

3. **Fallback 扫描**：
   - 扫描常见 Java 安装目录：
     - `$env:ProgramFiles\Java`
     - `$env:ProgramFiles(x86)\Java`
     - `$env:LOCALAPPDATA\Programs\Java`
     - `$env:USERPROFILE\.jdks`
   - 检查 PATH 中的 java.exe

### 版本匹配

支持多种版本格式的匹配：
- 标准格式：`17.0.17`
- Java 8 特殊格式：`1.8.0_472`
- 两段格式：`17.0`
- 单段格式：`17`

支持模糊匹配，例如输入 `17` 可以匹配所有 17.x.x 版本。

### 供应商识别

通过检测 `JAVA_HOME` 目录名称和 `release` 文件自动识别供应商：
- Temurin (Eclipse Adoptium)
- Zulu (Azul Systems)
- Oracle (Oracle JDK)
- GraalVM
- Liberica (BellSoft)
- Corretto (Amazon)
- Microsoft (Microsoft OpenJDK)
- Unknown (其他供应商)

### 供应商优先级

通过 `config/vendor-priority.json` 配置供应商优先级：
```json
{
  "priority": ["temurin", "zulu", "oracle", "graalvm", "unknown"]
}
```

当用户不指定供应商时，JMP 会按此优先级自动选择。

### 环境变量管理

- **use 命令**：修改当前 PowerShell 会话的 `JAVA_HOME` 和 `PATH`
- **pin 命令**：持久化到用户或系统环境变量（需要管理员权限）
- **unpin 命令**：移除持久化的环境变量
- **unuse 命令**：清除当前会话的 Java 设置

## 关键文件说明

### 入口文件

- **jmp.bat**：批处理启动器，调用 PowerShell 执行 `jmp.ps1`
- **jmp.ps1**：主入口脚本，解析参数并分发到对应命令

### 核心模块

- **Bootstrap.ps1**：自动加载所有源文件，建立运行时环境
- **Context.ps1**：创建上下文对象的工厂函数
- **Args.ps1**：参数解析逻辑

### 命令实现

所有命令位于 `src/commands/` 目录，遵循 `Invoke-CommandName.ps1` 命名规范：
- `Invoke-Scan.ps1`：扫描 Java 安装
- `Invoke-List.ps1`：列出所有 Java 安装
- `Invoke-Use.ps1`：切换 Java 版本
- `Invoke-Unuse.ps1`：清除当前会话设置
- `Invoke-Pin.ps1`：固定 Java 版本
- `Invoke-Unpin.ps1`：移除固定设置
- `Invoke-Current.ps1`：显示当前版本
- `Invoke-Version.ps1`：显示 JMP 版本
- `Invoke-Help.ps1`：显示帮助信息

### Java 功能模块

- **Scanner.ps1**：实现三种扫描策略（ES、fd、fallback）
- **Vendor.ps1**：供应商检测逻辑
- **Match.ps1**：版本匹配逻辑
- **Find.ps1**：Java 查找辅助函数

### 工具模块

- **Log.ps1**：日志输出函数（`Log-Debug`、`Write-Info`、`Write-Success`、`Write-Warning`、`Write-ErrorMsg`）
- **Fs.ps1**：文件系统操作（JSON 读写）
- **Set.ps1**：环境变量设置

## 常见操作

### 添加新的命令

1. 在 `src/commands/` 创建 `Invoke-NewCommand.ps1`
2. 实现函数 `function Invoke-NewCommand { param($Ctx) ... }`
3. 在 `jmp.ps1` 中添加命令分发逻辑
4. 在 `Invoke-Help.ps1` 中添加帮助信息

### 添加新的供应商

在 `src/java/Vendor.ps1` 的 `Detect-Vendor` 函数中添加新的供应商检测逻辑。

### 修改扫描策略

在 `src/java/Scanner.ps1` 中修改对应的扫描函数：
- `Scan-Java-WithES`：Everything 扫描
- `Scan-Java-WithFD`：fd 工具扫描
- `Scan-Java-Fallback`：fallback 扫描

## 注意事项

1. **环境变量作用域**：
   - `use` 命令：仅当前会话有效
   - `pin` 命令：持久化到用户或系统环境

2. **权限要求**：
   - 系统级 `pin` 和 `unpin` 操作需要管理员权限

3. **PowerShell 版本**：
   - 支持 PowerShell 5.1 和 PowerShell 7+
   - 使用 `Expand-Archive` 需要 PowerShell 5.1+

4. **依赖工具**：
   - Everything (ES)：可选，提供最快的扫描速度
   - fd：可选，可自动下载，提供快速扫描

5. **文件编码**：
   - 所有脚本使用 UTF-8 编码
   - 确保编辑器以 UTF-8 保存文件

## 版本信息

当前版本：v1.1.2

### 主要更新日志

- v1.1.2：修复 ES 扫描功能，提升扫描稳定性
- v1.1.1：重构文件命名，优化帮助信息，修复环境变量设置
- v1.1.0：新增 `pin`、`unpin`、`unuse` 命令
- v1.0.0：初始版本，实现三种扫描策略和基本功能

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！