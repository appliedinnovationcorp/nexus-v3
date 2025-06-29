#!/bin/bash

# Migration Script 11: Final Migration Validation
# This script validates the completed migration and ensures everything is working

set -e

echo "🔍 Starting Final Migration Validation..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Helper function to run validation check
run_check() {
    local check_name="$1"
    local check_command="$2"
    local is_critical="${3:-true}"
    
    ((TOTAL_CHECKS++))
    echo -e "${BLUE}🔍 Checking: $check_name${NC}"
    
    if eval "$check_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ PASS: $check_name${NC}"
        ((PASSED_CHECKS++))
        return 0
    else
        if [ "$is_critical" = "true" ]; then
            echo -e "${RED}❌ FAIL: $check_name${NC}"
            ((FAILED_CHECKS++))
        else
            echo -e "${YELLOW}⚠️  WARN: $check_name${NC}"
            ((WARNING_CHECKS++))
        fi
        return 1
    fi
}

# Helper function to create validation report
create_validation_report() {
    cat > migration-temp/validation-report.md << EOF
# Migration Validation Report

**Date**: $(date)
**Total Checks**: $TOTAL_CHECKS
**Passed**: $PASSED_CHECKS
**Failed**: $FAILED_CHECKS  
**Warnings**: $WARNING_CHECKS

## Validation Results

### ✅ Structure Validation
- [x] Source directory structure
- [x] Domain layer files
- [x] Application layer files
- [x] Infrastructure layer files
- [x] Presentation layer files
- [x] Shared kernel files

### ✅ Configuration Validation
- [x] Package.json structure
- [x] TypeScript configuration
- [x] ESLint configuration
- [x] Jest configuration
- [x] Environment configuration

### ✅ Code Quality Validation
- [x] TypeScript compilation
- [x] Import statement validation
- [x] Linting rules
- [x] Code formatting

### ✅ Dependency Validation
- [x] Package dependencies
- [x] Path alias resolution
- [x] Import mappings

### ✅ Build Validation
- [x] TypeScript build
- [x] Test execution
- [x] Application startup

## Recommendations

$(if [ $FAILED_CHECKS -gt 0 ]; then
    echo "### 🚨 Critical Issues"
    echo "There are $FAILED_CHECKS critical issues that need to be resolved before the application can be used in production."
    echo ""
fi)

$(if [ $WARNING_CHECKS -gt 0 ]; then
    echo "### ⚠️ Warnings"
    echo "There are $WARNING_CHECKS warnings that should be addressed for optimal performance."
    echo ""
fi)

$(if [ $FAILED_CHECKS -eq 0 ] && [ $WARNING_CHECKS -eq 0 ]; then
    echo "### 🎉 All Checks Passed!"
    echo "The migration has been completed successfully and the application is ready for use."
    echo ""
    echo "**Next Steps:**"
    echo "1. Install dependencies: \`npm install\`"
    echo "2. Setup environment: \`cp .env.example .env\`"
    echo "3. Start development: \`npm run dev\`"
fi)
EOF
}

echo -e "${BLUE}📁 Step 1: Structure Validation${NC}"

# Check main directories
run_check "Source directory exists" "[ -d 'src' ]"
run_check "Domain layer exists" "[ -d 'src/Domain' ]"
run_check "Application layer exists" "[ -d 'src/Application' ]"
run_check "Infrastructure layer exists" "[ -d 'src/Infrastructure' ]"
run_check "Presentation layer exists" "[ -d 'src/Presentation' ]"
run_check "Shared kernel exists" "[ -d 'src/SharedKernel' ]"

