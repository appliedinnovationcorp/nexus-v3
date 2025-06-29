#!/bin/bash

# Migration Script 06: Configuration and Deployment Migration
# This script consolidates configurations and deployment files

set -e

echo "⚙️  Starting Configuration and Deployment Migration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to safely copy files
safe_copy() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        echo -e "${GREEN}✅ Copied $desc: $src -> $dest${NC}"
    elif [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null)" ]; then
        cp -r "$src"/* "$dest"/ 2>/dev/null || true
        echo -e "${GREEN}✅ Copied $desc directory: $src -> $dest${NC}"
    else
        echo -e "${YELLOW}⚠️  Source not found or empty for $desc: $src${NC}"
    fi
}

# Helper function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local desc="$3"
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✅ Created $desc: $file_path${NC}"
}

echo -e "${BLUE}📦 Step 1: Creating New Package.json...${NC}"

# Extract dependencies from all existing package.json files
echo -e "${BLUE}🔍 Analyzing existing dependencies...${NC}"

# Create temporary file to collect all dependencies
echo '{}' > migration-temp/all-dependencies.json

# Process each package.json file
while IFS= read -r package_file; do
    if [ -f "$package_file" ]; then
        echo "Processing: $package_file"
        # Extract dependencies and devDependencies, merge them
        jq -s '.[0] * (.[1].dependencies // {}) * (.[1].devDependencies // {})' migration-temp/all-dependencies.json "$package_file" > migration-temp/temp-deps.json
        mv migration-temp/temp-deps.json migration-temp/all-dependencies.json
    fi
done < migration-temp/inventory/package-json-files.txt

# Create the new consolidated package.json
create_file "package.json" "{
  \"name\": \"nexus-v3-ddd\",
  \"version\": \"1.0.0\",
  \"description\": \"Nexus V3 - Domain-Driven Design Architecture\",
  \"main\": \"dist/startup.js\",
  \"scripts\": {
    \"start\": \"node dist/startup.js\",
    \"dev\": \"tsx watch src/startup.ts\",
    \"build\": \"tsc\",
    \"build:watch\": \"tsc --watch\",
    \"test\": \"jest\",
    \"test:watch\": \"jest --watch\",
    \"test:coverage\": \"jest --coverage\",
    \"test:unit\": \"jest tests/unit\",
    \"test:integration\": \"jest tests/integration\",
    \"test:e2e\": \"jest tests/e2e\",
    \"lint\": \"eslint src/**/*.ts\",
    \"lint:fix\": \"eslint src/**/*.ts --fix\",
    \"format\": \"prettier --write src/**/*.ts\",
    \"db:migrate\": \"tsx src/Infrastructure/Data/DatabaseSetup.ts\",
    \"db:seed\": \"tsx scripts/seed-database.ts\",
    \"clean\": \"rimraf dist\",
    \"typecheck\": \"tsc --noEmit\"
  },
  \"dependencies\": {
    \"express\": \"^4.18.2\",
    \"cors\": \"^2.8.5\",
    \"helmet\": \"^7.1.0\",
    \"compression\": \"^1.7.4\",
    \"pg\": \"^8.11.3\",
    \"redis\": \"^4.6.10\",
    \"bcryptjs\": \"^2.4.3\",
    \"jsonwebtoken\": \"^9.0.2\",
    \"nodemailer\": \"^6.9.7\",
    \"winston\": \"^3.11.0\",
    \"joi\": \"^17.11.0\",
    \"dotenv\": \"^16.3.1\",
    \"uuid\": \"^9.0.1\",
    \"date-fns\": \"^2.30.0\",
    \"lodash\": \"^4.17.21\"
  },
  \"devDependencies\": {
    \"@types/node\": \"^20.8.0\",
    \"@types/express\": \"^4.17.20\",
    \"@types/cors\": \"^2.8.15\",
    \"@types/compression\": \"^1.7.4\",
    \"@types/pg\": \"^8.10.7\",
    \"@types/bcryptjs\": \"^2.4.5\",
    \"@types/jsonwebtoken\": \"^9.0.4\",
    \"@types/nodemailer\": \"^6.4.13\",
    \"@types/uuid\": \"^9.0.6\",
    \"@types/lodash\": \"^4.14.200\",
    \"@types/jest\": \"^29.5.6\",
    \"@types/supertest\": \"^2.0.15\",
    \"typescript\": \"^5.2.2\",
    \"tsx\": \"^3.14.0\",
    \"jest\": \"^29.7.0\",
    \"ts-jest\": \"^29.1.1\",
    \"supertest\": \"^6.3.3\",
    \"eslint\": \"^8.52.0\",
    \"@typescript-eslint/parser\": \"^6.9.0\",
    \"@typescript-eslint/eslint-plugin\": \"^6.9.0\",
    \"prettier\": \"^3.0.3\",
    \"rimraf\": \"^5.0.5\",
    \"nodemon\": \"^3.0.1\"
  },
  \"engines\": {
    \"node\": \">=18.0.0\",
    \"npm\": \">=8.0.0\"
  },
  \"keywords\": [
    \"ddd\",
    \"domain-driven-design\",
    \"clean-architecture\",
    \"typescript\",
    \"nodejs\",
    \"express\"
  ],
  \"author\": \"Nexus Team\",
  \"license\": \"MIT\"
}" "New Package.json"

