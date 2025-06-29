#!/bin/bash

# Enterprise Advanced Tooling Setup Script
# Comprehensive development tooling with 100% FOSS technologies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js first."
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install Git first."
    fi
    
    # Check available disk space (minimum 20GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 20971520 ]; then
        warn "Less than 20GB disk space available. Advanced tooling may require more space."
    fi
    
    # Check available memory (minimum 16GB recommended)
    available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    if [ "$available_memory" -lt 16384 ]; then
        warn "Less than 16GB RAM available. Performance may be impacted."
    fi
    
    log "Prerequisites check completed"
}

# Initialize configuration files
init_configs() {
    log "Initializing configuration files..."
    
    # Create directory structure
    mkdir -p config/{prometheus,grafana/{provisioning,dashboards},storybook,chromatic,codegen,api-docs,dependency-updater,code-quality,testing,semantic-release,perf-budget,orchestrator}
    mkdir -p docker/{storybook,chromatic-server,graphql-codegen,api-docs-generator,dependency-updater,code-quality-dashboard,automated-testing,semantic-release,bundle-analyzer,perf-budget-monitor,tooling-orchestrator}
    mkdir -p sql
    mkdir -p docs
    mkdir -p logs
    
    # Storybook configuration
    cat > config/storybook/.storybook/main.js << 'EOF'
const path = require('path');

module.exports = {
  stories: [
    '../src/**/*.stories.@(js|jsx|ts|tsx|mdx)',
    '../../../packages/*/src/**/*.stories.@(js|jsx|ts|tsx|mdx)'
  ],
  addons: [
    '@storybook/addon-essentials',
    '@storybook/addon-controls',
    '@storybook/addon-actions',
    '@storybook/addon-viewport',
    '@storybook/addon-docs',
    '@storybook/addon-a11y',
    '@storybook/addon-design-tokens',
    '@chromatic-com/storybook'
  ],
  framework: {
    name: '@storybook/react-vite',
    options: {}
  },
  features: {
    buildStoriesJson: true
  },
  typescript: {
    check: false,
    reactDocgen: 'react-docgen-typescript',
    reactDocgenTypescriptOptions: {
      shouldExtractLiteralValuesFromEnum: true,
      propFilter: (prop) => (prop.parent ? !/node_modules/.test(prop.parent.fileName) : true),
    },
  },
  viteFinal: async (config) => {
    config.resolve.alias = {
      ...config.resolve.alias,
      '@': path.resolve(__dirname, '../src'),
      '@/components': path.resolve(__dirname, '../src/components'),
      '@/lib': path.resolve(__dirname, '../src/lib'),
    };
    return config;
  },
};
EOF

    cat > config/storybook/.storybook/preview.js << 'EOF'
import { themes } from '@storybook/theming';
import '../src/styles/globals.css';

export const parameters = {
  actions: { argTypesRegex: '^on[A-Z].*' },
  controls: {
    matchers: {
      color: /(background|color)$/i,
      date: /Date$/,
    },
  },
  docs: {
    theme: themes.light,
  },
  viewport: {
    viewports: {
      mobile: {
        name: 'Mobile',
        styles: {
          width: '375px',
          height: '667px',
        },
      },
      tablet: {
        name: 'Tablet',
        styles: {
          width: '768px',
          height: '1024px',
        },
      },
      desktop: {
        name: 'Desktop',
        styles: {
          width: '1024px',
          height: '768px',
        },
      },
    },
  },
  a11y: {
    config: {},
    options: {
      checks: { 'color-contrast': { options: { noScroll: true } } },
      restoreScroll: true,
    },
  },
};

export const globalTypes = {
  theme: {
    name: 'Theme',
    description: 'Global theme for components',
    defaultValue: 'light',
    toolbar: {
      icon: 'circlehollow',
      items: ['light', 'dark'],
      showName: true,
    },
  },
};
EOF

    # GraphQL Code Generator configuration
    cat > config/codegen/codegen.yml << 'EOF'
overwrite: true
schema: "http://localhost:3100/graphql"
documents: "src/**/*.{ts,tsx,graphql,gql}"
generates:
  src/generated/graphql.ts:
    plugins:
      - "typescript"
      - "typescript-operations"
      - "typescript-react-apollo"
    config:
      withHooks: true
      withHOC: false
      withComponent: false
      apolloReactHooksImportFrom: "@apollo/client"
      skipTypename: false
      namingConvention:
        typeNames: pascal-case#pascalCase
        enumValues: upper-case#upperCase
      scalars:
        DateTime: string
        JSON: any
        Upload: File
  src/generated/introspection.json:
    plugins:
      - "introspection"
  src/generated/schema.graphql:
    plugins:
      - "schema-ast"
hooks:
  afterAllFileWrite:
    - prettier --write
EOF

    # Husky configuration
    cat > .husky/pre-commit << 'EOF'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Run lint-staged
npx lint-staged

# Run type checking
npm run type-check

# Run tests related to staged files
npm run test:staged
EOF

    cat > .husky/commit-msg << 'EOF'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Validate commit message format
npx commitlint --edit $1
EOF

    cat > .husky/pre-push << 'EOF'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Run full test suite before push
npm run test:ci

# Run build to ensure it works
npm run build

# Run security audit
npm audit --audit-level moderate
EOF

    # Commitlint configuration
    cat > .commitlintrc.js << 'EOF'
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation changes
        'style',    // Code style changes (formatting, etc)
        'refactor', // Code refactoring
        'perf',     // Performance improvements
        'test',     // Adding or updating tests
        'chore',    // Maintenance tasks
        'ci',       // CI/CD changes
        'build',    // Build system changes
        'revert',   // Reverting changes
      ],
    ],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'lower-case'],
    'subject-case': [2, 'always', 'sentence-case'],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    'header-max-length': [2, 'always', 100],
    'body-leading-blank': [2, 'always'],
    'footer-leading-blank': [2, 'always'],
  },
};
EOF

    # Lint-staged configuration
    cat > .lintstagedrc.js << 'EOF'
