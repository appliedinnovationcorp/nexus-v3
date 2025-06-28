#!/bin/bash

# Loop through each folder in ./apps
for dir in ./apps/*/; do
    # Extract just the folder name (remove path and trailing slash)
    folder_name=$(basename "$dir")
    
    echo "Setting up $folder_name..."
    
    # Enter the directory
    cd "$dir" || continue
    
    # Create src and dist directories
    mkdir -p src dist
    
    # Initialize package.json with pnpm
    pnpm init -y
    
    # Modify package.json to set name and main fields
    # Use jq if available, otherwise use sed
    if command -v jq &> /dev/null; then
        # Using jq (more reliable)
        jq --arg name "@aic/$folder_name" --arg main "./src/index.ts" \
           '.name = $name | .main = $main' package.json > package.json.tmp && \
           mv package.json.tmp package.json
    else
        # Using sed (fallback)
        sed -i "s/\"name\": \".*\"/\"name\": \"@aic\/$folder_name\"/" package.json
        sed -i "s/\"main\": \".*\"/\"main\": \".\/src\/index.ts\"/" package.json
    fi
    
    echo "✓ Completed setup for $folder_name"
    
    # Return to the original directory
    cd - > /dev/null
done

echo "All apps have been set up!"