echo -e "${BLUE}🔧 Step 2: Creating TypeScript Configuration...${NC}"

create_file "tsconfig.json" "{
  \"compilerOptions\": {
    \"target\": \"ES2022\",
    \"module\": \"commonjs\",
    \"lib\": [\"ES2022\"],
    \"outDir\": \"./dist\",
    \"rootDir\": \"./src\",
    \"strict\": true,
    \"esModuleInterop\": true,
    \"skipLibCheck\": true,
    \"forceConsistentCasingInFileNames\": true,
    \"resolveJsonModule\": true,
    \"declaration\": true,
    \"declarationMap\": true,
    \"sourceMap\": true,
    \"removeComments\": true,
    \"noImplicitAny\": true,
    \"strictNullChecks\": true,
    \"strictFunctionTypes\": true,
    \"noImplicitThis\": true,
    \"noImplicitReturns\": true,
    \"noFallthroughCasesInSwitch\": true,
    \"noUncheckedIndexedAccess\": true,
    \"exactOptionalPropertyTypes\": true,
    \"experimentalDecorators\": true,
    \"emitDecoratorMetadata\": true,
    \"baseUrl\": \".\",
    \"paths\": {
      \"@/*\": [\"src/*\"],
      \"@domain/*\": [\"src/Domain/*\"],
      \"@application/*\": [\"src/Application/*\"],
      \"@infrastructure/*\": [\"src/Infrastructure/*\"],
      \"@presentation/*\": [\"src/Presentation/*\"],
      \"@shared/*\": [\"src/SharedKernel/*\"]
    }
  },
  \"include\": [
    \"src/**/*\"
  ],
  \"exclude\": [
    \"node_modules\",
    \"dist\",
    \"tests\",
    \"**/*.test.ts\",
    \"**/*.spec.ts\"
  ]
}" "TypeScript Configuration"

echo -e "${BLUE}🧪 Step 3: Creating Test Configuration...${NC}"

create_file "jest.config.js" "module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src', '<rootDir>/tests'],
  testMatch: [
    '**/__tests__/**/*.ts',
    '**/?(*.)+(spec|test).ts'
  ],
  transform: {
    '^.+\\.ts$': 'ts-jest',
  },
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/**/index.ts',
    '!src/startup.ts'
  ],
  coverageDirectory: 'coverage',
  coverageReporters: [
    'text',
    'lcov',
    'html'
  ],
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/src/\$1',
    '^@domain/(.*)$': '<rootDir>/src/Domain/\$1',
    '^@application/(.*)$': '<rootDir>/src/Application/\$1',
    '^@infrastructure/(.*)$': '<rootDir>/src/Infrastructure/\$1',
    '^@presentation/(.*)$': '<rootDir>/src/Presentation/\$1',
    '^@shared/(.*)$': '<rootDir>/src/SharedKernel/\$1'
  },
  testTimeout: 10000,
  verbose: true
};" "Jest Configuration"