module.exports = {
  '*.{js,jsx,ts,tsx}': [
    'eslint --fix',
    'prettier --write',
    'jest --bail --findRelatedTests --passWithNoTests',
  ],
  '*.{json,md,yml,yaml}': ['prettier --write'],
  '*.{css,scss,sass}': ['stylelint --fix', 'prettier --write'],
  '*.{png,jpg,jpeg,gif,svg}': ['imagemin-lint-staged'],
};
EOF

    # Semantic Release configuration
    cat > .releaserc.js << 'EOF'
module.exports = {
  branches: [
    'main',
    { name: 'beta', prerelease: true },
    { name: 'alpha', prerelease: true },
  ],
  plugins: [
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    '@semantic-release/changelog',
    '@semantic-release/npm',
    '@semantic-release/github',
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'package.json', 'package-lock.json'],
        message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
      },
    ],
  ],
  preset: 'conventionalcommits',
  presetConfig: {
    types: [
      { type: 'feat', section: 'Features' },
      { type: 'fix', section: 'Bug Fixes' },
      { type: 'perf', section: 'Performance Improvements' },
      { type: 'revert', section: 'Reverts' },
      { type: 'docs', section: 'Documentation', hidden: false },
      { type: 'style', section: 'Styles', hidden: false },
      { type: 'chore', section: 'Miscellaneous Chores', hidden: false },
      { type: 'refactor', section: 'Code Refactoring', hidden: false },
      { type: 'test', section: 'Tests', hidden: false },
      { type: 'build', section: 'Build System', hidden: false },
      { type: 'ci', section: 'Continuous Integration', hidden: false },
    ],
  },
};
EOF

    # Renovate configuration for dependency updates
    cat > renovate.json << 'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:base",
    "schedule:weekends",
    ":dependencyDashboard",
    ":semanticCommits",
    ":separatePatchReleases"
  ],
  "timezone": "UTC",
  "schedule": ["before 6am on Monday"],
  "labels": ["dependencies"],
  "assignees": ["@nexus-v3-team"],
  "reviewers": ["@nexus-v3-team"],
  "packageRules": [
    {
      "matchDepTypes": ["devDependencies"],
      "automerge": true,
      "automergeType": "pr",
      "requiredStatusChecks": null
    },
    {
      "matchPackagePatterns": ["^@types/"],
      "automerge": true,
      "automergeType": "pr"
    },
    {
      "matchPackageNames": ["react", "react-dom"],
      "groupName": "React"
    },
    {
      "matchPackageNames": ["@typescript-eslint/parser", "@typescript-eslint/eslint-plugin"],
      "groupName": "TypeScript ESLint"
    }
  ],
  "vulnerabilityAlerts": {
    "enabled": true,
    "schedule": ["at any time"]
  },
  "lockFileMaintenance": {
    "enabled": true,
    "schedule": ["before 6am on Monday"]
  }
}
EOF

    # Prometheus configuration for tooling
    cat > config/prometheus/prometheus-tooling.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "rules/*.yml"

