# Release Strategy

This document explains how AzerothCore RealmMaster releases work and what they contain.

## Release Philosophy

Since **Docker images are stored on Docker Hub**, GitHub releases serve as **deployment packages** rather than source distributions. Each release contains everything users need to deploy pre-built images without building from source.

## What's in a Release?

### Release Assets (ZIP Archive)

Each release includes a downloadable `.zip` file containing:

```
azerothcore-realmmaster-v1.0.0-realmmaster.zip
├── .env.prebuilt              # Pre-configured for Docker Hub images
├── docker-compose.yml         # Service definitions
├── deploy.sh                  # Deployment script
├── status.sh                  # Status monitoring
├── cleanup.sh                 # Cleanup utilities
├── scripts/                   # Required Python/Bash scripts
├── config/                    # Module manifest and presets
├── docs/                      # Complete documentation
├── QUICKSTART.md             # Release-specific quick start
└── README.md                 # Project overview
```

### Release Notes

Each release includes:
- Module profile and count
- Docker Hub image tags (date-specific and latest)
- Quick start instructions
- Complete module list
- Build information (commit, date, source variant)
- Links to documentation
- Known issues

## Release Types

### 1. Profile-Based Releases

Each module profile gets its own release variant:

- **v1.0.0-realmmaster** - RealmMaster profile (32 modules, recommended)
- **v1.0.0-suggested-modules** - Alternative suggested module set
- **v1.0.0-all-modules** - All supported modules
- **v1.0.0-playerbots-only** - Just playerbots

Users choose the release that matches their desired module set.

### 2. Version Numbering

We use semantic versioning:
- **Major** (v1.0.0 → v2.0.0): Breaking changes, major feature additions
- **Minor** (v1.0.0 → v1.1.0): New modules, feature enhancements
- **Patch** (v1.0.0 → v1.0.1): Bug fixes, documentation updates

## Docker Hub Image Tags

Releases reference specific Docker Hub tags:

### Date-Tagged Images (Recommended for Production)
```
uprightbass360/azerothcore-realmmaster:authserver-realmmaster-20260109
uprightbass360/azerothcore-realmmaster:worldserver-realmmaster-20260109
```
- **Immutable**: Never change
- **Stable**: Guaranteed to match the release
- **Recommended**: For production deployments

### Latest Tags (Auto-Updated)
```
uprightbass360/azerothcore-realmmaster:authserver-realmmaster-latest
uprightbass360/azerothcore-realmmaster:worldserver-realmmaster-latest
```
- **Mutable**: Updated nightly by CI/CD
- **Convenient**: Always get the newest build
- **Use case**: Development, testing, staying current

## Creating a Release

### Automated (Recommended)

Use the GitHub Actions workflow:

1. Go to **Actions** → **Create Release**
2. Click **Run workflow**
3. Fill in:
   - **Version**: `v1.0.0`
   - **Profile**: `RealmMaster` (or other profile)
   - **Pre-release**: Check if beta/RC
4. Click **Run workflow**

The workflow automatically:
- Creates deployment package with all files
- Generates release notes with module list
- Uploads ZIP archive as release asset
- Creates GitHub release with proper tags

### Manual

If you need to create a release manually:

```bash
# 1. Tag the release
git tag -a v1.0.0 -m "Release v1.0.0 - RealmMaster Profile"
git push origin v1.0.0

# 2. Create deployment package
./scripts/create-release-package.sh v1.0.0 RealmMaster

# 3. Create GitHub release
# Go to GitHub → Releases → Draft a new release
# - Tag: v1.0.0
# - Title: RealmMaster v1.0.0 - RealmMaster Profile
# - Upload: azerothcore-realmmaster-v1.0.0-realmmaster.zip
# - Add release notes
```

## Release Checklist

Before creating a release:

- [ ] Verify CI/CD build succeeded
- [ ] Test Docker Hub images work correctly
- [ ] Update CHANGELOG.md
- [ ] Update version in documentation if needed
- [ ] Verify all module SQL migrations are included
- [ ] Test deployment on clean system
- [ ] Update known issues section

## For Users: Using a Release

### Quick Start

```bash
# 1. Download release
wget https://github.com/uprightbass360/AzerothCore-RealmMaster/releases/download/v1.0.0/azerothcore-realmmaster-v1.0.0-realmmaster.zip

# 2. Extract
unzip azerothcore-realmmaster-v1.0.0-realmmaster.zip
cd azerothcore-realmmaster-v1.0.0-realmmaster

# 3. Configure
nano .env.prebuilt
# Set: DOCKERHUB_USERNAME=uprightbass360

# 4. Deploy
mv .env.prebuilt .env
./deploy.sh
```

### Upgrading Between Releases

```bash
# 1. Backup your data
./scripts/bash/backup.sh

# 2. Download new release
wget https://github.com/.../releases/download/v1.1.0/...

# 3. Extract to new directory
unzip azerothcore-realmmaster-v1.1.0-realmmaster.zip

# 4. Copy your .env and data
cp old-version/.env new-version/.env
cp -r old-version/storage new-version/storage

# 5. Deploy new version
cd new-version
./deploy.sh
```

## Release Schedule

- **Nightly Builds**: Images built automatically at 2 AM UTC
- **Releases**: Created as needed when significant changes accumulate
- **LTS Releases**: Planned quarterly for long-term support

## Support

- **Release Issues**: https://github.com/uprightbass360/AzerothCore-RealmMaster/issues
- **Documentation**: Included in each release ZIP
- **Discord**: https://discord.gg/gkt4y2x

## FAQ

### Why are images on Docker Hub and not in releases?

Docker images can be 1-2GB each. GitHub has a 2GB file limit and releases should be lightweight. Docker Hub is designed for hosting images, GitHub releases are for deployment packages.

### Can I use latest tags in production?

We recommend **date-tagged images** for production (e.g., `authserver-realmmaster-20260109`). Latest tags are updated nightly and may have untested changes.

### How do I know which image version a release uses?

Check the release notes - they include the specific Docker Hub tags (date-stamped) that were tested with that release.

### What if I want to build from source instead?

Clone the repository and use `./setup.sh` + `./build.sh` instead of using pre-built releases. See [GETTING_STARTED.md](GETTING_STARTED.md) for instructions.

### Are releases required?

No! You can:
1. **Use releases**: Download ZIP, deploy pre-built images (easiest)
2. **Use nightly images**: Pull latest tags directly from Docker Hub
3. **Build from source**: Clone repo, build locally (most flexible)

Releases are just convenient snapshots for users who want stability.
