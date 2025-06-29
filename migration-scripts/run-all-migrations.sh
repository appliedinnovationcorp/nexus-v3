#!/bin/bash

# Master Migration Script
# This script runs all migration steps in sequence

set -e

echo "🚀 Starting Complete Migration Process..."
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Migration steps
MIGRATION_STEPS=(
    "00-prepare-migration.sh"
    "01-migrate-domain.sh"
    "02-migrate-application.sh"
    "03-migrate-infrastructure.sh"
    "04-migrate-presentation.sh"
    "05-migrate-shared-kernel.sh"
    "06-migrate-configuration.sh"
    "07-migrate-testing.sh"
    "08-update-dependencies.sh"
    "09-create-startup.sh"
    "10-cleanup-old-structure.sh"
    "11-validate-migration.sh"
)

# Function to run a migration step
run_migration_step() {
    local step="$1"
    local step_number="${step:0:2}"
    local step_name="${step:3:-3}"
    
    echo ""
    echo -e "${BLUE}🔄 Running Step $step_number: $step_name${NC}"
    echo "================================================"
    
    if [ -f "$SCRIPT_DIR/$step" ]; then
        if bash "$SCRIPT_DIR/$step"; then
            echo -e "${GREEN}✅ Step $step_number completed successfully${NC}"
        else
            echo -e "${RED}❌ Step $step_number failed${NC}"
            echo -e "${YELLOW}Migration stopped at step $step_number${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Migration script not found: $step${NC}"
        exit 1
    fi
}

# Function to show progress
show_progress() {
    local current="$1"
    local total="$2"
    local percentage=$((current * 100 / total))
    
    echo ""
    echo -e "${BLUE}📊 Migration Progress: $current/$total ($percentage%)${NC}"
    
    # Simple progress bar
    local bar_length=50
    local filled_length=$((percentage * bar_length / 100))
    local bar=""
    
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    echo -e "${BLUE}[$bar] $percentage%${NC}"
}

# Check if we're in the right directory
if [ ! -f "package.json" ] && [ ! -f "current-tree.md" ]; then
    echo -e "${RED}❌ Please run this script from the project root directory${NC}"
    exit 1
fi

# Show migration plan
echo -e "${BLUE}📋 Migration Plan:${NC}"
echo "=================="
for i in "${!MIGRATION_STEPS[@]}"; do
    step="${MIGRATION_STEPS[$i]}"
    step_number="${step:0:2}"
    step_name="${step:3:-3}"
    echo "  $((i+1)). Step $step_number: $step_name"
done
echo ""

# Confirm before starting
read -p "Do you want to proceed with the complete migration? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Migration cancelled."
    exit 0
fi

# Record start time
START_TIME=$(date +%s)
echo ""
echo -e "${GREEN}🚀 Starting migration at $(date)${NC}"

# Run all migration steps
for i in "${!MIGRATION_STEPS[@]}"; do
    step="${MIGRATION_STEPS[$i]}"
    show_progress $((i+1)) ${#MIGRATION_STEPS[@]}
    run_migration_step "$step"
done

# Calculate total time
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo -e "${GREEN}🎉 MIGRATION COMPLETED SUCCESSFULLY!${NC}"
echo "===================================="
echo -e "${BLUE}Total time: ${MINUTES}m ${SECONDS}s${NC}"
echo -e "${BLUE}Completed at: $(date)${NC}"
echo ""

# Show final summary
echo -e "${GREEN}📊 Migration Summary:${NC}"
echo "===================="
echo "✅ All 12 migration steps completed successfully"
echo "✅ Domain-Driven Design architecture implemented"
echo "✅ Monorepo structure consolidated to clean DDD"
echo "✅ All dependencies resolved and imports updated"
echo "✅ Comprehensive testing setup created"
echo "✅ Production-ready configuration established"
echo "✅ Migration validated and ready for use"
echo ""

echo -e "${BLUE}📁 New Project Structure:${NC}"
echo "========================="
echo "src/"
echo "├── Domain/           # Core business logic"
echo "├── Application/      # Use cases and handlers"
echo "├── Infrastructure/   # Data access and external services"
echo "├── Presentation/     # Web UI and API controllers"
echo "└── SharedKernel/     # Common utilities and types"
echo ""

echo -e "${GREEN}🚀 Next Steps:${NC}"
echo "=============="
echo "1. Install dependencies:    npm install"
echo "2. Setup environment:       cp .env.example .env"
echo "3. Start databases:         Use Docker or local setup"
echo "4. Run migrations:          npm run db:migrate"
echo "5. Seed database:           npm run db:seed"
echo "6. Start development:       npm run dev"
echo ""

echo -e "${BLUE}📚 Documentation:${NC}"
echo "=================="
echo "• README.md                 - Updated project documentation"
echo "• migration-temp/           - Migration reports and analysis"
echo "• migration-scripts/        - All migration scripts for reference"
echo "• ../v3-backup/            - Complete backup of original structure"
echo ""

echo -e "${GREEN}🎯 The migration is complete and your application is ready!${NC}"
echo -e "${BLUE}Happy coding with your new Domain-Driven Design architecture! 🚀${NC}"