scrape_configs:
  # Advanced tooling services
  - job_name: 'advanced-tooling'
    static_configs:
      - targets:
        - 'chromatic-server:3300'
        - 'graphql-codegen:3301'
        - 'api-docs-generator:3303'
        - 'code-quality-dashboard:3304'
        - 'bundle-analyzer:3305'
        - 'perf-budget-monitor:3306'
        - 'tooling-orchestrator:3307'
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Storybook metrics (if available)
  - job_name: 'storybook'
    static_configs:
      - targets: ['storybook:6006']
    metrics_path: '/metrics'
    scrape_interval: 60s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093
EOF

    log "Configuration files initialized"
}

# Setup package.json scripts
setup_package_scripts() {
    log "Setting up package.json scripts..."
    
    # Create comprehensive package.json scripts
    cat > ../package.json.tooling << 'EOF'
{
  "scripts": {
    "storybook": "storybook dev -p 6006",
    "build-storybook": "storybook build",
    "chromatic": "npx chromatic --project-token=$CHROMATIC_PROJECT_TOKEN",
    "codegen": "graphql-codegen --config advanced-tooling/config/codegen/codegen.yml",
    "codegen:watch": "graphql-codegen --config advanced-tooling/config/codegen/codegen.yml --watch",
    "docs:api": "swagger-jsdoc -d advanced-tooling/config/swagger/definition.js -o advanced-tooling/docs/openapi.json apps/*/src/**/*.js",
    "docs:serve": "swagger-ui-serve advanced-tooling/docs/openapi.json",
    "lint": "eslint . --ext .js,.jsx,.ts,.tsx --fix",
    "lint:check": "eslint . --ext .js,.jsx,.ts,.tsx",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "type-check": "tsc --noEmit",
    "test:unit": "jest",
    "test:e2e": "playwright test",
    "test:visual": "chromatic --exit-zero-on-changes",
    "test:staged": "jest --bail --findRelatedTests --passWithNoTests",
    "test:ci": "jest --ci --coverage --watchAll=false",
    "analyze": "npm run build && npx webpack-bundle-analyzer build/static/js/*.js",
    "perf:budget": "lighthouse-ci autorun",
    "deps:update": "npx npm-check-updates -u",
    "deps:audit": "npm audit --audit-level moderate",
    "release": "semantic-release",
    "release:dry": "semantic-release --dry-run",
    "prepare": "husky install",
    "postinstall": "husky install"
  },
  "devDependencies": {
    "@storybook/react-vite": "^7.6.0",
    "@storybook/addon-essentials": "^7.6.0",
    "@storybook/addon-controls": "^7.6.0",
    "@storybook/addon-actions": "^7.6.0",
    "@storybook/addon-viewport": "^7.6.0",
    "@storybook/addon-docs": "^7.6.0",
    "@storybook/addon-a11y": "^7.6.0",
    "@chromatic-com/storybook": "^1.0.0",
    "chromatic": "^10.0.0",
    "@graphql-codegen/cli": "^5.0.0",
    "@graphql-codegen/typescript": "^4.0.0",
    "@graphql-codegen/typescript-operations": "^4.0.0",
    "@graphql-codegen/typescript-react-apollo": "^4.0.0",
    "@graphql-codegen/introspection": "^4.0.0",
    "@graphql-codegen/schema-ast": "^4.0.0",
    "husky": "^8.0.0",
    "lint-staged": "^15.0.0",
    "@commitlint/cli": "^18.0.0",
    "@commitlint/config-conventional": "^18.0.0",
    "semantic-release": "^22.0.0",
    "@semantic-release/changelog": "^6.0.0",
    "@semantic-release/git": "^10.0.0",
    "swagger-jsdoc": "^6.2.0",
    "swagger-ui-express": "^5.0.0",
    "@playwright/test": "^1.40.0",
    "lighthouse": "^11.0.0",
    "@lhci/cli": "^0.12.0",
    "webpack-bundle-analyzer": "^4.10.0",
    "npm-check-updates": "^16.0.0",
    "imagemin-lint-staged": "^0.5.0"
  }
}
EOF

    log "Package.json scripts configured"
}

