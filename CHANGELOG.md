# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.1.0] - 2024-11-18

### 🎉 Major Features
- **macOS Compatibility**: Full support for macOS systems with BSD tools
- **Cross-Platform Installer**: New `install-security-hooks-macos.sh` for macOS-specific installation
- **Enhanced Testing**: Comprehensive testing suite with `test-macos-compatibility.sh`

### ✨ Added
- macOS system detection in all security scripts
- BSD tools compatibility (grep, sed, xargs) alongside GNU tools
- macOS-specific installation script with system verification
- Comprehensive troubleshooting guide (`MACOS_TROUBLESHOOTING.md`)
- Cross-platform testing and validation scripts
- Enhanced documentation with macOS-specific instructions

### 🔧 Improved
- **Cross-platform compatibility**: Scripts now work seamlessly on macOS, Linux, and Windows
- **Error handling**: Better error messages and debugging information for macOS
- **Documentation**: Updated README with detailed macOS setup instructions
- **Hook installation**: More robust pre-commit and post-commit hook setup

### 🐛 Fixed
- xargs compatibility issues between BSD (macOS) and GNU (Linux) versions
- grep pattern matching differences between systems
- Path handling and normalization across different operating systems
- Script execution permissions and shell compatibility

### 📚 Documentation
- Added comprehensive macOS troubleshooting guide
- Updated README with platform-specific installation instructions
- Enhanced configuration examples for different environments
- Added testing and validation procedures

---

## [v1.0.7] - 2024-11-15

### 🔧 Improved
- Enhanced PowerShell compatibility for Windows environments
- Better error handling and output formatting for Windows terminals
- Improved cross-platform script execution

### 🐛 Fixed
- PowerShell-specific output issues
- Windows terminal compatibility problems
- Script exit code handling in Windows environments

---

## [v1.0.6] - 2024-11-14

### 🎉 Major Features
- Comprehensive Windows compatibility improvements
- Enhanced PowerShell support
- Better cross-platform error handling

### ✨ Added
- Windows system detection and optimization
- PowerShell-specific output handling
- Improved terminal compatibility

### 🔧 Improved
- Script execution reliability across platforms
- Error reporting and debugging information
- Output formatting consistency

---

## [v1.0.5] - 2024-11-13

### 🔧 Improved
- Pre-commit hook reliability and error handling
- Better integration with Git workflow
- Enhanced script execution feedback

### 🐛 Fixed
- Hook installation and execution issues
- Error propagation in pre-commit workflows
- Script permission and accessibility problems

---

## [v1.0.4] - 2024-11-12

### ✨ Added
- Enhanced syntax error reporting with line numbers
- Improved debugging capabilities
- Better error context and suggestions

### 🔧 Improved
- Error message clarity and actionability
- Development workflow integration
- Code quality feedback

---

## [v1.0.0 - v1.0.3] - 2024-11-01 to 2024-11-11

### 🎉 Initial Release Features
- Core security scanning functionality
- Secrets detection with comprehensive patterns
- URL hardcoding verification
- Dependency vulnerability scanning
- Git hooks integration
- Configurable security policies

### 🛡️ Security Features
- Detection of API keys, tokens, and credentials
- Private key and certificate scanning
- Environment file validation
- High-entropy string detection
- Custom pattern matching

### 🔧 Core Functionality
- Pre-commit hook integration
- Post-commit notifications and reporting
- Configurable exclude patterns
- Multi-language support (JS, TS, Python, etc.)
- Cross-platform basic compatibility

---

## Migration Guide

### Upgrading to v1.1.0 from v1.0.x

If you're using these hooks on **macOS**, we highly recommend upgrading to v1.1.0 for the best experience:

```bash
# Update to latest version
git fetch --tags
git checkout v1.1.0

# For macOS users - use the new installer
./install-security-hooks-macos.sh

# For other platforms - continue using
./install-security-hooks.sh
```

### New macOS Users

```bash
# Clone the repository
git clone https://github.com/your-repo/security-hooks-repo.git
cd security-hooks-repo
git checkout v1.1.0

# Use macOS-specific installer
./install-security-hooks-macos.sh

# Test compatibility
./test-macos-compatibility.sh
```

### Configuration Updates

No breaking changes to configuration files. Existing `.security-config.yml` files remain compatible.

---

## Support

- **Issues**: Report bugs and request features via GitHub Issues
- **Documentation**: See README.md and MACOS_TROUBLESHOOTING.md
- **Testing**: Use provided test scripts to validate your setup

## Contributing

See our contributing guidelines and feel free to submit pull requests for improvements and bug fixes.