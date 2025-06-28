#!/bin/bash

# Loop through each folder in ./apps
for dir in ./apps/*/; do
    folder_name=$(basename "$dir")
    
    echo "Fixing package.json for $folder_name..."
    
    cd "$dir" || continue
    
    if [ -f "package.json" ]; then
        # Create a temporary file with the updated JSON
        cat package.json | \
        sed "s/\"name\": \"$folder_name\"/\"name\": \"@aic\/$folder_name\"/" | \
        sed 's/"main": "index.js"/"main": ".\/src\/index.ts"/' > package.json.tmp
        
        # Replace the original file
        mv package.json.tmp package.json
        
        echo "✓ Updated $folder_name"
    else
        echo "✗ No package.json found for $folder_name"
    fi
    
    cd - > /dev/null
done

echo "All package.json files have been updated!"
