# Changelog

All notable changes to DroboBridge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-01-31

### Added

#### Device Management
- USB device detection via IOKit with real-time monitoring
- Volume enumeration via DiskArbitration framework
- Storage visibility tracking from USB → Block Device → Volume → Mounted

#### Linux Filesystem Support
- Paragon extFS integration for native read-write ext3/ext4 mounting
- ext4fuse fallback for read-only mounting when Paragon unavailable
- Automatic driver detection and selection

#### Storage Visualization
- Capacity overview with progress bars and color-coded warnings
- Drive bay visualization showing Drobo's 5-bay physical layout
- Donut chart showing volume distribution

#### File Browser
- Full folder navigation with breadcrumb trail
- Back/forward/up navigation history
- File search within mounted volumes
- Quick Look preview integration
- Reveal in Finder functionality
- Context menus for file operations

#### File Operations (Read-Write Mode)
- Copy files to Drobo via drag & drop
- Delete files and folders with confirmation
- Rename files and folders
- Create new folders

#### Diagnostics
- System analysis collecting diskutil output and logs
- Issue detection with recommendations
- Export diagnostic bundle as timestamped ZIP

#### Safety Features
- Read-only mounting by default
- SafetyGuard validation for all operations
- Audit logging of significant actions
- Confirmation dialogs for destructive operations

### Security
- Never formats or erases disks
- Never modifies partition tables
- Validates all commands before execution

---

## Version History

- **1.0.0** - Initial public release with full feature set
