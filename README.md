# DroboBridge

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

A full-featured macOS application for managing Drobo DAS (Direct Attached Storage) devices, with support for Linux filesystems (ext3/ext4) and comprehensive file browsing capabilities.

> **Note**: Drobo, Inc. ceased operations in 2023. This tool helps legacy Drobo owners continue using their devices with modern macOS.

![DroboBridge Overview](docs/images/screenshot-placeholder.png)

## Features

### Device Management
- **USB Device Detection** - Real-time monitoring of Drobo connect/disconnect via IOKit
- **Volume Enumeration** - Automatic discovery of all partitions via DiskArbitration
- **Storage Visibility Tracking** - Visual progression from USB → Block Device → Volume → Mounted

### Linux Filesystem Support
- **Paragon extFS Integration** - Native read-write mounting for ext3/ext4 filesystems
- **ext4fuse Fallback** - Read-only mounting when Paragon isn't available
- **Automatic Detection** - Identifies the best available driver automatically

### Storage Visualization
- **Capacity Overview** - Progress bars showing used/free space with color-coded warnings
- **Drive Bay View** - Visual representation of Drobo's 5-bay physical layout
- **Pie Chart Breakdown** - Donut chart showing volume distribution

### File Browser
- **Full Navigation** - Browse folders with breadcrumb navigation, back/forward/up
- **Search** - Find files by name within mounted volumes
- **Quick Look** - Preview files using macOS Quick Look
- **File Operations** (when mounted read-write):
  - Copy files to Drobo (drag & drop supported)
  - Delete files and folders
  - Rename files and folders
  - Create new folders
- **Reveal in Finder** - Open any file location in Finder

### Diagnostics
- **System Analysis** - Collects diskutil output and system logs
- **Issue Detection** - Identifies common problems with recommendations
- **Export Bundle** - Creates timestamped ZIP files for troubleshooting

## Safety First

DroboBridge is designed with data safety as the primary concern:

- **NEVER** formats, erases, or initializes disks
- **NEVER** modifies partition tables or filesystem structures
- **ALWAYS** mounts volumes in read-only mode by default
- **ALWAYS** validates commands before execution
- **ALWAYS** requires explicit confirmation for write operations

### "Initialize Disk" Warning

If macOS shows an "Initialize Disk" dialog when you connect your Drobo:

1. **Click "Ignore" or "Eject"**
2. **NEVER click "Initialize"** - this will erase all your data
3. Use DroboBridge to mount the volume safely

## Requirements

- **macOS 13.0** (Ventura) or later
- **Xcode 15.0** or later (for building from source)

### For Linux Filesystem Support

Choose one of the following:

| Option | Access | Cost | Notes |
|--------|--------|------|-------|
| **Paragon extFS** | Read-Write | $39 | Recommended - native macOS integration |
| **ext4fuse + macFUSE** | Read-Only | Free | Requires kernel extension approval |

## Installation

### Download Release

Download the latest release from the [Releases](https://github.com/ringo380/DroboBridge/releases) page.

### Build from Source

#### Using XcodeGen (Recommended)

```bash
# Clone the repository
git clone https://github.com/ringo380/DroboBridge.git
cd DroboBridge

# Generate Xcode project
xcodegen generate

# Build with Xcode
xcodebuild -scheme DroboBridge -configuration Release build
```

#### Using Swift Package Manager

```bash
cd DroboBridge
swift build -c release
```

## Usage

### 1. Connect Your Drobo

Connect your Drobo via USB and launch DroboBridge.

### 2. Check Overview Tab

- Verify connection status shows "Drobo Connected"
- Review storage visualization and drive bay status
- Check for any warnings or issues

### 3. Mount Volumes

Go to the **Volumes** tab:
- Select a volume from the list
- Choose mount mode:
  - **Read-Only** (default, safe) - Green indicator
  - **Read-Write** (requires Paragon) - Blue indicator
- Click Mount

### 4. Browse Files

Go to the **Files** tab:
- Select a mounted volume from the sidebar
- Navigate folders, search for files
- Use context menu for file operations
- Drag & drop files to copy (when mounted R/W)

### 5. Run Diagnostics

If you encounter issues:
- Go to **Diagnostics** tab
- Click "Run Diagnostics"
- Export the bundle for troubleshooting

## Project Structure

```
DroboBridge/
├── Sources/
│   ├── App/                        # App entry point
│   ├── Models/                     # Data models
│   │   ├── USBDevice.swift
│   │   ├── BlockDevice.swift
│   │   ├── VolumeInfo.swift
│   │   └── ...
│   ├── Services/                   # Core services
│   │   ├── DroboDeviceWatcher.swift    # USB monitoring
│   │   ├── DiskCorrelator.swift        # Device correlation
│   │   ├── MountController.swift       # Mount operations
│   │   ├── Ext4FuseController.swift    # Linux FS support
│   │   ├── FileOperationsService.swift # File operations
│   │   └── SafetyGuard.swift           # Safety validation
│   ├── State/
│   │   └── DroboStorageCoordinator.swift
│   ├── Views/
│   │   ├── Overview/               # Overview tab
│   │   ├── Mount/                  # Volumes tab
│   │   ├── FileBrowser/            # Files tab
│   │   ├── Diagnostics/            # Diagnostics tab
│   │   └── Visualization/          # Charts and visualizations
│   └── Utilities/
│       └── Errors.swift
├── Tests/                          # Unit tests
├── Package.swift                   # SPM manifest
├── project.yml                     # XcodeGen spec
└── DroboBridge.entitlements
```

## Troubleshooting

### Drobo Not Detected

1. Check USB cable and try a different port
2. Avoid USB hubs - connect directly to Mac
3. Check Drobo power and LED status
4. Wait 60+ seconds for Drobo initialization

### Volumes Won't Mount

1. **ext4 filesystem**: Install Paragon extFS or ext4fuse
2. **"Unsupported filesystem"**: Check Diagnostics tab for details
3. **Permission denied**: Grant Full Disk Access in System Settings

### ext4fuse Issues

```bash
# Install macFUSE first
brew install macfuse

# Then install ext4fuse
brew install gromgit/fuse/ext4fuse-mac

# Restart Mac and approve kernel extension in:
# System Settings → Privacy & Security
```

### Export for Support

1. Run Diagnostics
2. Click "Export" and save the ZIP file
3. The bundle contains only system info, no personal data

## Limitations

- **macOS only** - Requires macOS 13+ with IOKit and DiskArbitration
- **No BeyondRAID manipulation** - Cannot reconstruct arrays from individual disks
- **No firmware updates** - Use Drobo Dashboard for firmware management
- **Drobo-specific** - Designed for Drobo devices, may work with other USB storage

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [drobo-utils](https://github.com/drobo-utils/drobo-utils) for Linux
- Uses Apple's IOKit and DiskArbitration frameworks
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) for export functionality
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

## Disclaimer

This project is not affiliated with Drobo, Inc. or any of its successors. Use at your own risk. Always maintain backups of important data.
