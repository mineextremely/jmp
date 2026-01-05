# JMP Beta3 (Legacy Single-File Version)

**⚠️ This is a legacy version. Please use the latest version from the [master branch](https://github.com/mineextremely/jmp).**

JMP (Java Manage PowerShell) Beta3 is a single-file PowerShell script for managing multiple Java installations on Windows. This version has been archived and replaced by a modular architecture.

## ⚠️ Important Notice

This is the **Beta3** legacy version of JMP. It has been superseded by a newer, modular version with enhanced features:

- ✅ **New Version**: [v1.1.1](https://github.com/mineextremely/jmp/releases) (master branch)
- ❌ **This Version**: Beta3 (archived)

### What's New in v1.1.1?

- **Modular Architecture**: Better code organization and maintainability
- **Enhanced Features**:
  - `pin` command: Persist Java version to user/system environment
  - `unpin` command: Remove persisted Java settings
  - `unuse` command: Clear current session Java settings
  - **Multiple scan strategies**: Everything (ES), fd tool, and fallback scanning
  - **Auto-download**: Automatically download fd tool for faster scanning
- **Better Error Handling**: Improved error messages and debugging
- **More Vendors**: Support for 7+ Java vendors (Temurin, Zulu, Oracle, GraalVM, Liberica, Corretto, Microsoft)

**Please migrate to the latest version for the best experience!**

---

## Legacy Features (Beta3)

### Quick Start

```bash
# Scan for Java installations
jmp scan

# List all discovered Java
jmp list

# Switch to Java 17
jmp use 17

# Switch to Temurin Java 17
jmp use 17 temurin

# Show current Java version
jmp current

# Show JMP version
jmp version
```

### Commands

| Command | Description |
|---------|-------------|
| `scan` | Discover Java installations (ES-first, then fallback) |
| `list` | List all discovered Java installations |
| `use <version> [vendor]` | Switch Java version for current session |
| `current` | Show current JAVA_HOME |
| `version` | Show JMP version |
| `help` | Show this help |

### Supported Vendors

- Temurin (Eclipse Adoptium)
- Zulu (Azul Systems)
- Oracle (Oracle JDK)
- GraalVM

### Requirements

- Windows OS
- PowerShell 5.1+
- Everything (optional, for faster scanning)

### Limitations (Legacy Version)

- Single-file architecture (harder to maintain)
- No persistent Java version management
- No automatic tool downloads
- Limited vendor support
- Basic error handling

## Migration Guide

To migrate from Beta3 to v1.1.1:

1. **Download the latest version**:
   ```bash
   git clone https://github.com/mineextremely/jmp.git
   cd jmp
   git checkout master
   ```

2. **Update your workflow**:
   - Old: `jmp use 21` (session only)
   - New: `jmp use 21` (session) OR `jmp pin 21` (persistent)

3. **Take advantage of new features**:
   - Use `jmp pin` to set a default Java version
   - Use `jmp scan -fallback 1` to skip Everything and use fd
   - Use `-debug` flag for detailed logging

## Version Information

- **Version**: Beta3
- **Status**: ⚠️ Archived / Legacy
- **Last Updated**: 2025
- **Supported**: No (use master branch)

## License

MIT License

---

**For the latest features and updates, please use the [master branch](https://github.com/mineextremely/jmp).**