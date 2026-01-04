# JMP (Java Manage PowerShell)

一个用 PowerShell 编写的 Java 版本管理工具，用于在 Windows 系统上快速切换和管理多个 Java 安装版本。

## 功能特性

- **扫描 Java 安装**：支持多种扫描策略（Everything 搜索工具、常见目录扫描）
- **列出可用版本**：显示所有已发现的 Java 安装
- **切换 Java 版本**：快速切换到指定的 Java 版本和供应商
- **显示当前版本**：查看当前激活的 JAVA_HOME 和 Java 版本
- **供应商优先级**：支持配置不同供应商的优先级（Temurin、Zulu、Oracle、GraalVM）

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

# 显示当前激活的 Java 版本
jmp current

# 显示 JMP 版本信息
jmp version

# 显示帮助信息
jmp help
```

## 命令说明

### scan

扫描系统中的 Java 安装，支持两种模式：

- **自动模式（默认）**：优先使用 Everything (ES)，失败后使用常见目录扫描
- **-fallback**：直接使用常见目录扫描

```bash
jmp scan                    # 自动扫描
jmp scan -fallback          # 使用 fallback 扫描
```

### list

列出所有已发现的 Java 安装，按版本号排序

```bash
jmp list
```

### use

切换到指定的 Java 版本

```bash
jmp use 17                  # 切换到 Java 17（使用优先级最高的供应商）
jmp use 17 temurin          # 切换到 Temurin 版本的 Java 17
jmp use 8                   # 切换到 Java 8
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
│   │   ├── Scan.ps1           # 扫描 Java 安装
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

- **Temurin** (Adoptium)
- **Zulu**
- **Oracle**
- **GraalVM**
- **Unknown** (其他供应商)

## 版本匹配

JMP 支持多种版本格式的匹配：

- 标准格式：`17.0.17`
- Java 8 特殊格式：`1.8.0_472`
- 两段格式：`17.0`
- 单段格式：`17`

支持模糊匹配，例如输入 `17` 可以匹配所有 17.x.x 版本。

## 注意事项

1. **环境变量作用域**：`jmp.ps1` 修改的环境变量仅在当前 PowerShell 会话中有效
2. **Everything 服务**：ES 服务需要正常运行才能使用 Everything 搜索功能

## 开发

### 代码规范

- **函数命名**：使用 PascalCase，动词-名词格式（如 `Invoke-Scan`、`Parse-JavaVersion`）
- **变量命名**：使用 PascalCase（如 `$ScriptRoot`、`$EnableDebug`）
- **文件命名**：使用 PascalCase（如 `Args.ps1`、`Vendor.ps1`）

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！