# Create Docker images
build_images() {
    log "Building custom Docker images..."
    
    # Storybook Dockerfile
    cat > docker/storybook/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci

# Copy Storybook configuration
COPY .storybook/ ./.storybook/
COPY src/ ./src/

EXPOSE 6006

CMD ["npm", "run", "storybook"]
EOF

    # Chromatic Server Dockerfile
    cat > docker/chromatic-server/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

EXPOSE 3300

CMD ["node", "src/index.js"]
EOF

    cat > docker/chromatic-server/package.json << 'EOF'
{
  "name": "chromatic-server",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "pg": "^8.11.0",
    "redis": "^4.6.0",
    "winston": "^3.11.0",
    "prom-client": "^15.0.0",
    "puppeteer": "^21.0.0",
    "pixelmatch": "^5.3.0",
    "sharp": "^0.32.0",
    "multer": "^1.4.5"
  }
}
EOF

    # GraphQL Code Generator Dockerfile
    cat > docker/graphql-codegen/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install GraphQL Code Generator globally
RUN npm install -g @graphql-codegen/cli

# Install common plugins
RUN npm install -g \
    @graphql-codegen/typescript \
    @graphql-codegen/typescript-operations \
    @graphql-codegen/typescript-react-apollo \
    @graphql-codegen/introspection \
    @graphql-codegen/schema-ast

# Copy configuration
COPY config/ ./config/

EXPOSE 3301

CMD ["graphql-codegen", "--config", "config/codegen.yml", "--watch"]
EOF

    log "Docker images configuration created"
}

# Start services
start_services() {
    log "Starting Advanced Tooling services..."
    
    # Pull required images
    docker-compose -f docker-compose.advanced-tooling.yml pull
    
    # Build custom images
    docker-compose -f docker-compose.advanced-tooling.yml build
    
    # Start services in stages
    log "Starting database services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d chromatic-postgres quality-postgres perf-postgres
    sleep 30
    
    log "Starting cache services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d chromatic-redis quality-redis
    sleep 20
    
    log "Starting core tooling services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d storybook chromatic-server graphql-codegen swagger-ui api-docs-generator
    sleep 30
    
    log "Starting automation services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d dependency-updater automated-testing semantic-release
    sleep 20
    
    log "Starting monitoring services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d tooling-prometheus tooling-grafana
    sleep 20
    
    log "Starting remaining services..."
    docker-compose -f docker-compose.advanced-tooling.yml up -d code-quality-dashboard bundle-analyzer perf-budget-monitor tooling-orchestrator
    
    log "Waiting for services to be ready..."
    sleep 60
    
    # Health checks
    check_service_health "Storybook" "http://localhost:6006"
    check_service_health "Chromatic Server" "http://localhost:3300/health"
    check_service_health "GraphQL CodeGen" "http://localhost:3301/health"
    check_service_health "Swagger UI" "http://localhost:3302"
    check_service_health "Code Quality Dashboard" "http://localhost:3304/health"
    check_service_health "Bundle Analyzer" "http://localhost:3305"
    check_service_health "Tooling Orchestrator" "http://localhost:3307/health"
    check_service_health "Tooling Grafana" "http://localhost:3308"
    check_service_health "Tooling Prometheus" "http://localhost:9096/-/healthy"
    
    log "All services are running successfully!"
}

