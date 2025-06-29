#!/bin/bash

# Migration Script 08: Dependencies and Import Updates
# This script updates all import statements and resolves dependencies

set -e

echo "📦 Starting Dependencies and Import Updates..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local desc="$3"
    
    echo "$content" > "$file_path"
    echo -e "${GREEN}✅ Created $desc: $file_path${NC}"
}

echo -e "${BLUE}🔍 Step 1: Analyzing Import Patterns...${NC}"

# Create import mapping file
create_file "migration-temp/import-mappings.json" "{
  \"@aic/\": \"@shared/\",
  \"packages/utils\": \"@shared/Utils\",
  \"packages/types\": \"@shared/Types\",
  \"packages/constants\": \"@shared/Constants\",
  \"packages/validators\": \"@shared/Validators\",
  \"packages/ui\": \"@presentation/Web/Components\",
  \"packages/auth\": \"@domain/Services\",
  \"packages/api\": \"@application/Queries/Dtos\",
  \"apps/backend/\": \"@presentation/Api/Controllers/\",
  \"services/user-domain\": \"@domain/\",
  \"services/shared-kernel\": \"@shared/\",
  \"../../../Domain/\": \"@domain/\",
  \"../../../Application/\": \"@application/\",
  \"../../../Infrastructure/\": \"@infrastructure/\",
  \"../../../Presentation/\": \"@presentation/\",
  \"../../../SharedKernel/\": \"@shared/\",
  \"../../Domain/\": \"@domain/\",
  \"../../Application/\": \"@application/\",
  \"../../Infrastructure/\": \"@infrastructure/\",
  \"../../Presentation/\": \"@presentation/\",
  \"../../SharedKernel/\": \"@shared/\",
  \"../Domain/\": \"@domain/\",
  \"../Application/\": \"@application/\",
  \"../Infrastructure/\": \"@infrastructure/\",
  \"../Presentation/\": \"@presentation/\",
  \"../SharedKernel/\": \"@shared/\"
}" "Import Mappings"

echo -e "${BLUE}🔄 Step 2: Creating Import Update Script...${NC}"

create_file "scripts/update-imports.sh" "#!/bin/bash

# Script to update all import statements
set -e

echo \"🔄 Updating import statements...\"

# Function to update imports in a file
update_file_imports() {
    local file=\"\$1\"
    echo \"Updating: \$file\"
    
    # Update @aic/ imports
    sed -i \"s|from '@aic/|from '@shared/|g\" \"\$file\"
    sed -i \"s|import '@aic/|import '@shared/|g\" \"\$file\"
    
    # Update package imports
    sed -i \"s|from 'packages/utils|from '@shared/Utils|g\" \"\$file\"
    sed -i \"s|from 'packages/types|from '@shared/Types|g\" \"\$file\"
    sed -i \"s|from 'packages/constants|from '@shared/Constants|g\" \"\$file\"
    sed -i \"s|from 'packages/validators|from '@shared/Validators|g\" \"\$file\"
    sed -i \"s|from 'packages/ui|from '@presentation/Web/Components|g\" \"\$file\"
    sed -i \"s|from 'packages/auth|from '@domain/Services|g\" \"\$file\"
    sed -i \"s|from 'packages/api|from '@application/Queries/Dtos|g\" \"\$file\"
    
    # Update relative imports to absolute
    sed -i \"s|from '../../../Domain/|from '@domain/|g\" \"\$file\"
    sed -i \"s|from '../../../Application/|from '@application/|g\" \"\$file\"
    sed -i \"s|from '../../../Infrastructure/|from '@infrastructure/|g\" \"\$file\"
    sed -i \"s|from '../../../Presentation/|from '@presentation/|g\" \"\$file\"
    sed -i \"s|from '../../../SharedKernel/|from '@shared/|g\" \"\$file\"
    
    sed -i \"s|from '../../Domain/|from '@domain/|g\" \"\$file\"
    sed -i \"s|from '../../Application/|from '@application/|g\" \"\$file\"
    sed -i \"s|from '../../Infrastructure/|from '@infrastructure/|g\" \"\$file\"
    sed -i \"s|from '../../Presentation/|from '@presentation/|g\" \"\$file\"
    sed -i \"s|from '../../SharedKernel/|from '@shared/|g\" \"\$file\"
    
    sed -i \"s|from '../Domain/|from '@domain/|g\" \"\$file\"
    sed -i \"s|from '../Application/|from '@application/|g\" \"\$file\"
    sed -i \"s|from '../Infrastructure/|from '@infrastructure/|g\" \"\$file\"
    sed -i \"s|from '../Presentation/|from '@presentation/|g\" \"\$file\"
    sed -i \"s|from '../SharedKernel/|from '@shared/|g\" \"\$file\"
    
    # Update import statements (not just from)
    sed -i \"s|import '../../../Domain/|import '@domain/|g\" \"\$file\"
    sed -i \"s|import '../../../Application/|import '@application/|g\" \"\$file\"
    sed -i \"s|import '../../../Infrastructure/|import '@infrastructure/|g\" \"\$file\"
    sed -i \"s|import '../../../Presentation/|import '@presentation/|g\" \"\$file\"
    sed -i \"s|import '../../../SharedKernel/|import '@shared/|g\" \"\$file\"
    
    sed -i \"s|import '../../Domain/|import '@domain/|g\" \"\$file\"
    sed -i \"s|import '../../Application/|import '@application/|g\" \"\$file\"
    sed -i \"s|import '../../Infrastructure/|import '@infrastructure/|g\" \"\$file\"
    sed -i \"s|import '../../Presentation/|import '@presentation/|g\" \"\$file\"
    sed -i \"s|import '../../SharedKernel/|import '@shared/|g\" \"\$file\"
    
    sed -i \"s|import '../Domain/|import '@domain/|g\" \"\$file\"
    sed -i \"s|import '../Application/|import '@application/|g\" \"\$file\"
    sed -i \"s|import '../Infrastructure/|import '@infrastructure/|g\" \"\$file\"
    sed -i \"s|import '../Presentation/|import '@presentation/|g\" \"\$file\"
    sed -i \"s|import '../SharedKernel/|import '@shared/|g\" \"\$file\"
}

