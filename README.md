# JMP (Java Manage PowerShell)

一个用 PowerShell 编写的 Java 版本管理工具，用于在 Windows 系统上快速切换和管理多个 Java 安装版本。

## 功能特性

- **多种扫描策略**：支持 Everything (ES)、fd 工具、常见目录扫描三种模式
- **自动下载工具**：自动下载并安装 fd 工具以提升扫描速度
- **智能供应商识别**：自动识别 Java 发行版供应商（Temurin、Zulu、Oracle、GraalVM、Liberica、Corretto 等）
- **版本切换**：快速切换到指定的 Java 版本和供应商
- **持久化固定**：支持将 Java 版本持久化固定到用户或系统环境
- **版本模糊匹配**：支持多种版本格式和模糊匹配
- **供应商优先级**：支持配置不同供应商的优先级
- **跨版本兼容**：兼容 PowerShell 5.1 和 PowerShell 7+

## 技术栈

- **语言**：PowerShell 5.1+
- **平台**：Windows
- **架构**：模块化设计
- **数据存储**：JSON

## 快速开始

### 安装

1. 克隆仓库：
```bash
git clone https://github.com/mineextremely/jmp.git
cd jmp
```

2. 将项目目录添加到系统 PATH 环境变量，或直接使用批处理文件运行

### 使用

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

# 固定 Temurin Java 21 到系统环境（需要管理员权限）
jmp pin 21 temurin system

# 移除用户环境的固定设置
jmp unpin

# 移除系统环境的固定设置（需要管理员权限）
jmp unpin system

# 显示当前激活的 Java 版本
jmp current

# 显示 JMP 版本信息
jmp version