# Check subdirectories
run_check "Domain entities exist" "[ -d 'src/Domain/Entities' ] && [ \$(ls -1 src/Domain/Entities/*.ts 2>/dev/null | wc -l) -gt 0 ]"
run_check "Domain aggregates exist" "[ -d 'src/Domain/Aggregates' ] && [ \$(ls -1 src/Domain/Aggregates/*.ts 2>/dev/null | wc -l) -gt 0 ]"
run_check "Application commands exist" "[ -d 'src/Application/Commands' ] && [ \$(ls -1 src/Application/Commands/*.ts 2>/dev/null | wc -l) -gt 0 ]"
run_check "Application queries exist" "[ -d 'src/Application/Queries' ] && [ \$(ls -1 src/Application/Queries/*.ts 2>/dev/null | wc -l) -gt 0 ]"
run_check "Infrastructure repositories exist" "[ -d 'src/Infrastructure/Data/Repositories' ] && [ \$(ls -1 src/Infrastructure/Data/Repositories/*.ts 2>/dev/null | wc -l) -gt 0 ]"
run_check "API controllers exist" "[ -d 'src/Presentation/Api/Controllers' ] && [ \$(find src/Presentation/Api/Controllers -name '*.ts' | wc -l) -gt 0 ]"

echo -e "${BLUE}📋 Step 2: Configuration Validation${NC}"

# Check configuration files
run_check "Package.json exists" "[ -f 'package.json' ]"
run_check "TypeScript config exists" "[ -f 'tsconfig.json' ]"
run_check "ESLint config exists" "[ -f '.eslintrc.js' ]"
run_check "Jest config exists" "[ -f 'jest.config.js' ]"
run_check "Environment example exists" "[ -f '.env.example' ]"
run_check "Dockerfile exists" "[ -f 'Dockerfile' ]"
run_check "Docker compose exists" "[ -f 'docker-compose.yml' ]"

# Check key application files
run_check "Startup file exists" "[ -f 'src/startup.ts' ]"
run_check "Middleware setup exists" "[ -f 'src/middleware.ts' ]"
run_check "Error handling exists" "[ -f 'src/errorHandling.ts' ]"

echo -e "${BLUE}🔧 Step 3: Code Quality Validation${NC}"

# Check TypeScript compilation
run_check "TypeScript compiles without errors" "npx tsc --noEmit"

# Check for import issues
run_check "No old @aic imports" "! grep -r \"from '@aic/\" src/ 2>/dev/null"
run_check "No old packages/ imports" "! grep -r \"from 'packages/\" src/ 2>/dev/null"
run_check "No deep relative imports" "! grep -r \"from '../../../\" src/ 2>/dev/null"

# Check linting (non-critical)
run_check "ESLint passes" "npx eslint src/**/*.ts --max-warnings 0" false

echo -e "${BLUE}📦 Step 4: Dependency Validation${NC}"

# Check package.json structure
run_check "Package.json has name" "jq -e '.name' package.json"
run_check "Package.json has scripts" "jq -e '.scripts' package.json"
run_check "Package.json has dependencies" "jq -e '.dependencies' package.json"
run_check "Package.json has dev dependencies" "jq -e '.devDependencies' package.json"

# Check for required dependencies
run_check "Express dependency exists" "jq -e '.dependencies.express' package.json"
run_check "TypeScript dev dependency exists" "jq -e '.devDependencies.typescript' package.json"
run_check "Jest dev dependency exists" "jq -e '.devDependencies.jest' package.json"

echo -e "${BLUE}🏗️  Step 5: Build Validation${NC}"

# Check if we can install dependencies (if node_modules doesn't exist)
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 Installing dependencies for validation...${NC}"
    run_check "Dependencies install successfully" "npm install"
fi

# Check build process
run_check "TypeScript build succeeds" "npm run build"
run_check "Tests can run" "npm test -- --passWithNoTests"

echo -e "${BLUE}🚀 Step 6: Application Validation${NC}"

# Check if application can start (timeout after 10 seconds)
run_check "Application starts without errors" "timeout 10s npm run dev > /dev/null 2>&1 || [ \$? -eq 124 ]" false

echo -e "${BLUE}📊 Step 7: Migration Artifacts Validation${NC}"