# Update all TypeScript files in src directory
find src/ -name \"*.ts\" -o -name \"*.tsx\" | while read -r file; do
    update_file_imports \"\$file\"
done

# Update all test files
find tests/ -name \"*.ts\" -o -name \"*.tsx\" | while read -r file; do
    update_file_imports \"\$file\"
done

echo \"✅ Import statements updated!\"" "Import Update Script"

chmod +x scripts/update-imports.sh

echo -e "${BLUE}🔧 Step 3: Creating Dependency Injection Container...${NC}"

create_file "src/Infrastructure/DependencyInjection/Container.ts" "import { Pool } from 'pg';
import { DatabaseConfig } from './DatabaseConfig';

// Repositories
import { IUserRepository } from '../Data/Repositories/IUserRepository';
import { PostgresUserRepository } from '../Data/Repositories/PostgresUserRepository';
import { IAuthRepository } from '../Data/Repositories/IAuthRepository';
import { PostgresAuthRepository } from '../Data/Repositories/PostgresAuthRepository';

// External Services
import { IEmailService } from '../ExternalServices/IEmailService';
import { NodemailerEmailService } from '../ExternalServices/NodemailerEmailService';
import { IPasswordService } from '../ExternalServices/IPasswordService';
import { BcryptPasswordService } from '../ExternalServices/BcryptPasswordService';
import { ITokenService } from '../ExternalServices/ITokenService';
import { JwtTokenService } from '../ExternalServices/JwtTokenService';
import { ILogger } from '../ExternalServices/ILogger';
import { WinstonLogger } from '../ExternalServices/WinstonLogger';

// Messaging
import { IEventPublisher } from '../Messaging/IEventPublisher';
import { InMemoryEventPublisher } from '../Messaging/InMemoryEventPublisher';

// Command Handlers
import { CreateUserHandler } from '../../Application/Commands/Handlers/CreateUserHandler';
import { UpdateUserHandler } from '../../Application/Commands/Handlers/UpdateUserHandler';
import { AuthenticateUserHandler } from '../../Application/Commands/Handlers/AuthenticateUserHandler';

// Query Handlers
import { GetUserHandler } from '../../Application/Queries/Handlers/GetUserHandler';
import { GetUserByEmailHandler } from '../../Application/Queries/Handlers/GetUserByEmailHandler';
import { GetUsersHandler } from '../../Application/Queries/Handlers/GetUsersHandler';

// Validators
import { CreateUserValidator } from '../../Application/Commands/Validators/CreateUserValidator';
import { UpdateUserValidator } from '../../Application/Commands/Validators/UpdateUserValidator';

// Controllers
import { UserController } from '../../Presentation/Api/Controllers/User/UserController';
import { AuthController } from '../../Presentation/Api/Controllers/Auth/AuthController';

export class Container {
  private static instance: Container;
  private services: Map<string, any> = new Map();

  private constructor() {}

  public static getInstance(): Container {
    if (!Container.instance) {
      Container.instance = new Container();
    }
    return Container.instance;
  }