echo -e "${BLUE}📏 Step 4: Creating ESLint Configuration...${NC}"

create_file ".eslintrc.js" "module.exports = {
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
    project: './tsconfig.json'
  },
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    '@typescript-eslint/recommended',
    '@typescript-eslint/recommended-requiring-type-checking'
  ],
  root: true,
  env: {
    node: true,
    jest: true,
    es2022: true
  },
  ignorePatterns: ['.eslintrc.js', 'dist/', 'node_modules/', 'coverage/'],
  rules: {
    '@typescript-eslint/interface-name-prefix': 'off',
    '@typescript-eslint/explicit-function-return-type': 'error',
    '@typescript-eslint/explicit-module-boundary-types': 'error',
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/no-unused-vars': 'error',
    '@typescript-eslint/prefer-const': 'error',
    '@typescript-eslint/no-var-requires': 'error',
    'prefer-const': 'error',
    'no-var': 'error',
    'no-console': 'warn',
    'no-debugger': 'error'
  }
};" "ESLint Configuration"

echo -e "${BLUE}💅 Step 5: Creating Prettier Configuration...${NC}"

create_file ".prettierrc" "{
  \"semi\": true,
  \"trailingComma\": \"es5\",
  \"singleQuote\": true,
  \"printWidth\": 100,
  \"tabWidth\": 2,
  \"useTabs\": false,
  \"bracketSpacing\": true,
  \"arrowParens\": \"avoid\",
  \"endOfLine\": \"lf\"
}" "Prettier Configuration"

create_file ".prettierignore" "node_modules/
dist/
coverage/
*.log
.env*
migration-temp/
migration-scripts/" "Prettier Ignore"

echo -e "${BLUE}🌍 Step 6: Creating Environment Configuration...${NC}"

create_file ".env.example" "# Application
NODE_ENV=development
PORT=3000
APP_NAME=\"Nexus V3\"
APP_VERSION=\"1.0.0\"

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=nexus_v3
DB_USER=postgres
DB_PASSWORD=password
DB_POOL_MAX=20
DB_IDLE_TIMEOUT=30000
DB_CONNECTION_TIMEOUT=2000

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
JWT_EXPIRES_IN=24h
JWT_REFRESH_EXPIRES_IN=30d

# Email
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=your-email@gmail.com
EMAIL_PASS=your-app-password
FROM_EMAIL=noreply@nexus-v3.com

# Logging
LOG_LEVEL=info
LOG_FILE_PATH=logs/

# Security
BCRYPT_ROUNDS=12
MAX_LOGIN_ATTEMPTS=5
LOCKOUT_DURATION_MINUTES=15

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100

# CORS
CORS_ORIGIN=http://localhost:3000
CORS_CREDENTIALS=true

# File Upload
MAX_FILE_SIZE_MB=10
UPLOAD_PATH=uploads/

# Frontend URL (for email links)
FRONTEND_URL=http://localhost:3000" "Environment Example"

create_file "config/database.ts" "import { DatabaseConfig } from '../src/SharedKernel/Types/CommonTypes';

export const databaseConfig: DatabaseConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'nexus_v3',
  username: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'password',
  ssl: process.env.NODE_ENV === 'production',
  poolSize: parseInt(process.env.DB_POOL_MAX || '20')
};" "Database Config"

create_file "config/email.ts" "import { EmailConfig } from '../src/SharedKernel/Types/CommonTypes';

export const emailConfig: EmailConfig = {
  host: process.env.EMAIL_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.EMAIL_PORT || '587'),
  secure: process.env.EMAIL_SECURE === 'true',
  auth: {
    user: process.env.EMAIL_USER || '',
    pass: process.env.EMAIL_PASS || ''
  },
  from: process.env.FROM_EMAIL || 'noreply@nexus-v3.com'
};" "Email Config"

create_file "config/jwt.ts" "import { JwtConfig } from '../src/SharedKernel/Types/CommonTypes';

