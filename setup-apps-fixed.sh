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
    
    # Initialize package.json with pnpm (without -y flag)
    echo "" | pnpm init
    
    # Modify package.json using sed to set name and main fields
    if [ -f "package.json" ]; then
        # Update the name field
        sed -i "s/\"name\": \".*\"/\"name\": \"@aic\/$folder_name\"/" package.json
        
        # Update or add the main field
        if grep -q '"main":' package.json; then
            sed -i "s/\"main\": \".*\"/\"main\": \".\/src\/index.ts\"/" package.json
        else
            # Add main field after name field
            sed -i "/\"name\": \"@aic\/$folder_name\",/a\\  \"main\": \"./src/index.ts\"," package.json
        fi
        
        echo "✓ Completed setup for $folder_name"
    else
        echo "✗ Failed to create package.json for $folder_name"
    fi
    
    # Return to the original directory
    cd - > /dev/null
done

echo "All apps have been set up!"