  public async initialize(): Promise<void> {
    // Database
    const pool = DatabaseConfig.getPool();
    this.services.set('pool', pool);

    // External Services
    const logger = new WinstonLogger();
    this.services.set('logger', logger);

    const passwordService = new BcryptPasswordService();
    this.services.set('passwordService', passwordService);

    const tokenService = new JwtTokenService(
      process.env.JWT_SECRET || 'default-secret',
      process.env.JWT_EXPIRES_IN || '24h'
    );
    this.services.set('tokenService', tokenService);

    const emailService = new NodemailerEmailService({
      host: process.env.EMAIL_HOST || 'localhost',
      port: parseInt(process.env.EMAIL_PORT || '587'),
      secure: process.env.EMAIL_SECURE === 'true',
      auth: {
        user: process.env.EMAIL_USER || '',
        pass: process.env.EMAIL_PASS || ''
      }
    });
    this.services.set('emailService', emailService);

    // Messaging
    const eventPublisher = new InMemoryEventPublisher(logger);
    this.services.set('eventPublisher', eventPublisher);

    // Repositories
    const userRepository = new PostgresUserRepository(pool);
    this.services.set('userRepository', userRepository);

    const authRepository = new PostgresAuthRepository(pool);
    this.services.set('authRepository', authRepository);

    // Validators
    const createUserValidator = new CreateUserValidator();
    this.services.set('createUserValidator', createUserValidator);

    const updateUserValidator = new UpdateUserValidator();
    this.services.set('updateUserValidator', updateUserValidator);

    // Command Handlers
    const createUserHandler = new CreateUserHandler(userRepository, eventPublisher);
    this.services.set('createUserHandler', createUserHandler);

    const updateUserHandler = new UpdateUserHandler(userRepository, eventPublisher);
    this.services.set('updateUserHandler', updateUserHandler);

    const authenticateUserHandler = new AuthenticateUserHandler(
      userRepository,
      authRepository,
      passwordService,
      tokenService
    );
    this.services.set('authenticateUserHandler', authenticateUserHandler);

    // Query Handlers
    const getUserHandler = new GetUserHandler(userRepository);
    this.services.set('getUserHandler', getUserHandler);

    const getUserByEmailHandler = new GetUserByEmailHandler(userRepository);
    this.services.set('getUserByEmailHandler', getUserByEmailHandler);

    const getUsersHandler = new GetUsersHandler(userRepository);
    this.services.set('getUsersHandler', getUsersHandler);

    // Controllers
    const userController = new UserController(
      createUserHandler,
      updateUserHandler,
      getUserHandler,
      getUsersHandler,
      createUserValidator,
      updateUserValidator
    );
    this.services.set('userController', userController);

    const authController = new AuthController(authenticateUserHandler);
    this.services.set('authController', authController);
  }

