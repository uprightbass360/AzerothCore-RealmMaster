# CI/CD Documentation

This document describes the continuous integration and deployment workflows configured for the AzerothCore RealmMaster project.

## Build and Publish Workflow

The `build-and-publish.yml` workflow automatically builds AzerothCore with your configured modules and publishes Docker images to Docker Hub.

### Trigger Schedule

- **Nightly builds**: Runs automatically at 2 AM UTC every day
- **Manual trigger**: Can be triggered manually via GitHub Actions UI with optional force rebuild

### What It Does

1. **Checks out the repository** - Gets the RealmMaster project code
2. **Sets up Git** - Configures git for module repository cloning
3. **Sets up Docker Buildx** - Enables optimized Docker builds
4. **Logs in to Docker Hub** - Authenticates for image publishing
5. **Prepares the build environment**:
   - Runs `./setup.sh --non-interactive --module-config RealmMaster --force`
   - Uses the same setup process as local builds (ensures consistency)
   - Applies the **RealmMaster module profile** from `config/module-profiles/RealmMaster.json`
   - Creates `.env` with proper paths and configured modules (32 modules)
   - Automatically selects correct source variant (standard or playerbots)
6. **Caches build artifacts** to speed up subsequent builds:
   - Go build cache (`.gocache`)
   - Source repository (`local-storage/source`)
7. **Sets up Python 3.11** - Required for module management scripts
8. **Runs `./build.sh --yes`** - This is where the magic happens:
   - **Step 1**: Sets up the AzerothCore source repository
   - **Step 2**: Detects build requirements
   - **Step 3**: Syncs module metadata
   - **Step 4**: **Fetches all module repositories** - Automatically clones all 32 enabled module repos from GitHub
   - **Step 5**: **Compiles AzerothCore** with all fetched modules integrated
   - **Step 6**: Tags the compiled images
9. **Tags images for Docker Hub** - Prepares `latest` and date-based tags
10. **Pushes images to Docker Hub** - Publishes the built images
11. **Generates a build summary** - Shows enabled modules and published images

### Module Fetching Process

The workflow **automatically fetches all module repositories** during the build. Here's how it works:

- The `build.sh` script reads the enabled modules from `.env` (set by the RealmMaster profile)
- For each enabled module, it clones the repository from GitHub (all modules are public repos)
- Module repositories are cloned into the AzerothCore source tree under `modules/`
- Examples of fetched repositories:
  - `mod-playerbots` from https://github.com/mod-playerbots/mod-playerbots.git
  - `mod-transmog` from https://github.com/azerothcore/mod-transmog.git
  - `mod-solo-lfg` from https://github.com/azerothcore/mod-solo-lfg.git
  - ...and 29 more

**No manual module setup required!** The build process handles everything automatically.

### Published Images

The workflow publishes images with **profile-specific tags** so you know exactly which modules are included:

**Profile-Tagged Images** (recommended):
- `<dockerhub-username>/azerothcore-realmmaster:authserver-realmmaster-latest` ✅ Built nightly
- `<dockerhub-username>/azerothcore-realmmaster:authserver-realmmaster-YYYYMMDD` ✅ Built nightly
- `<dockerhub-username>/azerothcore-realmmaster:worldserver-realmmaster-latest` ✅ Built nightly
- `<dockerhub-username>/azerothcore-realmmaster:worldserver-realmmaster-YYYYMMDD` ✅ Built nightly

**Generic Tags** (backward compatibility, defaults to RealmMaster profile):
- `<dockerhub-username>/azerothcore-realmmaster:authserver-latest` ✅ Built nightly
- `<dockerhub-username>/azerothcore-realmmaster:worldserver-latest` ✅ Built nightly

**Other Profile Tags** (built on-demand via manual workflow trigger):
- `authserver-suggested-modules-latest` - Available when built
- `authserver-all-modules-latest` - Available when built
- `authserver-playerbots-only-latest` - Available when built

**Note**: Only the RealmMaster profile is built automatically on schedule. Other profiles can be built by manually triggering the workflow with different profile names.

## Required GitHub Secrets

To enable the build and publish workflow, you must configure the following secrets in your GitHub repository:

### Setting Up Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add the following secrets:

#### DOCKERHUB_USERNAME

Your Docker Hub username.

**Example**: `yourusername`

#### DOCKERHUB_TOKEN

A Docker Hub access token (recommended) or your Docker Hub password.

**How to create a Docker Hub access token**:

