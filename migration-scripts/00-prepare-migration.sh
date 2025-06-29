#!/bin/bash

# Migration Script 00: Prepare Migration Environment
# This script prepares the workspace for the DDD refactoring

set -e

echo "🚀 Starting Migration Preparation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create backup
echo -e "${BLUE}📦 Creating backup...${NC}"
if [ ! -d "../v3-backup" ]; then
    cp -r . ../v3-backup
    echo -e "${GREEN}✅ Backup created at ../v3-backup${NC}"
else
    echo -e "${YELLOW}⚠️  Backup already exists, skipping...${NC}"
fi

# Create migration workspace
echo -e "${BLUE}📁 Creating new DDD structure...${NC}"

# Create main source directories
mkdir -p src/{Domain/{Aggregates,Entities,ValueObjects,Services,Events},Application/{Commands/{Handlers,Validators},Queries/{Handlers,Dtos},Events},Infrastructure/{Data/{Repositories,Migrations},ExternalServices,Messaging},Presentation/{Web/{Components,Pages},Api/{Controllers,Mappers}},SharedKernel}

# Create test directories
mkdir -p tests/{unit,integration,e2e}

# Create config and deployment directories
mkdir -p config deployment docs

# Create temporary directories for migration
mkdir -p migration-temp/{inventory,analysis,mappings}

echo -e "${GREEN}✅ Directory structure created${NC}"

# Create inventory of current source files
echo -e "${BLUE}📋 Creating source file inventory...${NC}"

# Find all TypeScript/JavaScript source files
find apps/ packages/ services/ -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" 2>/dev/null | sort > migration-temp/inventory/current-source-files.txt

# Find all test files
find apps/ packages/ services/ testing/ -name "*.test.ts" -o -name "*.test.tsx" -o -name "*.spec.ts" -o -name "*.spec.tsx" 2>/dev/null | sort > migration-temp/inventory/current-test-files.txt

# Find all configuration files
find . -name "package.json" -not -path "./node_modules/*" -not -path "./migration-temp/*" | sort > migration-temp/inventory/package-json-files.txt
find . -name "*.config.*" -not -path "./node_modules/*" -not -path "./migration-temp/*" | sort > migration-temp/inventory/config-files.txt

echo -e "${GREEN}✅ Inventory created${NC}"

# Analyze domain concepts
echo -e "${BLUE}🔍 Analyzing domain concepts...${NC}"

# Extract class definitions
grep -r "class\|interface\|type\|enum" apps/ packages/ services/ --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v node_modules > migration-temp/analysis/domain-concepts.txt || true

# Extract API endpoints
grep -r "app\.\|router\.\|@Get\|@Post\|@Put\|@Delete" apps/ packages/ services/ --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v node_modules > migration-temp/analysis/api-endpoints.txt || true

# Extract database models
grep -r "Schema\|Model\|Entity\|@Entity\|@Table" apps/ packages/ services/ --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v node_modules > migration-temp/analysis/database-models.txt || true

echo -e "${GREEN}✅ Domain analysis completed${NC}"

# Create migration mapping files
echo -e "${BLUE}🗺️  Creating migration mappings...${NC}"

cat > migration-temp/mappings/domain-mapping.json << 'EOF'
{
  "entities": {
    "User": "src/Domain/Entities/User.ts",
    "Auth": "src/Domain/Entities/Auth.ts",
    "Content": "src/Domain/Entities/Content.ts",
    "System": "src/Domain/Entities/System.ts"
  },
  "aggregates": {
    "UserAggregate": "src/Domain/Aggregates/UserAggregate.ts",
    "AuthAggregate": "src/Domain/Aggregates/AuthAggregate.ts",
    "ContentAggregate": "src/Domain/Aggregates/ContentAggregate.ts",
    "SystemAggregate": "src/Domain/Aggregates/SystemAggregate.ts"
  },
  "valueObjects": {
    "UserTypes": "src/Domain/ValueObjects/UserTypes.ts",
    "AuthTypes": "src/Domain/ValueObjects/AuthTypes.ts",
    "ApiTypes": "src/Domain/ValueObjects/ApiTypes.ts",
    "CommonTypes": "src/Domain/ValueObjects/CommonTypes.ts"
  }
}
EOF

cat > migration-temp/mappings/service-mapping.json << 'EOF'
{
  "backend_services": {
    "apps/backend/api": "src/Presentation/Api/Controllers",
    "apps/backend/auth": "src/Presentation/Api/Controllers/Auth",
    "apps/backend/graphql": "src/Presentation/Api/Controllers/GraphQL",
    "apps/backend/webhooks": "src/Presentation/Api/Controllers/Webhooks",
    "apps/backend/cron": "src/Infrastructure/Services/CronService.ts",
    "apps/backend/workers": "src/Infrastructure/Services/WorkerService.ts"
  },
  "frontend_apps": {
    "apps/frontend/web": "src/Presentation/Web/Pages/Main",
    "apps/frontend/admin": "src/Presentation/Web/Pages/Admin",
    "apps/frontend/landing": "src/Presentation/Web/Pages/Landing",
    "apps/frontend/docs": "src/Presentation/Web/Pages/Docs",
    "apps/frontend/mobile": "src/Presentation/Web/Pages/Mobile",
    "apps/frontend/desktop": "src/Presentation/Web/Pages/Desktop"
  }
}
EOF

echo -e "${GREEN}✅ Migration mappings created${NC}"

# Create migration status tracker
cat > migration-temp/migration-status.json << 'EOF'
{
  "phases": {
    "00-prepare": "completed",
    "01-domain": "pending",
    "02-application": "pending",
    "03-infrastructure": "pending",
    "04-presentation": "pending",
    "05-shared-kernel": "pending",
    "06-configuration": "pending",
    "07-testing": "pending",
    "08-dependencies": "pending",
    "09-startup": "pending",
    "10-cleanup": "pending",
    "11-validation": "pending"
  },
  "started_at": "'$(date -Iseconds)'",
  "current_phase": "01-domain"
}
EOF

echo -e "${GREEN}🎉 Migration preparation completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Backup created: ../v3-backup"
echo -e "  • DDD structure created in src/"
echo -e "  • Source files inventoried: $(wc -l < migration-temp/inventory/current-source-files.txt) files"
echo -e "  • Test files inventoried: $(wc -l < migration-temp/inventory/current-test-files.txt) files"
echo -e "  • Package.json files found: $(wc -l < migration-temp/inventory/package-json-files.txt) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/01-migrate-domain.sh${NC}"
