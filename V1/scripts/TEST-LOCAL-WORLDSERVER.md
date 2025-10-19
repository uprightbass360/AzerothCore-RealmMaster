# Test Local Worldserver Performance

This test setup allows you to compare the performance of worldserver with game files stored locally within the container vs. external volume mount.

## What This Tests

### 🧪 **Test Configuration**: Local Game Files with NFS Caching
- Game files (maps, vmaps, mmaps, DBC) cached on NFS and copied to local container storage
- **No external volume mount** for `/azerothcore/data` (files stored locally for performance)
- **NFS cache** for downloaded files (persistent across container restarts)
- First run: ~15GB download and extraction time
- Subsequent runs: ~5-10 minutes (extraction only from cache)

### 📊 **Comparison with Standard Configuration**: External Volume
- Game files stored in external volume mount
- Persistent across container restarts
- One-time download, reused across deployments

## Quick Start

### Prerequisites
Make sure the database and authserver are running first:

```bash
# Start database layer
docker-compose --env-file docker-compose-azerothcore-database.env -f docker-compose-azerothcore-database.yml up -d

# Start authserver (minimal requirement)
docker-compose --env-file docker-compose-azerothcore-services.env -f docker-compose-azerothcore-services.yml up -d ac-authserver
```

### Run the Test

```bash
cd scripts

# Start test worldserver (downloads files locally)
./test-local-worldserver.sh

# Monitor logs
./test-local-worldserver.sh --logs

# Cleanup when done
./test-local-worldserver.sh --cleanup
```

## Test Details

### Port Configuration
- **Test Worldserver**: `localhost:8216` (game), `localhost:7779` (SOAP)
- **Regular Worldserver**: `localhost:8215` (game), `localhost:7778` (SOAP)

Both can run simultaneously without conflicts.

### Download Process
The test worldserver will:
1. Check for cached client data in NFS storage
2. If cached: Copy from cache (fast)
3. If not cached: Download ~15GB client data from GitHub releases and cache it
4. Extract maps, vmaps, mmaps, and DBC files to local container storage
5. Verify all required directories exist
6. Start the worldserver

**Expected startup time**:
- First run: 20-30 minutes (download + extraction)
- Subsequent runs: 5-10 minutes (extraction only from cache)

### Storage Locations
- **Game Files**: `/azerothcore/data` (inside container, not mounted - for performance testing)
- **Cache**: External mount at `storage/azerothcore/cache-test/` (persistent across restarts)
- **Config**: External mount (shared with regular deployment)
- **Logs**: External mount at `storage/azerothcore/logs-test/`

## Performance Metrics to Compare

### Startup Time
- **Regular**: ~2-3 minutes (files already extracted in external volume)
- **Test (first run)**: ~20-30 minutes (download + extraction + cache)
- **Test (cached)**: ~5-10 minutes (extraction only from cache)

### Runtime Performance
Compare these during gameplay:
- Map loading times
- Zone transitions
- Server responsiveness
- Memory usage
- CPU utilization

### Storage Usage
- **Regular**: Persistent ~15GB in external volume
- **Test**: ~15GB cache in external volume + ~15GB ephemeral inside container
- **Test Total**: ~30GB during operation (cache + local copy)

## Monitoring Commands

```bash
# Check container status
docker ps | grep test

# Monitor logs
docker logs ac-worldserver-test -f

# Check game data size (local in container)
docker exec ac-worldserver-test du -sh /azerothcore/data/*

# Check cache size (persistent)
ls -la storage/azerothcore/cache-test/
du -sh storage/azerothcore/cache-test/*

# Check cached version
cat storage/azerothcore/cache-test/client-data-version.txt

# Check server processes
docker exec ac-worldserver-test ps aux | grep worldserver

# Monitor resource usage
docker stats ac-worldserver-test
```

## Testing Scenarios

### 1. Startup Performance
```bash
# Time the full startup
time ./test-local-worldserver.sh

# Compare with regular worldserver restart
docker restart ac-worldserver
```

### 2. Runtime Performance
Connect a game client to both servers and compare:
- Zone loading times
- Combat responsiveness
- Large area rendering

### 3. Resource Usage
```bash
# Compare memory usage
docker stats ac-worldserver ac-worldserver-test --no-stream

# Compare disk I/O
docker exec ac-worldserver-test iostat 1 5
docker exec ac-worldserver iostat 1 5
```

## Cleanup

```bash
# Stop and remove test container
./test-local-worldserver.sh --cleanup

# Remove test logs
rm -rf storage/azerothcore/logs-test/
```

## Expected Results

### Pros of Local Files
- Potentially faster file I/O (no network mount overhead)
- Self-contained container
- No external volume dependencies

### Cons of Local Files
- Much longer startup time (20-30 minutes)
- Re-download on every container recreation
- Larger container footprint
- No persistence across restarts

## Conclusion

This test will help determine if the performance benefits of local file storage outweigh the significant startup time and storage overhead costs.