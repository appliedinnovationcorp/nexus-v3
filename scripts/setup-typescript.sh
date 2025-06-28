#!/bin/bash

# TypeScript Setup Script for aic Workspace
echo "🔧 Setting up TypeScript for aic Workspace..."

# Function to create tsconfig for Node.js apps
create_node_tsconfig() {
    local app_path=$1
    local app_name=$2
    
    if [ ! -f "$app_path/tsconfig.json" ]; then
        echo "📝 Creating tsconfig.json for $app_name..."
        cat > "$app_path/tsconfig.json" << EOF
{
  "extends": "@aic/tsconfig/base.json",
  "compilerOptions": {
    "baseUrl": ".",
    "outDir": "./dist",
    "rootDir": "./src",
    "paths": {
      "@/*": ["./src/*"],
      "@aic/*": ["../../packages/*/src"]
    },
    "types": ["node"],
    "lib": ["ES2022"],
    "module": "CommonJS",
    "target": "ES2022",
    "moduleResolution": "node",
    "noEmit": false,
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true
  },
  "include": [
    "src/**/*",
    "**/*.ts"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "build",
    "**/*.test.ts",
    "**/*.spec.ts"
  ]
}
EOF
    fi
}

# Function to create tsconfig for React apps
create_react_tsconfig() {
    local app_path=$1
    local app_name=$2
    
    if [ ! -f "$app_path/tsconfig.json" ]; then
        echo "📝 Creating tsconfig.json for $app_name..."
        cat > "$app_path/tsconfig.json" << EOF
{
  "extends": "@aic/tsconfig/react.json",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"],
      "@aic/*": ["../../packages/*/src"]
    }
  },
  "include": [
    "src/**/*",
    "**/*.ts",
    "**/*.tsx"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "build",
    ".next"
  ]
}
EOF
    fi
}

# Function to create tsconfig for packages
create_package_tsconfig() {
    local package_path=$1
    local package_name=$2
    local is_react=${3:-false}
    
    if [ ! -f "$package_path/tsconfig.json" ]; then
        echo "📝 Creating tsconfig.json for $package_name package..."
        
        local extends_config="@aic/tsconfig/base.json"
        if [ "$is_react" = true ]; then
            extends_config="@aic/tsconfig/react.json"
        fi
        
        cat > "$package_path/tsconfig.json" << EOF
{
  "extends": "$extends_config",
  "compilerOptions": {
    "baseUrl": ".",
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "declarationMap": true,
    "noEmit": false,
    "composite": true,
    "paths": {
      "@aic/*": ["../*/src"]
    }
  },
  "include": [
    "src/**/*"
  ],
  "exclude": [
    "node_modules",
    "dist",
    "**/*.test.ts",
    "**/*.test.tsx",
    "**/*.spec.ts",
    "**/*.spec.tsx"
  ]
}
EOF
    fi
}

# Setup Node.js apps
echo "🚀 Setting up Node.js applications..."
create_node_tsconfig "./apps/api" "API"
create_node_tsconfig "./apps/graphql" "GraphQL"
create_node_tsconfig "./apps/cron" "Cron"
create_node_tsconfig "./apps/auth" "Auth"
create_node_tsconfig "./apps/webhooks" "Webhooks"
create_node_tsconfig "./apps/workers" "Workers"
create_node_tsconfig "./apps/cli" "CLI"

# Setup React apps
echo "⚛️  Setting up React applications..."
create_react_tsconfig "./apps/admin" "Admin"
create_react_tsconfig "./apps/docs" "Docs"
create_react_tsconfig "./apps/storybook" "Storybook"
create_react_tsconfig "./apps/landing" "Landing"
create_react_tsconfig "./apps/extension" "Extension"
create_react_tsconfig "./apps/desktop" "Desktop"

# Setup packages
echo "📦 Setting up packages..."
create_package_tsconfig "./packages/types" "types"
create_package_tsconfig "./packages/utils" "utils"
create_package_tsconfig "./packages/config" "config"
create_package_tsconfig "./packages/constants" "constants"
create_package_tsconfig "./packages/validators" "validators"
create_package_tsconfig "./packages/api" "api"
create_package_tsconfig "./packages/auth" "auth"
create_package_tsconfig "./packages/database" "database"
create_package_tsconfig "./packages/services" "services"
create_package_tsconfig "./packages/build-tools" "build-tools"

# Setup React packages
create_package_tsconfig "./packages/ui" "ui" true
create_package_tsconfig "./packages/components" "components" true
create_package_tsconfig "./packages/design-tokens" "design-tokens" true
create_package_tsconfig "./packages/icons" "icons" true

# Create global type definitions
echo "🌐 Creating global type definitions..."
mkdir -p "./types"

cat > "./types/global.d.ts" << EOF
// Global type definitions for aic Workspace

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: 'development' | 'production' | 'test';
      DATABASE_URL: string;
      REDIS_URL: string;
      JWT_SECRET: string;
      NEXTAUTH_SECRET: string;
      NEXTAUTH_URL: string;
    }
  }
}

export {};
EOF

# Run type checking
echo "🔍 Running type check..."
pnpm type-check

echo "✅ TypeScript setup complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Run 'pnpm install' to ensure all dependencies are installed"
echo "  2. Run 'pnpm type-check' to verify TypeScript configuration"
echo "  3. Run 'pnpm build' to build all packages and apps"
echo "  4. Start development with 'pnpm dev'"
