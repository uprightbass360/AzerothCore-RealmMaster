# AzerothCore Module Management Documentation

This directory contains comprehensive documentation for the AzerothCore automated module management system.

## Documentation Overview

### 📖 [MODULE_MANAGEMENT.md](MODULE_MANAGEMENT.md)
**Complete system guide** covering:
- Architecture overview and components
- Module installation and configuration
- Database integration and SQL execution
- Rebuild detection and automation
- Usage examples and troubleshooting

### 📋 [MODULE_COMPATIBILITY.md](MODULE_COMPATIBILITY.md)
**Module compatibility matrix** including:
- Status of all 28 analyzed modules
- Known issues and compatibility notes
- Testing procedures and best practices
- Troubleshooting guide for specific modules

## Quick Start

### 1. Enable a Module
```bash
# Edit environment file
vim docker-compose-azerothcore-services.env
# Set MODULE_NAME=1

# Rebuild if C++ compilation required
./scripts/rebuild-with-modules.sh

# Restart services
docker compose -f docker-compose-azerothcore-services.yml restart
```

### 2. Check Module Status
```bash
# View current configuration
grep "^MODULE_" docker-compose-azerothcore-services.env

# Check for rebuild requirements
docker compose -f docker-compose-azerothcore-services.yml up ac-modules
```

### 3. Safe Testing Approach
1. Start with all modules disabled (current state)
2. Enable one module at a time
3. Test compilation and functionality
4. Document results in compatibility matrix

## Directory Structure

```
docs/
├── README.md                    # This overview file
├── MODULE_MANAGEMENT.md         # Complete system documentation
└── MODULE_COMPATIBILITY.md      # Module compatibility matrix

scripts/
└── rebuild-with-modules.sh      # Automated rebuild script

docker-compose-azerothcore-services.yml  # Main service configuration
docker-compose-azerothcore-services.env  # Module configuration
```

## System Features

- ✅ **Automatic Module Detection**: Downloads and analyzes all available modules
- ✅ **State Tracking**: Hash-based change detection triggers rebuilds automatically
- ✅ **SQL Integration**: Executes module database scripts automatically
- ✅ **Configuration Management**: Handles .conf file setup
- ✅ **Rebuild Automation**: Complete source-based compilation workflow
- ✅ **Compatibility Analysis**: Documents module requirements and issues

## Support

### For Module-Specific Issues
- Check the compatibility matrix in `MODULE_COMPATIBILITY.md`
- Refer to individual module GitHub repositories
- Test modules incrementally

### For System Issues
- Review `MODULE_MANAGEMENT.md` troubleshooting section
- Check Docker logs: `docker compose logs ac-modules`
- Verify environment configuration

## Contributing

When testing modules:
1. Update compatibility status in `MODULE_COMPATIBILITY.md`
2. Document any special requirements or configuration
3. Report issues to module maintainers
4. Submit pull requests with compatibility findings

---

**Note**: All modules are currently disabled for a stable baseline. Enable and test modules individually to ensure compatibility with your specific AzerothCore setup.