# Health check function
check_service_health() {
    local service_name=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            log "$service_name is healthy"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            warn "$service_name health check failed after $max_attempts attempts"
            return 1
        fi
        
        sleep 10
        ((attempt++))
    done
}

# Setup Git hooks
setup_git_hooks() {
    log "Setting up Git hooks with Husky..."
    
    # Initialize Husky
    if [ -d "../.git" ]; then
        cd ..
        npx husky install
        chmod +x .husky/pre-commit
        chmod +x .husky/commit-msg
        chmod +x .husky/pre-push
        cd advanced-tooling
        log "Git hooks configured successfully"
    else
        warn "Not in a Git repository. Skipping Git hooks setup."
    fi
}

# Display access information
show_access_info() {
    log "Advanced Tooling System is ready!"
    echo
    echo -e "${BLUE}=== ACCESS INFORMATION ===${NC}"
    echo -e "${GREEN}Storybook:${NC} http://localhost:6006"
    echo -e "${GREEN}Chromatic Server:${NC} http://localhost:3300"
    echo -e "${GREEN}GraphQL CodeGen:${NC} http://localhost:3301"
    echo -e "${GREEN}Swagger UI:${NC} http://localhost:3302"
    echo -e "${GREEN}API Docs Generator:${NC} http://localhost:3303"
    echo -e "${GREEN}Code Quality Dashboard:${NC} http://localhost:3304"
    echo -e "${GREEN}Bundle Analyzer:${NC} http://localhost:3305"
    echo -e "${GREEN}Performance Budget Monitor:${NC} http://localhost:3306"
    echo -e "${GREEN}Tooling Orchestrator:${NC} http://localhost:3307"
    echo -e "${GREEN}Tooling Grafana:${NC} http://localhost:3308 (admin/admin)"
    echo -e "${GREEN}Tooling Prometheus:${NC} http://localhost:9096"
    echo
    echo -e "${BLUE}=== DEVELOPMENT COMMANDS ===${NC}"
    echo "npm run storybook          # Start Storybook development server"
    echo "npm run chromatic          # Run visual regression tests"
    echo "npm run codegen            # Generate GraphQL types"
    echo "npm run docs:api           # Generate API documentation"
    echo "npm run lint               # Run ESLint with auto-fix"
    echo "npm run test:visual        # Run visual tests"
    echo "npm run analyze            # Analyze bundle size"
    echo "npm run release            # Create semantic release"
    echo
    echo -e "${BLUE}=== QUICK START ===${NC}"
    echo "1. Develop components in Storybook at http://localhost:6006"
    echo "2. Generate GraphQL types with npm run codegen"
    echo "3. View API documentation at http://localhost:3302"
    echo "4. Monitor code quality at http://localhost:3304"
    echo "5. Analyze bundle performance at http://localhost:3305"
    echo "6. Track tooling metrics in Grafana at http://localhost:3308"
    echo
}

# Main execution
main() {
    log "Starting Enterprise Advanced Tooling Setup..."
    
    check_prerequisites
    init_configs
    setup_package_scripts
    build_images
    start_services
    setup_git_hooks
    show_access_info
    
    log "Advanced Tooling setup completed successfully!"
}

# Execute main function
main "$@"