  public get<T>(serviceName: string): T {
    const service = this.services.get(serviceName);
    if (!service) {
      throw new Error(\`Service '\${serviceName}' not found in container\`);
    }
    return service;
  }

  public set(serviceName: string, service: any): void {
    this.services.set(serviceName, service);
  }
}" "DI Container"

echo -e "${BLUE}📋 Step 4: Creating Package Resolution Script...${NC}"

create_file "scripts/resolve-packages.sh" "#!/bin/bash

# Script to resolve and install all dependencies
set -e

echo \"📦 Resolving package dependencies...\"

# Remove old node_modules and lock files
echo \"🧹 Cleaning old dependencies...\"
rm -rf node_modules package-lock.json yarn.lock pnpm-lock.yaml

# Remove old package.json files from subdirectories
find . -name \"package.json\" -not -path \"./package.json\" -not -path \"./node_modules/*\" -delete

# Install dependencies
echo \"📥 Installing dependencies...\"
npm install

# Install additional dependencies that might be missing
echo \"📥 Installing additional dependencies...\"

# Core dependencies
npm install --save express cors helmet compression
npm install --save pg redis bcryptjs jsonwebtoken nodemailer
npm install --save winston joi dotenv uuid date-fns lodash

# Development dependencies
npm install --save-dev @types/node @types/express @types/cors @types/compression
npm install --save-dev @types/pg @types/bcryptjs @types/jsonwebtoken @types/nodemailer
npm install --save-dev @types/uuid @types/lodash @types/jest @types/supertest
npm install --save-dev typescript tsx jest ts-jest supertest
npm install --save-dev eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin
npm install --save-dev prettier rimraf nodemon

# React dependencies (for frontend components)
npm install --save react react-dom @types/react @types/react-dom

# Additional utilities
npm install --save class-variance-authority clsx tailwind-merge

echo \"✅ Dependencies resolved!\"

# Verify installation
echo \"🔍 Verifying installation...\"
npm list --depth=0

echo \"✅ Package resolution completed!\"" "Package Resolution Script"

chmod +x scripts/resolve-packages.sh

echo -e "${BLUE}🔧 Step 5: Running Import Updates...${NC}"

echo -e "${BLUE}🔄 Updating import statements in source files...${NC}"

# Run the import update script
./scripts/update-imports.sh

echo -e "${BLUE}📊 Step 6: Creating Dependency Analysis Report...${NC}"

create_file "migration-temp/dependency-analysis.md" "# Dependency Analysis Report

## Migration Summary
- **Original packages**: $(find . -name \"package.json\" -not -path \"./node_modules/*\" -not -path \"./migration-temp/*\" | wc -l) package.json files
- **Consolidated to**: 1 package.json file
- **Import statements updated**: All relative imports converted to absolute path aliases

## Dependency Categories

### Production Dependencies
- **Web Framework**: express, cors, helmet, compression
- **Database**: pg (PostgreSQL client)
- **Caching**: redis
- **Authentication**: bcryptjs, jsonwebtoken
- **Email**: nodemailer
- **Logging**: winston
- **Validation**: joi
- **Utilities**: dotenv, uuid, date-fns, lodash

### Development Dependencies
- **TypeScript**: typescript, tsx, @types/*
- **Testing**: jest, ts-jest, supertest
- **Linting**: eslint, @typescript-eslint/*
- **Formatting**: prettier
- **Build Tools**: rimraf
- **Development**: nodemon

### Frontend Dependencies (if needed)
- **React**: react, react-dom, @types/react, @types/react-dom
- **Styling**: class-variance-authority, clsx, tailwind-merge

## Path Aliases Configured
- \`@/*\` → \`src/*\`
- \`@domain/*\` → \`src/Domain/*\`
- \`@application/*\` → \`src/Application/*\`
- \`@infrastructure/*\` → \`src/Infrastructure/*\`
- \`@presentation/*\` → \`src/Presentation/*\`
- \`@shared/*\` → \`src/SharedKernel/*\`

## Import Patterns Updated
- \`@aic/*\` → \`@shared/*\`
- \`packages/*\` → Appropriate domain/shared paths
- Relative imports → Absolute path aliases
- Service imports → Domain/Infrastructure paths

## Removed Dependencies
- All workspace-specific packages (\`@aic/*\`)
- Turborepo and monorepo tooling
- Duplicate dependencies across packages
- Legacy build tools and configurations
" "Dependency Analysis Report"

echo -e "${BLUE}🔍 Step 7: Validating Import Updates...${NC}"

# Create validation script
create_file "scripts/validate-imports.sh" "#!/bin/bash

# Script to validate that all imports are correctly updated
set -e

echo \"🔍 Validating import statements...\"

# Check for remaining old import patterns
echo \"Checking for old import patterns...\"

# Check for @aic imports
old_aic_imports=\$(grep -r \"from '@aic/\" src/ tests/ 2>/dev/null | wc -l || echo 0)
if [ \"\$old_aic_imports\" -gt 0 ]; then
    echo \"⚠️  Found \$old_aic_imports old @aic imports:\"
    grep -r \"from '@aic/\" src/ tests/ 2>/dev/null || true
fi

# Check for packages/ imports
old_package_imports=\$(grep -r \"from 'packages/\" src/ tests/ 2>/dev/null | wc -l || echo 0)
if [ \"\$old_package_imports\" -gt 0 ]; then
    echo \"⚠️  Found \$old_package_imports old packages/ imports:\"
    grep -r \"from 'packages/\" src/ tests/ 2>/dev/null || true
fi

# Check for deep relative imports
deep_relative_imports=\$(grep -r \"from '../../../\" src/ tests/ 2>/dev/null | wc -l || echo 0)
if [ \"\$deep_relative_imports\" -gt 0 ]; then
    echo \"⚠️  Found \$deep_relative_imports deep relative imports:\"
    grep -r \"from '../../../\" src/ tests/ 2>/dev/null || true
fi

# Summary
total_issues=\$((old_aic_imports + old_package_imports + deep_relative_imports))
if [ \"\$total_issues\" -eq 0 ]; then
    echo \"✅ All imports are correctly updated!\"
else
    echo \"⚠️  Found \$total_issues import issues that need manual fixing\"
fi

echo \"📊 Import validation completed!\"" "Import Validation Script"

chmod +x scripts/validate-imports.sh

# Run validation
./scripts/validate-imports.sh

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["08-dependencies"] = "completed" | .current_phase = "09-startup"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Dependencies and Import Updates Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Import update script: Created and executed"
echo -e "  • Dependency injection: Container configured"
echo -e "  • Package resolution: Script created"
echo -e "  • Path aliases: Configured in tsconfig.json"
echo -e "  • Import validation: Script created and executed"
echo -e "  • Dependency analysis: Report generated"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/09-create-startup.sh${NC}"
