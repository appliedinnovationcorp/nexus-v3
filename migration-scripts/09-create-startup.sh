#!/bin/bash

# Migration Script 09: Startup and Application Bootstrap
# This script creates the main application startup file and configuration

set -e

echo "🚀 Starting Application Startup Creation..."

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

echo -e "${BLUE}🏗️  Step 1: Creating Main Startup File...${NC}"

create_file "src/startup.ts" "import 'reflect-metadata';
import { config } from 'dotenv';
import express, { Express } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';

import { Container } from '@infrastructure/DependencyInjection/Container';
import { DatabaseSetup } from '@infrastructure/Data/DatabaseSetup';
import { setupRoutes } from '@presentation/Api/Routes';
import { setupMiddleware } from './middleware';
import { setupErrorHandling } from './errorHandling';
import { ILogger } from '@infrastructure/ExternalServices/ILogger';

// Load environment variables
config();

export async function createApp(): Promise<Express> {
  const app = express();

  // Initialize dependency injection container
  const container = Container.getInstance();
  await container.initialize();

  // Get logger
  const logger = container.get<ILogger>('logger');

  // Setup database
  const databaseSetup = new DatabaseSetup();
  await databaseSetup.initialize();
  logger.info('Database initialized successfully');

  // Basic middleware
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: [\"'self'\"],
        styleSrc: [\"'self'\", \"'unsafe-inline'\"],
        scriptSrc: [\"'self'\"],
        imgSrc: [\"'self'\", 'data:', 'https:'],
      },
    },
  }));

  app.use(cors({
    origin: process.env.CORS_ORIGIN || 'http://localhost:3000',
    credentials: process.env.CORS_CREDENTIALS === 'true',
  }));

  app.use(compression());
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));

  // Setup custom middleware
  setupMiddleware(app, container);

  // Setup API routes
  const apiRoutes = setupRoutes(
    container.get('userController'),
    container.get('authController')
  );
  app.use('/api', apiRoutes);

  // Setup error handling
  setupErrorHandling(app, logger);

  logger.info('Application initialized successfully');
  return app;
}

