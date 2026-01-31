# Contributing to DroboBridge

Thank you for your interest in contributing to DroboBridge! This project helps legacy Drobo owners continue using their devices with modern macOS.

## How to Contribute

### Reporting Bugs

1. **Check existing issues** - Search [GitHub Issues](https://github.com/ringo380/DroboBridge/issues) to avoid duplicates
2. **Use the bug report template** - Fill out all required sections
3. **Include diagnostics** - Export a diagnostic bundle from the app (Diagnostics → Export)
4. **Describe the environment** - macOS version, Drobo model, filesystem type

### Suggesting Features

1. **Open a feature request issue** - Use the feature request template
2. **Explain the use case** - Why would this be helpful for Drobo users?
3. **Consider scope** - DroboBridge focuses on mounting and file access, not RAID management

### Submitting Code

1. **Fork the repository**
2. **Create a feature branch** - `git checkout -b feature/your-feature-name`
3. **Follow the code style** - Match existing patterns in the codebase
4. **Add tests** - Cover new functionality with unit tests
5. **Update documentation** - Update README if adding user-facing features
6. **Submit a pull request** - Use the PR template

## Development Setup

### Prerequisites

- macOS 13.0+ (Ventura or later)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (recommended)

### Building from Source

```bash
# Clone your fork
git clone https://github.com/ringo380/DroboBridge.git
cd DroboBridge

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme DroboBridge -configuration Debug build

# Or open in Xcode
open DroboBridge.xcodeproj
```

### Running Tests

```bash
swift test
# or
xcodebuild test -scheme DroboBridge -destination 'platform=macOS'
```

## Code Guidelines

### Swift Style

- Use Swift 5.9+ features where appropriate
- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation comments for public APIs

### Architecture

- **Models** - Data structures, keep logic minimal
- **Services** - Business logic, I/O operations
- **Views** - SwiftUI views, presentation only
- **State** - Observable coordinators for app state

### Safety First

DroboBridge is designed to be safe by default:

- **Never** add code that formats or erases disks
- **Always** validate operations through `SafetyGuard`
- **Default** to read-only operations
- **Require** explicit user confirmation for destructive actions
- **Log** all significant operations via audit log

### Commit Messages

Use clear, descriptive commit messages:

```
feat: Add drive bay visualization to Overview tab

- Create DriveBayView with 5-slot layout
- Add LED color indicators for drive status
- Integrate into OverviewTab
```

Prefixes:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code restructuring
- `test:` - Adding tests
- `chore:` - Build/tooling changes

## Testing with Hardware

If you have a Drobo device:

1. **Test mounting** - Verify mount/unmount works correctly
2. **Test file operations** - Only on non-critical data!
3. **Test diagnostics** - Ensure diagnostic export captures useful info
4. **Report Drobo model** - Different models may have quirks

## Questions?

- Open a [Discussion](https://github.com/ringo380/DroboBridge/discussions)
- Tag your issue with `question` label

## License

By contributing to DroboBridge, you agree that your contributions will be licensed under the MIT License.
