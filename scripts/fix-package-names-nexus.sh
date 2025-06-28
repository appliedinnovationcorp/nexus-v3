#!/bin/bash

# Fix all package names to use @aic namespace
echo "🔧 Fixing package names to use @aic namespace..."

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
update_package_name "./apps/admin" "@aic/admin"
update_package_name "./apps/cli" "@aic/cli"
update_package_name "./apps/cron" "@aic/cron"
update_package_name "./apps/desktop" "@aic/desktop"
update_package_name "./apps/docs" "@aic/docs"
update_package_name "./apps/extension" "@aic/extension"
update_package_name "./apps/graphql" "@aic/graphql"
update_package_name "./apps/landing" "@aic/landing"
update_package_name "./apps/mobile" "@aic/mobile"
update_package_name "./apps/storybook" "@aic/storybook"
update_package_name "./apps/webhooks" "@aic/webhooks"
update_package_name "./apps/workers" "@aic/workers"
update_package_name "./apps/api" "@aic/api-service"

# Update all packages
update_package_name "./packages/api" "@aic/api"
update_package_name "./packages/build-tools" "@aic/build-tools"
update_package_name "./packages/components" "@aic/components"
update_package_name "./packages/config" "@aic/config"
update_package_name "./packages/constants" "@aic/constants"
update_package_name "./packages/database" "@aic/database"
update_package_name "./packages/design-tokens" "@aic/design-tokens"
update_package_name "./packages/icons" "@aic/icons"
update_package_name "./packages/services" "@aic/services"
update_package_name "./packages/validators" "@aic/validators"

echo "✅ Package names updated!"