export async function startServer(): Promise<void> {
  try {
    const app = await createApp();
    const port = parseInt(process.env.PORT || '3000');
    
    const server = app.listen(port, () => {
      console.log(\`🚀 Server running on port \${port}\`);
      console.log(\`📊 Environment: \${process.env.NODE_ENV || 'development'}\`);
      console.log(\`🔗 API: http://localhost:\${port}/api\`);
      console.log(\`❤️  Health: http://localhost:\${port}/api/health\`);
    });

    // Graceful shutdown
    const gracefulShutdown = async (signal: string) => {
      console.log(\`\n📴 Received \${signal}. Starting graceful shutdown...\`);
      
      server.close(async () => {
        console.log('🔌 HTTP server closed');
        
        try {
          // Close database connections
          const { DatabaseConfig } = await import('@infrastructure/Data/DatabaseConfig');
          await DatabaseConfig.closePool();
          console.log('🗄️  Database connections closed');
          
          console.log('✅ Graceful shutdown completed');
          process.exit(0);
        } catch (error) {
          console.error('❌ Error during shutdown:', error);
          process.exit(1);
        }
      });
    };

    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));

  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Start server if this file is run directly
if (require.main === module) {
  startServer().catch(console.error);
}" "Main Startup File"

echo -e "${BLUE}⚙️  Step 2: Creating Middleware Setup...${NC}"

create_file "src/middleware.ts" "import { Express, Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import { Container } from '@infrastructure/DependencyInjection/Container';
import { ILogger } from '@infrastructure/ExternalServices/ILogger';
import { createAuthMiddleware } from '@presentation/Api/Middleware/AuthMiddleware';

export function setupMiddleware(app: Express, container: Container): void {
  const logger = container.get<ILogger>('logger');

  // Request logging middleware
  app.use((req: Request, res: Response, next: NextFunction) => {
    const start = Date.now();
    
    res.on('finish', () => {
      const duration = Date.now() - start;
      logger.info('HTTP Request', {
        method: req.method,
        url: req.url,
        statusCode: res.statusCode,
        duration: \`\${duration}ms\`,
        userAgent: req.get('User-Agent'),
        ip: req.ip
      });
    });
    
    next();
  });

  // Rate limiting
  const limiter = rateLimit({
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000'), // 1 minute
    max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS || '100'), // limit each IP to 100 requests per windowMs
    message: {
      error: 'Too many requests from this IP, please try again later.'
    },
    standardHeaders: true,
    legacyHeaders: false,
  });

  app.use('/api', limiter);

  // Auth middleware setup
  const tokenService = container.get('tokenService');
  const authMiddleware = createAuthMiddleware(tokenService);
  
  // Make auth middleware available globally
  app.set('authMiddleware', authMiddleware);

  // Health check endpoint (no auth required)
  app.get('/health', (req: Request, res: Response) => {
    res.status(200).json({
      status: 'OK',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: process.env.NODE_ENV || 'development',
      version: process.env.npm_package_version || '1.0.0'
    });
  });

  // API documentation endpoint
  app.get('/api', (req: Request, res: Response) => {
    res.status(200).json({
      name: 'Nexus V3 API',
      version: '1.0.0',
      description: 'Domain-Driven Design API',
      endpoints: {
        health: '/health',
        auth: {
          login: 'POST /api/auth/login',
          logout: 'POST /api/auth/logout',
          refresh: 'POST /api/auth/refresh'
        },
        users: {
          create: 'POST /api/users',
          get: 'GET /api/users/:id',
          list: 'GET /api/users',
          update: 'PUT /api/users/:id'
        }
      }
    });
  });
}" "Middleware Setup"

echo -e "${BLUE}🚨 Step 3: Creating Error Handling...${NC}"

create_file "src/errorHandling.ts" "import { Express, Request, Response, NextFunction } from 'express';
import { ILogger } from '@infrastructure/ExternalServices/ILogger';
import { 
  DomainException, 
  ValidationException, 
  NotFoundException, 
  UnauthorizedException,
  HttpStatusCodes 
} from '@shared/index';

interface ErrorResponse {
  error: string;
  message: string;
  statusCode: number;
  timestamp: string;
  path: string;
  details?: any;
}

export function setupErrorHandling(app: Express, logger: ILogger): void {
  // 404 handler - must be after all routes
  app.use('*', (req: Request, res: Response) => {
    const error: ErrorResponse = {
      error: 'Not Found',
      message: \`Route \${req.method} \${req.originalUrl} not found\`,
      statusCode: HttpStatusCodes.NOT_FOUND,
      timestamp: new Date().toISOString(),
      path: req.originalUrl
    };

    logger.warn('Route not found', {
      method: req.method,
      url: req.originalUrl,
      ip: req.ip
    });

    res.status(HttpStatusCodes.NOT_FOUND).json(error);
  });

  // Global error handler
  app.use((error: Error, req: Request, res: Response, next: NextFunction) => {
    // If response already sent, delegate to default Express error handler
    if (res.headersSent) {
      return next(error);
    }

    let statusCode = HttpStatusCodes.INTERNAL_SERVER_ERROR;
    let message = 'Internal Server Error';
    let details: any = undefined;

    // Handle domain exceptions
    if (error instanceof ValidationException) {
      statusCode = HttpStatusCodes.BAD_REQUEST;
      message = error.message;
      details = { validationErrors: error.validationErrors };
    } else if (error instanceof NotFoundException) {
      statusCode = HttpStatusCodes.NOT_FOUND;
      message = error.message;
    } else if (error instanceof UnauthorizedException) {
      statusCode = HttpStatusCodes.UNAUTHORIZED;
      message = error.message;
    } else if (error instanceof DomainException) {
      statusCode = HttpStatusCodes.BAD_REQUEST;
      message = error.message;
      details = { code: error.code };
    }

    const errorResponse: ErrorResponse = {
      error: error.name || 'Error',
      message,
      statusCode,
      timestamp: new Date().toISOString(),
      path: req.originalUrl,
      ...(details && { details })
    };

    // Log error
    if (statusCode >= 500) {
      logger.error('Server Error', {
        error: error.message,
        stack: error.stack,
        method: req.method,
        url: req.originalUrl,
        ip: req.ip,
        userAgent: req.get('User-Agent')
      });
    } else {
      logger.warn('Client Error', {
        error: error.message,
        method: req.method,
        url: req.originalUrl,
        ip: req.ip,
        statusCode
      });
    }

    // Send error response
    res.status(statusCode).json(errorResponse);
  });

  // Handle unhandled promise rejections
  process.on('unhandledRejection', (reason: any, promise: Promise<any>) => {
    logger.error('Unhandled Promise Rejection', {
      reason: reason?.message || reason,
      stack: reason?.stack
    });
    
    // In production, you might want to exit the process
    if (process.env.NODE_ENV === 'production') {
      console.error('Unhandled Promise Rejection. Shutting down...');
      process.exit(1);
    }
  });

  // Handle uncaught exceptions
  process.on('uncaughtException', (error: Error) => {
    logger.error('Uncaught Exception', {
      error: error.message,
      stack: error.stack
    });
    
    console.error('Uncaught Exception. Shutting down...');
    process.exit(1);
  });
}" "Error Handling"

echo -e "${BLUE}🔧 Step 4: Creating Development Scripts...${NC}"

create_file "scripts/dev.sh" "#!/bin/bash

# Development startup script
set -e

echo \"🔧 Starting development environment...\"

# Check if .env file exists
if [ ! -f \".env\" ]; then
    echo \"📝 Creating .env file from .env.example...\"
    cp .env.example .env
    echo \"⚠️  Please update .env file with your configuration\"
fi

# Start database if not running
if ! docker ps | grep -q nexus-postgres; then
    echo \"🐳 Starting PostgreSQL database...\"
    docker run -d --name nexus-postgres \
        -e POSTGRES_DB=nexus_v3 \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=password \
        -p 5432:5432 \
        postgres:15-alpine
fi

# Start Redis if not running
if ! docker ps | grep -q nexus-redis; then
    echo \"🐳 Starting Redis cache...\"
    docker run -d --name nexus-redis \
        -p 6379:6379 \
        redis:7-alpine
fi

# Wait for services
echo \"⏳ Waiting for services to be ready...\"
sleep 5

# Install dependencies if needed
if [ ! -d \"node_modules\" ]; then
    echo \"📦 Installing dependencies...\"
    npm install
fi

# Run database migrations
echo \"🗄️  Running database migrations...\"
npm run db:migrate

# Start development server
echo \"🚀 Starting development server...\"
npm run dev" "Development Script"

create_file "scripts/build.sh" "#!/bin/bash

# Production build script
set -e

echo \"🏗️  Building application for production...\"

# Clean previous build
echo \"🧹 Cleaning previous build...\"
npm run clean

# Type checking
echo \"🔍 Running type checking...\"
npm run typecheck

# Linting
echo \"📏 Running linter...\"
npm run lint

# Testing
echo \"🧪 Running tests...\"
npm test

# Build
echo \"📦 Building application...\"
npm run build

# Verify build
if [ -d \"dist\" ] && [ -f \"dist/startup.js\" ]; then
    echo \"✅ Build completed successfully!\"
    echo \"📊 Build size: \$(du -sh dist | cut -f1)\"
else
    echo \"❌ Build failed!\"
    exit 1
fi" "Build Script"

create_file "scripts/prod.sh" "#!/bin/bash

# Production startup script
set -e

echo \"🌟 Starting production server...\"

# Check if build exists
if [ ! -d \"dist\" ] || [ ! -f \"dist/startup.js\" ]; then
    echo \"❌ No build found. Please run 'npm run build' first.\"
    exit 1
fi

# Check environment
if [ \"\$NODE_ENV\" != \"production\" ]; then
    echo \"⚠️  NODE_ENV is not set to 'production'\"
    export NODE_ENV=production
fi

# Start production server
echo \"🚀 Starting production server...\"
node dist/startup.js" "Production Script"

chmod +x scripts/dev.sh scripts/build.sh scripts/prod.sh

echo -e "${BLUE}📋 Step 5: Creating Database Seeding...${NC}"

create_file "scripts/seed-database.ts" "import 'reflect-metadata';
import { config } from 'dotenv';
import { Container } from '../src/Infrastructure/DependencyInjection/Container';
import { CreateUserHandler } from '../src/Application/Commands/Handlers/CreateUserHandler';
import { CreateUserCommand } from '../src/Application/Commands/CreateUserCommand';
import { ILogger } from '../src/Infrastructure/ExternalServices/ILogger';

// Load environment variables
config();

async function seedDatabase(): Promise<void> {
  try {
    console.log('🌱 Starting database seeding...');

    // Initialize container
    const container = Container.getInstance();
    await container.initialize();

    const logger = container.get<ILogger>('logger');
    const createUserHandler = container.get<CreateUserHandler>('createUserHandler');

    // Create admin user
    const adminCommand = new CreateUserCommand(
      'admin@nexus-v3.com',
      'Admin User',
      'admin123'
    );

    const adminId = await createUserHandler.handle(adminCommand);
    logger.info('Admin user created', { userId: adminId });

    // Create test users
    const testUsers = [
      { email: 'john.doe@example.com', name: 'John Doe' },
      { email: 'jane.smith@example.com', name: 'Jane Smith' },
      { email: 'bob.johnson@example.com', name: 'Bob Johnson' },
      { email: 'alice.brown@example.com', name: 'Alice Brown' },
      { email: 'charlie.wilson@example.com', name: 'Charlie Wilson' }
    ];

    for (const userData of testUsers) {
      const command = new CreateUserCommand(
        userData.email,
        userData.name,
        'password123'
      );

      const userId = await createUserHandler.handle(command);
      logger.info('Test user created', { userId, email: userData.email });
    }

    console.log('✅ Database seeding completed successfully!');
    console.log(\`📊 Created \${testUsers.length + 1} users\`);

  } catch (error) {
    console.error('❌ Database seeding failed:', error);
    process.exit(1);
  } finally {
    // Close database connections
    const { DatabaseConfig } = await import('../src/Infrastructure/Data/DatabaseConfig');
    await DatabaseConfig.closePool();
    process.exit(0);
  }
}

// Run seeding if this file is executed directly
if (require.main === module) {
  seedDatabase().catch(console.error);
}" "Database Seeding"

echo -e "${BLUE}📖 Step 6: Creating README for New Structure...${NC}"

create_file "README.md" "# Nexus V3 - Domain-Driven Design Architecture

A modern, scalable application built with Domain-Driven Design principles, clean architecture, and TypeScript.

## 🏗️ Architecture

This application follows Domain-Driven Design (DDD) and Clean Architecture principles:

- **Domain Layer**: Core business logic, entities, aggregates, and domain services
- **Application Layer**: Use cases, commands, queries, and application services
- **Infrastructure Layer**: Data access, external services, and technical concerns
- **Presentation Layer**: Web UI components and API controllers
- **Shared Kernel**: Common utilities, types, and base classes

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ 
- PostgreSQL 15+
- Redis 7+
- Docker (optional, for easy database setup)

### Installation

1. **Clone and install dependencies**
   \`\`\`bash
   git clone <repository-url>
   cd nexus-v3
   npm install
   \`\`\`

2. **Setup environment**
   \`\`\`bash
   cp .env.example .env
   # Edit .env with your configuration
   \`\`\`

3. **Start databases (using Docker)**
   \`\`\`bash
   # PostgreSQL
   docker run -d --name nexus-postgres \\
     -e POSTGRES_DB=nexus_v3 \\
     -e POSTGRES_USER=postgres \\
     -e POSTGRES_PASSWORD=password \\
     -p 5432:5432 \\
     postgres:15-alpine

   # Redis
   docker run -d --name nexus-redis \\
     -p 6379:6379 \\
     redis:7-alpine
   \`\`\`

4. **Initialize database**
   \`\`\`bash
   npm run db:migrate
   npm run db:seed
   \`\`\`

5. **Start development server**
   \`\`\`bash
   npm run dev
   \`\`\`

The application will be available at http://localhost:3000

## 📜 Scripts

- \`npm run dev\` - Start development server with hot reload
- \`npm run build\` - Build for production
- \`npm run start\` - Start production server
- \`npm test\` - Run all tests
- \`npm run test:unit\` - Run unit tests
- \`npm run test:integration\` - Run integration tests
- \`npm run test:e2e\` - Run end-to-end tests
- \`npm run lint\` - Run ESLint
- \`npm run format\` - Format code with Prettier
- \`npm run db:migrate\` - Run database migrations
- \`npm run db:seed\` - Seed database with test data

## 🏛️ Project Structure

\`\`\`
src/
├── Domain/                 # Domain layer
│   ├── Aggregates/        # Aggregate roots
│   ├── Entities/          # Domain entities
│   ├── ValueObjects/      # Value objects
│   ├── Services/          # Domain services
│   └── Events/            # Domain events
├── Application/           # Application layer
│   ├── Commands/          # Commands and handlers
│   ├── Queries/           # Queries and handlers
│   └── Events/            # Application event handlers
├── Infrastructure/        # Infrastructure layer
│   ├── Data/              # Data access and repositories
│   ├── ExternalServices/  # External service integrations
│   └── Messaging/         # Event publishing and messaging
├── Presentation/          # Presentation layer
│   ├── Web/               # Web components and pages
│   └── Api/               # API controllers and routes
├── SharedKernel/          # Shared utilities and types
└── startup.ts             # Application bootstrap
\`\`\`

## 🔌 API Endpoints

### Authentication
- \`POST /api/auth/login\` - User login
- \`POST /api/auth/logout\` - User logout
- \`POST /api/auth/refresh\` - Refresh token

### Users
- \`POST /api/users\` - Create user
- \`GET /api/users/:id\` - Get user by ID
- \`GET /api/users\` - List users (paginated)
- \`PUT /api/users/:id\` - Update user

### System
- \`GET /health\` - Health check
- \`GET /api\` - API documentation

## 🧪 Testing

The application includes comprehensive testing:

- **Unit Tests**: Test individual components in isolation
- **Integration Tests**: Test component interactions
- **E2E Tests**: Test complete user workflows

Run tests with:
\`\`\`bash
npm test                    # All tests
npm run test:unit          # Unit tests only
npm run test:integration   # Integration tests only
npm run test:e2e          # E2E tests only
npm run test:coverage     # With coverage report
\`\`\`

## 🐳 Docker

Build and run with Docker:

\`\`\`bash
# Build image
docker build -t nexus-v3 .

# Run with docker-compose
docker-compose up -d
\`\`\`

## 🔧 Development

### Path Aliases
The project uses TypeScript path aliases for clean imports:

- \`@domain/*\` → \`src/Domain/*\`
- \`@application/*\` → \`src/Application/*\`
- \`@infrastructure/*\` → \`src/Infrastructure/*\`
- \`@presentation/*\` → \`src/Presentation/*\`
- \`@shared/*\` → \`src/SharedKernel/*\`

### Code Quality
- **ESLint**: Linting with TypeScript rules
- **Prettier**: Code formatting
- **Husky**: Git hooks for quality checks
- **Jest**: Testing framework

## 📚 Documentation

- [Architecture Guide](docs/architecture.md)
- [API Documentation](docs/api.md)
- [Development Guide](docs/development.md)
- [Deployment Guide](docs/deployment.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Run quality checks
6. Submit a pull request

## 📄 License

This project is licensed under the MIT License.
" "New README"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["09-startup"] = "completed" | .current_phase = "10-cleanup"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Application Startup Creation Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Main startup file: src/startup.ts"
echo -e "  • Middleware setup: src/middleware.ts"
echo -e "  • Error handling: src/errorHandling.ts"
echo -e "  • Development scripts: 3 files"
echo -e "  • Database seeding: scripts/seed-database.ts"
echo -e "  • Updated README: Complete documentation"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/10-cleanup-old-structure.sh${NC}"
