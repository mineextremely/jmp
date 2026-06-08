# 更新日志

### v1.3.0

- ✅ **新增 `info` 命令**：显示 Java 发行版的详细信息（版本、供应商、架构、release 文件、属性等）
- ✅ **新增 `doctor` 命令**：诊断 Java 环境问题，检测缓存时效、PATH 污染、JAVA_HOME 一致性等
- ✅ **新增 `which` 命令**：预览会选中哪个 Java 版本，但不实际切换
- ✅ **新增 `reset` 命令**：一键重置 JMP 到初始状态（清除会话/用户/系统 JAVA_HOME 和缓存）
- ✅ **新增 `--system` 选项**：`reset` 命令支持清除系统环境变量（需要管理员）
- ✅ **新增 `--force` 选项**：`reset` 命令支持跳过确认提示（用于脚本）

### v1.2.1

- ✅ **修复 PATH 清理缺陷**：修复 `use` 连续切换版本时 PATH 累积多个 Java bin 路径的问题
- ✅ **修复 `unuse` PATH 残留**：修复 `unuse` 后 PATH 中残留 Java 父目录路径的问题
- ✅ **清理废弃代码**：移除 ES 时代遗留的 `-fallback`/`FallbackMode` 选项
- ✅ **补全命令路由**：`Invoke-JmpCommand` 补充 `unuse`、`pin`、`unpin` 命令

### v1.2.0

- ✅ **模块化重构**：将 Scanner.ps1 拆分为 5 个功能模块
  - `Network.ps1`：网络检测和 fd 工具下载功能
  - `Fallback.ps1`：PATH 和常见目录扫描
  - `LightScan.ps1`：轻量扫描（注册表、Store、CommonPaths）
  - `BFSScan.ps1`：BFS 深度扫描（广度优先搜索）
  - `FDScan.ps1`：FD 全盘扫描
- ✅ **移除 ES 功能**：删除 Everything (ES) 搜索功能及相关代码
- ✅ **更新扫描策略**：重构为三种扫描模式（light、default、deep）
- ✅ **Bootstrap 改进**：使用 UTF-8 编码加载所有模块
- ✅ **优化代码结构**：提高代码可维护性和可扩展性
- ✅ **改进文档**：更新 README 和项目结构说明

### v1.1.2

- ✅ 修复 JSON 解析问题：正确处理 PowerShell ConvertFrom-Json 返回的数组结构
- ✅ 修复非管理员环境下的扫描问题：`jmp -debug scan` 现在可以正常工作
- ✅ 提升扫描稳定性

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

- ✅ 实现多种扫描策略（注册表、BFS、fd）
- ✅ 自动下载 fd 工具
- ✅ 智能供应商识别（支持 7+ 种供应商）
- ✅ 版本模糊匹配
- ✅ 供应商优先级配置
- ✅ PowerShell 5.1 和 7+ 兼容
- ✅ 模块化架构设计