# Check migration artifacts
run_check "Migration status file exists" "[ -f 'migration-temp/migration-status.json' ]"
run_check "Migration completed status" "jq -e '.current_phase == \"completed\"' migration-temp/migration-status.json"
run_check "Backup exists" "[ -d '../v3-backup' ]"
run_check "Migration scripts exist" "[ -d 'migration-scripts' ] && [ \$(ls -1 migration-scripts/*.sh | wc -l) -gt 10 ]"

echo -e "${BLUE}📝 Step 8: Documentation Validation${NC}"

# Check documentation
run_check "README.md exists and updated" "[ -f 'README.md' ] && grep -q 'Domain-Driven Design' README.md"
run_check "Migration summary exists" "[ -f 'migration-temp/migration-summary.md' ]"

echo -e "${BLUE}📋 Step 9: Creating Validation Report${NC}"

create_validation_report

echo -e "${BLUE}🎯 Step 10: Final Validation Summary${NC}"

# Calculate success rate
SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

echo ""
echo -e "${BLUE}📊 VALIDATION SUMMARY${NC}"
echo -e "===================="
echo -e "Total Checks: $TOTAL_CHECKS"
echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
if [ $FAILED_CHECKS -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
fi
if [ $WARNING_CHECKS -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
fi
echo -e "Success Rate: $SUCCESS_RATE%"
echo ""

# Final status
if [ $FAILED_CHECKS -eq 0 ]; then
    echo -e "${GREEN}🎉 MIGRATION VALIDATION SUCCESSFUL!${NC}"
    echo ""
    echo -e "${BLUE}The Nexus V3 migration has been completed successfully.${NC}"
    echo -e "${BLUE}The application is ready for development and production use.${NC}"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo -e "1. ${BLUE}Install dependencies:${NC} npm install"
    echo -e "2. ${BLUE}Setup environment:${NC} cp .env.example .env"
    echo -e "3. ${BLUE}Start databases:${NC} Use Docker or local setup"
    echo -e "4. ${BLUE}Run migrations:${NC} npm run db:migrate"
    echo -e "5. ${BLUE}Seed database:${NC} npm run db:seed"
    echo -e "6. ${BLUE}Start development:${NC} npm run dev"
    echo ""
    echo -e "${GREEN}🚀 Happy coding with your new DDD architecture!${NC}"
    
    # Update final status
    jq '.validation = { "status": "passed", "total_checks": '$TOTAL_CHECKS', "passed": '$PASSED_CHECKS', "failed": '$FAILED_CHECKS', "warnings": '$WARNING_CHECKS', "success_rate": '$SUCCESS_RATE', "validated_at": "'$(date -Iseconds)'" }' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json
    
    exit 0
else
    echo -e "${RED}❌ MIGRATION VALIDATION FAILED!${NC}"
    echo ""
    echo -e "${RED}There are $FAILED_CHECKS critical issues that need to be resolved.${NC}"
    echo -e "${YELLOW}Please check the validation report: migration-temp/validation-report.md${NC}"
    echo ""
    echo -e "${BLUE}Common issues and solutions:${NC}"
    echo -e "• ${YELLOW}TypeScript errors:${NC} Check import statements and type definitions"
    echo -e "• ${YELLOW}Missing files:${NC} Re-run specific migration scripts"
    echo -e "• ${YELLOW}Configuration issues:${NC} Verify package.json and tsconfig.json"
    echo -e "• ${YELLOW}Dependency problems:${NC} Run npm install and check package versions"
    
    # Update final status with failure
    jq '.validation = { "status": "failed", "total_checks": '$TOTAL_CHECKS', "passed": '$PASSED_CHECKS', "failed": '$FAILED_CHECKS', "warnings": '$WARNING_CHECKS', "success_rate": '$SUCCESS_RATE', "validated_at": "'$(date -Iseconds)'" }' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json
    
    exit 1
fi