export const jwtConfig: JwtConfig = {
  secret: process.env.JWT_SECRET || 'your-super-secret-jwt-key',
  expiresIn: process.env.JWT_EXPIRES_IN || '24h',
  refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d'
};" "JWT Config"

echo -e "${BLUE}🐳 Step 7: Migrating Docker Configuration...${NC}"

# Copy existing Docker configurations
safe_copy "Dockerfile" "deployment/Dockerfile.old" "Old Dockerfile"
safe_copy "docker-compose.yml" "deployment/docker-compose.old.yml" "Old Docker Compose"

# Create new optimized Dockerfile
create_file "Dockerfile" "# Multi-stage build for production
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Create app user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# Set working directory
WORKDIR /app

# Copy built application
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

# Create logs directory
RUN mkdir -p logs && chown nextjs:nodejs logs

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

# Start the application
CMD [\"node\", \"dist/startup.js\"]" "New Dockerfile"

# Create new docker-compose for development
create_file "docker-compose.yml" "version: '3.8'

services:
  app:
    build: .
    ports:
      - \"3000:3000\"
    environment:
      - NODE_ENV=development
      - DB_HOST=postgres
      - REDIS_HOST=redis
    depends_on:
      - postgres
      - redis
    volumes:
      - ./logs:/app/logs
    networks:
      - nexus-network

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: nexus_v3
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    ports:
      - \"5432:5432\"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./src/Infrastructure/Data/Migrations:/docker-entrypoint-initdb.d
    networks:
      - nexus-network

  redis:
    image: redis:7-alpine
    ports:
      - \"6379:6379\"
    volumes:
      - redis_data:/data
    networks:
      - nexus-network

volumes:
  postgres_data:
  redis_data:

networks:
  nexus-network:
    driver: bridge" "New Docker Compose"

echo -e "${BLUE}🚀 Step 8: Migrating Deployment Configurations...${NC}"

# Copy infrastructure configurations
safe_copy "infrastructure" "deployment/infrastructure" "Infrastructure Configs"
safe_copy "containers" "deployment/containers" "Container Configs"

# Create deployment scripts
create_file "deployment/deploy.sh" "#!/bin/bash

# Deployment script for Nexus V3
set -e

echo \"🚀 Starting deployment...\"

# Build the application
echo \"📦 Building application...\"
npm run build

# Run tests
echo \"🧪 Running tests...\"
npm test

# Build Docker image
echo \"🐳 Building Docker image...\"
docker build -t nexus-v3:latest .

# Deploy based on environment
if [ \"\$NODE_ENV\" = \"production\" ]; then
    echo \"🌟 Deploying to production...\"
    # Add production deployment commands here
    docker-compose -f docker-compose.prod.yml up -d
else
    echo \"🔧 Deploying to development...\"
    docker-compose up -d
fi

echo \"✅ Deployment completed!\"" "Deployment Script"

chmod +x deployment/deploy.sh

echo -e "${BLUE}📋 Step 9: Creating Git Configuration...${NC}"

create_file ".gitignore" "# Dependencies
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Production build
dist/
build/

# Environment variables
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Logs
logs/
*.log

# Runtime data
pids/
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Temporary files
tmp/
temp/

# Migration temporary files
migration-temp/

# Database
*.sqlite
*.db

# Uploads
uploads/

# Cache
.cache/
.parcel-cache/

# Testing
.nyc_output/

# Docker
.dockerignore" "Git Ignore"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["06-configuration"] = "completed" | .current_phase = "07-testing"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Configuration and Deployment Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Package.json: Consolidated from $(wc -l < migration-temp/inventory/package-json-files.txt) files"
echo -e "  • TypeScript config: Created with path mapping"
echo -e "  • Test config: Jest with coverage setup"
echo -e "  • Linting: ESLint + Prettier configuration"
echo -e "  • Environment: .env.example with all variables"
echo -e "  • Docker: Multi-stage Dockerfile + docker-compose"
echo -e "  • Deployment: Scripts and configurations"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/07-migrate-testing.sh${NC}"
