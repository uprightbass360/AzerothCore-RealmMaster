#!/bin/bash
# Copy module .dist.conf files to .conf files for proper configuration loading
# This ensures all module configurations are available and can be customized

CONFIG_DIR="${STORAGE_PATH:-/nfs/azerothcore}/config"

echo "Creating module .conf files from .dist.conf templates..."

cd "$CONFIG_DIR" || {
    echo "Error: Cannot access config directory: $CONFIG_DIR"
    exit 1
}

# Counter for created files
created_count=0

# Process all .dist files except authserver, worldserver, dbimport (already handled)
for file in *.dist; do
    conffile=$(echo "$file" | sed 's/.dist$//')

    # Skip if it's a core config file (already handled)
    case "$conffile" in
        authserver.conf|worldserver.conf|dbimport.conf)
            continue
            ;;
    esac

    # Create .conf file if it doesn't exist
    if [ ! -f "$conffile" ]; then
        echo "Creating $conffile from $file"
        cp "$file" "$conffile"
        created_count=$((created_count + 1))
    else
        echo "Skipping $conffile (already exists)"
    fi
done

echo "Created $created_count module configuration files"
echo "Module configuration files are now ready for customization"

# List all .conf files for verification
echo ""
echo "Available configuration files:"
ls -1 *.conf | sort