# 显示帮助信息
jmp help
```

## 命令说明

### scan

扫描系统中的 Java 安装，支持三种模式：

- **自动模式（默认）**：优先使用 Everything (ES)，失败后尝试 fd，最后使用常见目录扫描
- **-fallback 1**：跳过 Everything，尝试使用 fd，失败后使用常见目录扫描
- **-fallback 2**：直接使用常见目录扫描

```bash
jmp scan                    # 自动扫描
jmp scan -fallback 1        # 跳过 ES，使用 fd 或 fallback
jmp scan -fallback 2        # 直接使用 fallback 扫描
jmp scan -debug             # 启用调试输出
```

**扫描策略说明**：

1. **Everything (ES)**：最快的扫描方式，需要 Everything 服务正常运行
2. **fd 工具**：快速文件搜索工具，如果不存在会自动询问是否下载
3. **Fallback 扫描**：扫描常见 Java 安装目录和 PATH

### list

列出所有已发现的 Java 安装，按版本号排序

```bash
jmp list
```

输出示例：
```
version   vendor   name                              source
-------   ------   ----                              ------
1.8.0_451 oracle   jdk-8u451                         es
1.8.0_472 temurin  jdk8u472-b08                      es
17.0.17   temurin  jdk-17.0.17+10                    es
21.0.9    temurin  jdk-21.0.9+10                     es
25.0.1    zulu     zulu25.30.17-ca-jdk25.0.1-win_x64 es
```

### use

切换到指定的 Java 版本（仅当前会话有效）

```bash
jmp use 17                  # 切换到 Java 17（使用优先级最高的供应商）
jmp use 17 temurin          # 切换到 Temurin 版本的 Java 17
jmp use 8                   # 切换到 Java 8
```

### unuse

清除当前会话的 Java 设置

```bash
jmp unuse                   # 清除当前会话的 JAVA_HOME 和 PATH 中的 Java 路径
```

### pin

持久化固定 Java 版本到用户或系统环境

```bash
jmp pin 21                  # 固定 Java 21 到用户环境（默认）
jmp pin 21 user            # 固定 Java 21 到用户环境
jmp pin 21 system          # 固定 Java 21 到系统环境（需要管理员权限）
jmp pin 21 temurin         # 固定 Temurin Java 21 到用户环境
jmp pin 21 temurin system  # 固定 Temurin Java 21 到系统环境
```

**说明**：
- `pin` 命令会将 Java 版本持久化到环境变量，新打开的终端会话会自动使用该版本
- 系统级设置需要管理员权限
- 更改会在新终端会话中生效

### unpin

移除持久化的 Java 设置

```bash
jmp unpin                   # 移除用户环境的固定设置
jmp unpin user             # 移除用户环境的固定设置
jmp unpin system           # 移除系统环境的固定设置（需要管理员权限）
```

### current

显示当前激活的 JAVA_HOME 和 Java 版本

```bash
jmp current
```

### version

显示 JMP 版本信息

```bash
jmp version
```

### help

显示帮助信息

```bash
jmp help
```

## 配置

### 供应商优先级

编辑 `config/vendor-priority.json` 文件来定义供应商优先级：

```json
{
  "priority": ["temurin", "zulu", "oracle", "graalvm", "unknown"]
}
```

当不指定供应商时，JMP 会按此优先级自动选择。

## 项目结构

```
jmp/
├── jmp.bat                    # Windows 批处理启动器
├── jmp.ps1                    # 主入口脚本
├── config/
│   └── vendor-priority.json   # 供应商优先级配置
├── src/
│   ├── commands/              # 命令实现模块
│   │   ├── Current.ps1        # 显示当前 Java 版本
│   │   ├── Help.ps1           # 显示帮助信息
│   │   ├── List.ps1           # 列出所有 Java 安装
│   │   ├── Pin.ps1            # 固定 Java 版本
│   │   ├── Scan.ps1           # 扫描 Java 安装
│   │   ├── Unpin.ps1          # 移除固定的 Java 版本
│   │   ├── Unuse.ps1          # 清除当前会话的 Java 设置
│   │   ├── Use.ps1            # 切换 Java 版本
│   │   └── Version.ps1        # 显示版本信息
│   ├── core/                  # 核心模块
│   │   ├── Args.ps1           # 参数解析
│   │   ├── Bootstrap.ps1      # 模块加载引导
│   │   ├── Context.ps1        # 上下文对象
│   │   └── Version.ps1        # 版本显示工具
│   ├── env/                   # 环境相关
│   │   └── Set.ps1            # 环境变量设置
│   ├── io/
│   │   └── Log.ps1            # 日志输出
│   ├── java/                  # Java 相关功能
│   │   ├── Find.ps1           # Java 查找函数
│   │   ├── Match.ps1          # 版本匹配函数
│   │   ├── Scan.ps1           # Java 扫描函数
│   │   └── Vendor.ps1         # 供应商检测
│   └── util/
│       └── Fs.ps1             # 文件系统工具（JSON 读写）
└── java-versions.json         # 扫描结果缓存（运行时生成）
```

## 支持的供应商

JMP 支持以下 Java 发行版供应商的自动识别：

- **Temurin** (Eclipse Adoptium)
- **Zulu** (Azul Systems)
- **Oracle** (Oracle JDK)
- **GraalVM**
- **Liberica** (BellSoft)
- **Corretto** (Amazon)
- **Microsoft** (Microsoft OpenJDK)
- **Unknown** (其他供应商)

## 版本匹配

JMP 支持多种版本格式的匹配：

- 标准格式：`17.0.17`
- Java 8 特殊格式：`1.8.0_472`
- 两段格式：`17.0`
- 单段格式：`17`

支持模糊匹配，例如输入 `17` 可以匹配所有 17.x.x 版本。

## 工具下载

### fd 工具

JMP 支持自动下载 fd 工具以提升扫描速度：

- 下载源优先级：jsDelivr CDN → ghproxy → GitHub 原始链接
- 自动解压并安装到项目根目录
- 支持用户选择是否下载

## 注意事项

1. **环境变量作用域**：
   - `use` 命令修改的环境变量仅在当前 PowerShell 会话中有效
   - `pin` 命令会将环境变量持久化到用户或系统环境，新终端会话会自动使用该版本
2. **Everything 服务**：ES 服务需要正常运行才能使用 Everything 搜索功能
3. **PowerShell 版本**：支持 PowerShell 5.1 和 PowerShell 7+
4. **文件编码**：所有 PowerShell 脚本使用 UTF-8 编码
5. **管理员权限**：系统级 `pin` 和 `unpin` 操作需要管理员权限

## 开发

### 代码规范

- **函数命名**：使用 PascalCase，动词-名词格式（如 `Invoke-Scan`、`Parse-JavaVersion`）
- **变量命名**：使用 PascalCase（如 `$ScriptRoot`、`$EnableDebug`）
- **文件命名**：
  - 命令层：使用 `Invoke-` 前缀（如 `Invoke-Scan.ps1`）
  - 核心层：使用 PascalCase（如 `Scanner.ps1`、`Vendor.ps1`）
- **文件编码**：所有 .ps1 文件使用 UTF-8 编码

### 调试模式

使用 `-debug` 参数启用调试输出：

```bash
jmp -debug scan
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v1.1.1

- ✅ 重构文件命名：commands 层文件统一使用 `Invoke-` 前缀
- ✅ 重构文件命名：java 层的 `Scan.ps1` 重命名为 `Scanner.ps1`
- ✅ 优化帮助信息：简化 `jmp help` 输出，为 `jmp use` 添加详细帮助
- ✅ 修复环境变量设置：修复 `pin` 和 `unpin` 命令的 EnvironmentVariableTarget 枚举值错误
- ✅ 改进用户体验：命令帮助信息更加平衡和清晰

### v1.1.0

- ✅ 新增 `pin` 命令：持久化固定 Java 版本到用户或系统环境
- ✅ 新增 `unpin` 命令：移除持久化的 Java 设置
- ✅ 新增 `unuse` 命令：清除当前会话的 Java 设置
- ✅ 支持用户级和系统级环境变量设置
- ✅ 系统级设置需要管理员权限验证
- ✅ 自动移除旧的 Java bin 路径，避免 PATH 污染
- ✅ 通知系统环境变量已更改（仅系统级）

### v1.0.0

- ✅ 实现三种扫描策略（Everything、fd、fallback）
- ✅ 自动下载 fd 工具
- ✅ 智能供应商识别（支持 7+ 种供应商）
- ✅ 版本模糊匹配
- ✅ 供应商优先级配置
- ✅ PowerShell 5.1 和 7+ 兼容
- ✅ 模块化架构设计