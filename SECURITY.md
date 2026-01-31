# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in DroboBridge, please report it responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly at ryan@robworks.info
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

You should receive a response within 48 hours. We take all security reports seriously.

## Security Design Principles

DroboBridge is designed with data safety as the primary concern:

### What DroboBridge NEVER Does

- **Never** formats, erases, or initializes disks
- **Never** modifies partition tables
- **Never** modifies filesystem structures
- **Never** writes to volumes without explicit user consent
- **Never** executes commands without SafetyGuard validation

### What DroboBridge ALWAYS Does

- **Always** mounts volumes in read-only mode by default
- **Always** requires explicit confirmation for write operations
- **Always** requires explicit confirmation for delete operations
- **Always** validates commands before execution
- **Always** logs significant operations via audit log

### Mount Safety

- Default mount mode is READ-ONLY
- Read-write mounting requires:
  1. Paragon extFS installed
  2. User explicitly selecting "Read-Write" mode
  3. User clicking "Mount" to confirm

### File Operation Safety

All file operations go through `SafetyGuard` which:

- Validates the volume is mounted read-write
- Ensures the target path is within the mounted volume
- Logs all operations for audit purposes
- Prevents operations on system directories

### Privilege Escalation

- The app requests only necessary permissions
- Full Disk Access may be required for ext4fuse (read-only fallback)
- No admin password required when using Paragon extFS

## Known Limitations

- DroboBridge cannot verify the integrity of data on Drobo devices
- DroboBridge does not implement BeyondRAID and cannot recover from disk failures
- Always maintain independent backups of important data

## Third-Party Dependencies

- **ZIPFoundation** - For diagnostic export (MIT License)
- **macFUSE** - Optional, for ext4fuse support (BSD License)
- **Paragon extFS** - Optional, commercial software for read-write ext3/ext4

We regularly review dependencies for known vulnerabilities.