1. Log in to [Docker Hub](https://hub.docker.com/)
2. Click on your username in the top right → **Account Settings**
3. Go to **Security** → **Personal Access Tokens** → **Generate New Token**
4. Give it a description (e.g., "GitHub Actions")
5. Set permissions: **Read & Write**
6. Click **Generate**
7. Copy the token (you won't be able to see it again)
8. Add this token as the `DOCKERHUB_TOKEN` secret in GitHub

## Module Configuration

### Default Profile: RealmMaster

The workflow uses the **RealmMaster** module profile by default, which includes 32 carefully selected modules:

- MODULE_PLAYERBOTS - AI-controlled player characters
- MODULE_TRANSMOG - Transmogrification system
- MODULE_SOLO_LFG - Solo dungeon finder
- MODULE_NPC_BUFFER - Buff NPC
- MODULE_ELUNA - Lua scripting engine
- MODULE_AIO - All-in-one interface
- ...and 26 more modules

See the full list in `config/module-profiles/RealmMaster.json`.

### Customizing the Module Profile

To use a different module profile in the CI/CD workflow:

1. **Choose or create a profile** in `config/module-profiles/`:
   - `RealmMaster.json` - Default (32 modules)
   - `suggested-modules.json` - Alternative suggested set
   - `playerbots-only.json` - Just playerbots
   - `all-modules.json` - All supported modules
   - Create your own JSON file

2. **Edit the workflow** at `.github/workflows/build-and-publish.yml`:

   ```yaml
   # Change this line in the "Prepare build environment" step:
   python3 scripts/python/apply_module_profile.py RealmMaster \

   # To use a different profile:
   python3 scripts/python/apply_module_profile.py suggested-modules \
   ```

3. **Update the build summary** (optional):
   ```yaml
   # Change this line in the "Build summary" step:
   echo "- **Module Profile**: RealmMaster" >> $GITHUB_STEP_SUMMARY

   # To:
   echo "- **Module Profile**: suggested-modules" >> $GITHUB_STEP_SUMMARY
   ```

### Testing Module Profiles Locally

You can test the module profile script locally before committing:

```bash
# List modules that will be enabled
python3 scripts/python/apply_module_profile.py RealmMaster --list-modules

# Apply a profile to create .env
python3 scripts/python/apply_module_profile.py RealmMaster

# Verify the result
grep '^MODULE_.*=1' .env | wc -l
```

## Cache Strategy

The workflow uses GitHub Actions cache to speed up builds:

- **Go build cache**: Cached in `.gocache` directory
- **Source repository**: Cached in `local-storage/source` directory

This significantly reduces build times for subsequent runs.

## Manual Workflow Trigger

To manually trigger the workflow:

1. Go to **Actions** tab in your GitHub repository
2. Click on **Build and Publish** workflow
3. Click **Run workflow**
4. **Choose module profile** (default: RealmMaster):
   - Enter profile name (e.g., `RealmMaster`, `suggested-modules`, `all-modules`, `playerbots-only`)
   - Profile must exist in `config/module-profiles/`
5. Optionally check **Force rebuild** to rebuild even if no changes detected
6. Click **Run workflow**

The workflow will build with the selected profile and tag images accordingly (e.g., `authserver-realmmaster-latest` for RealmMaster profile).

## Troubleshooting

### Build fails with "missing required command"

The workflow runs on Ubuntu and has Docker and Python 3.11 pre-installed. If you see missing command errors, ensure the build script dependencies are available.

### Authentication errors

If you see Docker Hub authentication errors:

- Verify `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets are set correctly
- Ensure the Docker Hub token has **Read & Write** permissions
- Check that the token hasn't expired

### Build timeout

The workflow has a 120-minute timeout. If builds consistently exceed this:

- Consider optimizing the build process
- Check if all module sources are accessible
- Review cache effectiveness

## Using Pre-Built Images

After images are published to Docker Hub, users can deploy RealmMaster **without building locally**!

### For End Users

See the complete guide at **[docs/PREBUILT_IMAGES.md](PREBUILT_IMAGES.md)** for step-by-step instructions.

**Quick start for users**:

```bash
# Clone the repository
git clone https://github.com/uprightbass360/AzerothCore-RealmMaster.git
cd AzerothCore-RealmMaster

# Use pre-built configuration
cp .env.prebuilt .env

# Edit .env and set DOCKERHUB_USERNAME=your-dockerhub-username

# Deploy (no build required!)
./deploy.sh
```

### For Developers

To test the published images:

```bash
# Pull latest RealmMaster profile images
docker pull <dockerhub-username>/azerothcore-realmmaster:authserver-realmmaster-latest
docker pull <dockerhub-username>/azerothcore-realmmaster:worldserver-realmmaster-latest

# Or pull specific date-tagged images
docker pull <dockerhub-username>/azerothcore-realmmaster:authserver-realmmaster-20260109
docker pull <dockerhub-username>/azerothcore-realmmaster:worldserver-realmmaster-20260109

# Or use generic latest tags (defaults to RealmMaster profile)
docker pull <dockerhub-username>/azerothcore-realmmaster:authserver-latest
docker pull <dockerhub-username>/azerothcore-realmmaster:worldserver-latest
```

### Pre-Built Configuration File

The `.env.prebuilt` template provides a minimal configuration that:
- References Docker Hub images instead of local builds
- Removes all build-related variables
- Includes only runtime configuration
- Is ready to use with minimal editing (just set DOCKERHUB_USERNAME)

**Benefits of pre-built images**:
- ✅ Skip 15-45 minute build time
- ✅ No build dependencies required
- ✅ Same 32 RealmMaster modules included
- ✅ Automatic nightly updates available
- ✅ Date-tagged versions for stability
- ✅ Profile-tagged images for clear identification

## Building Multiple Profiles

You can build different module profiles by manually triggering the workflow:

### Example: Build All Modules Profile

1. Go to **Actions** → **Build and Publish**
2. Click **Run workflow**
3. Set **module_profile** to `all-modules`
4. Click **Run workflow**

This will create:
- `authserver-all-modules-latest`
- `authserver-all-modules-YYYYMMDD`
- `worldserver-all-modules-latest`
- `worldserver-all-modules-YYYYMMDD`

### Creating Custom Profile Builds

To build a custom profile:

1. **Create profile JSON** in `config/module-profiles/my-custom-profile.json`:
   ```json
   {
     "modules": [
       "MODULE_PLAYERBOTS",
       "MODULE_TRANSMOG",
       "MODULE_SOLO_LFG"
     ],
     "label": "My Custom Profile",
     "description": "Custom module selection",
     "order": 100
   }
   ```

2. **Trigger workflow** with profile name `my-custom-profile`

3. **Images created**:
   - `authserver-my-custom-profile-latest`
   - `worldserver-my-custom-profile-latest`

### Scheduled Builds

The nightly scheduled build always uses the **RealmMaster** profile. To schedule builds for different profiles, you can:

1. Create additional workflow files (e.g., `.github/workflows/build-all-modules.yml`)
2. Set different cron schedules
3. Hardcode the profile name in the workflow
