#!/bin/bash

# Fix all package names to use @nexus namespace
echo "🔧 Fixing package names to use @nexus namespace..."

# Function to update package.json name
update_package_name() {
    local package_path=$1
    local new_name=$2
    
    if [ -f "$package_path/package.json" ]; then
        echo "📝 Updating $package_path to $new_name"
        sed -i "s/\"name\": \"@aic\/[^\"]*\"/\"name\": \"$new_name\"/" "$package_path/package.json"
    fi
}

# Update all apps
update_package_name "./apps/admin" "@nexus/admin"
update_package_name "./apps/cli" "@nexus/cli"
update_package_name "./apps/cron" "@nexus/cron"
update_package_name "./apps/desktop" "@nexus/desktop"
update_package_name "./apps/docs" "@nexus/docs"
update_package_name "./apps/extension" "@nexus/extension"
update_package_name "./apps/graphql" "@nexus/graphql"
update_package_name "./apps/landing" "@nexus/landing"
update_package_name "./apps/mobile" "@nexus/mobile"
update_package_name "./apps/storybook" "@nexus/storybook"
update_package_name "./apps/webhooks" "@nexus/webhooks"
update_package_name "./apps/workers" "@nexus/workers"
update_package_name "./apps/api" "@nexus/api-service"

# Update all packages
update_package_name "./packages/api" "@nexus/api"
update_package_name "./packages/build-tools" "@nexus/build-tools"
update_package_name "./packages/components" "@nexus/components"
update_package_name "./packages/config" "@nexus/config"
update_package_name "./packages/constants" "@nexus/constants"
update_package_name "./packages/database" "@nexus/database"
update_package_name "./packages/design-tokens" "@nexus/design-tokens"
update_package_name "./packages/icons" "@nexus/icons"
update_package_name "./packages/services" "@nexus/services"
update_package_name "./packages/validators" "@nexus/validators"

echo "✅ Package names updated!"
