#!/bin/bash

# Migration Script 07: Testing Migration
# This script consolidates and migrates all test files

set -e

echo "🧪 Starting Testing Migration..."

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

echo -e "${BLUE}🔧 Step 1: Creating Test Setup...${NC}"

create_file "tests/setup.ts" "import 'reflect-metadata';
import { config } from 'dotenv';

// Load test environment variables
config({ path: '.env.test' });

// Global test setup
beforeAll(async () => {
  // Setup test database, mocks, etc.
  console.log('🧪 Setting up test environment...');
});

afterAll(async () => {
  // Cleanup after all tests
  console.log('🧹 Cleaning up test environment...');
});

// Mock console methods in tests to reduce noise
global.console = {
  ...console,
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
};" "Test Setup"

create_file ".env.test" "# Test Environment Variables
NODE_ENV=test
PORT=3001

# Test Database
DB_HOST=localhost
DB_PORT=5433
DB_NAME=nexus_v3_test
DB_USER=postgres
DB_PASSWORD=password

# Test Redis
REDIS_HOST=localhost
REDIS_PORT=6380
REDIS_DB=1

# Test JWT
JWT_SECRET=test-secret-key
JWT_EXPIRES_IN=1h

# Test Email (use mock)
EMAIL_HOST=localhost
EMAIL_PORT=1025
EMAIL_USER=test@example.com
EMAIL_PASS=test

# Disable logging in tests
LOG_LEVEL=error" "Test Environment"

echo -e "${BLUE}📋 Step 2: Migrating Existing Tests...${NC}"

# Migrate unit tests
echo -e "${BLUE}🔬 Migrating unit tests...${NC}"

# Copy existing test files
while IFS= read -r test_file; do
    if [ -f "$test_file" ]; then
        # Determine destination based on file path
        if [[ "$test_file" == *"/unit/"* ]]; then
            dest_dir="tests/unit"
        elif [[ "$test_file" == *"/integration/"* ]]; then
            dest_dir="tests/integration"
        elif [[ "$test_file" == *"/e2e/"* ]]; then
            dest_dir="tests/e2e"
        else
            dest_dir="tests/unit"
        fi
        
        # Create destination directory if it doesn't exist
        mkdir -p "$dest_dir"
        
        # Copy file maintaining relative structure
        filename=$(basename "$test_file")
        safe_copy "$test_file" "$dest_dir/$filename" "Test file"
    fi
done < migration-temp/inventory/current-test-files.txt

# Copy from testing directory
if [ -d "testing/tests" ]; then
    safe_copy "testing/tests" "tests" "Testing Directory"
fi

echo -e "${BLUE}🧪 Step 3: Creating Unit Tests...${NC}"

# Create unit tests for domain entities
create_file "tests/unit/domain/entities/User.test.ts" "import { User } from '../../../../src/Domain/Entities/User';

describe('User Entity', () => {
  describe('constructor', () => {
    it('should create a user with valid data', () => {
      const user = new User(
        '123e4567-e89b-12d3-a456-426614174000',
        'test@example.com',
        'John Doe'
      );

      expect(user.id).toBe('123e4567-e89b-12d3-a456-426614174000');
      expect(user.email).toBe('test@example.com');
      expect(user.name).toBe('John Doe');
      expect(user.createdAt).toBeInstanceOf(Date);
      expect(user.updatedAt).toBeInstanceOf(Date);
    });

    it('should throw error with empty id', () => {
      expect(() => {
        new User('', 'test@example.com', 'John Doe');
      }).toThrow('Entity ID cannot be empty');
    });
  });

  describe('updateName', () => {
    it('should update user name and updatedAt timestamp', () => {
      const user = new User(
        '123e4567-e89b-12d3-a456-426614174000',
        'test@example.com',
        'John Doe'
      );

      const originalUpdatedAt = user.updatedAt;
      
      // Wait a bit to ensure timestamp difference
      setTimeout(() => {
        const updatedUser = user.updateName('Jane Doe');
        
        expect(updatedUser.name).toBe('Jane Doe');
        expect(updatedUser.updatedAt.getTime()).toBeGreaterThan(originalUpdatedAt.getTime());
        expect(updatedUser.id).toBe(user.id);
        expect(updatedUser.email).toBe(user.email);
      }, 10);
    });
  });

  describe('isActive', () => {
    it('should return true for active user', () => {
      const user = new User(
        '123e4567-e89b-12d3-a456-426614174000',
        'test@example.com',
        'John Doe'
      );

      expect(user.isActive()).toBe(true);
    });
  });
});" "User Entity Tests"

# Create unit tests for value objects
create_file "tests/unit/domain/value-objects/Email.test.ts" "import { Email } from '../../../../src/Domain/ValueObjects/Email';

describe('Email Value Object', () => {
  describe('constructor', () => {
    it('should create email with valid format', () => {
      const email = new Email('test@example.com');
      expect(email.getValue()).toBe('test@example.com');
    });

    it('should convert email to lowercase', () => {
      const email = new Email('TEST@EXAMPLE.COM');
      expect(email.getValue()).toBe('test@example.com');
    });

    it('should throw error with invalid email format', () => {
      expect(() => new Email('invalid-email')).toThrow('Invalid email format');
      expect(() => new Email('test@')).toThrow('Invalid email format');
      expect(() => new Email('@example.com')).toThrow('Invalid email format');
    });
  });

  describe('equals', () => {
    it('should return true for same email values', () => {
      const email1 = new Email('test@example.com');
      const email2 = new Email('TEST@EXAMPLE.COM');
      
      expect(email1.equals(email2)).toBe(true);
    });

    it('should return false for different email values', () => {
      const email1 = new Email('test1@example.com');
      const email2 = new Email('test2@example.com');
      
      expect(email1.equals(email2)).toBe(false);
    });
  });
});" "Email Value Object Tests"

# Create unit tests for domain services
create_file "tests/unit/domain/services/UserDomainService.test.ts" "import { UserDomainService } from '../../../../src/Domain/Services/UserDomainService';
import { User } from '../../../../src/Domain/Entities/User';

describe('UserDomainService', () => {
  let userDomainService: UserDomainService;

  beforeEach(() => {
    userDomainService = new UserDomainService();
  });

  describe('createUser', () => {
    it('should create a user with valid data', () => {
      const user = userDomainService.createUser('test@example.com', 'John Doe');

      expect(user).toBeInstanceOf(User);
      expect(user.email).toBe('test@example.com');
      expect(user.name).toBe('John Doe');
      expect(user.id).toBeDefined();
    });

    it('should throw error with invalid email', () => {
      expect(() => {
        userDomainService.createUser('invalid-email', 'John Doe');
      }).toThrow('Invalid email format');
    });
  });

  describe('canUserAccessResource', () => {
    it('should return true for active user', () => {
      const user = new User('123', 'test@example.com', 'John Doe');
      const canAccess = userDomainService.canUserAccessResource(user, 'resource-123');

      expect(canAccess).toBe(true);
    });
  });

  describe('validateUserUpdate', () => {
    it('should return true for valid updates', () => {
      const user = new User('123', 'test@example.com', 'John Doe');
      const isValid = userDomainService.validateUserUpdate(user, { name: 'Jane Doe' });

      expect(isValid).toBe(true);
    });

    it('should return false for invalid email update', () => {
      const user = new User('123', 'test@example.com', 'John Doe');
      const isValid = userDomainService.validateUserUpdate(user, { email: 'invalid-email' });

      expect(isValid).toBe(false);
    });
  });
});" "User Domain Service Tests"

echo -e "${BLUE}🔗 Step 4: Creating Integration Tests...${NC}"

# Create integration tests for repositories
create_file "tests/integration/infrastructure/repositories/PostgresUserRepository.test.ts" "import { Pool } from 'pg';
import { PostgresUserRepository } from '../../../../src/Infrastructure/Data/Repositories/PostgresUserRepository';
import { UserAggregate } from '../../../../src/Domain/Aggregates/UserAggregate';

describe('PostgresUserRepository Integration', () => {
  let pool: Pool;
  let repository: PostgresUserRepository;

  beforeAll(async () => {
    // Setup test database connection
    pool = new Pool({
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '5433'),
      database: process.env.DB_NAME,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    });

    repository = new PostgresUserRepository(pool);

    // Setup test tables
    await pool.query(\`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY,
        email VARCHAR(255) UNIQUE NOT NULL,
        name VARCHAR(255) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      )
    \`);
  });

  afterAll(async () => {
    // Cleanup
    await pool.query('DROP TABLE IF EXISTS users');
    await pool.end();
  });

  beforeEach(async () => {
    // Clean up before each test
    await pool.query('DELETE FROM users');
  });

  describe('save', () => {
    it('should save a new user aggregate', async () => {
      const userAggregate = UserAggregate.create('test@example.com', 'John Doe');
      
      await repository.save(userAggregate);
      
      const result = await pool.query('SELECT * FROM users WHERE id = \$1', [userAggregate.getId()]);
      expect(result.rows).toHaveLength(1);
      expect(result.rows[0].email).toBe('test@example.com');
      expect(result.rows[0].name).toBe('John Doe');
    });

    it('should update existing user aggregate', async () => {
      const userAggregate = UserAggregate.create('test@example.com', 'John Doe');
      await repository.save(userAggregate);
      
      userAggregate.updateUser('Jane Doe');
      await repository.save(userAggregate);
      
      const result = await pool.query('SELECT * FROM users WHERE id = \$1', [userAggregate.getId()]);
      expect(result.rows[0].name).toBe('Jane Doe');
    });
  });

  describe('findById', () => {
    it('should find user by id', async () => {
      const userAggregate = UserAggregate.create('test@example.com', 'John Doe');
      await repository.save(userAggregate);
      
      const foundUser = await repository.findById(userAggregate.getId());
      
      expect(foundUser).toBeDefined();
      expect(foundUser!.getUser().email).toBe('test@example.com');
      expect(foundUser!.getUser().name).toBe('John Doe');
    });

    it('should return null for non-existent user', async () => {
      const foundUser = await repository.findById('non-existent-id');
      expect(foundUser).toBeNull();
    });
  });

  describe('findByEmail', () => {
    it('should find user by email', async () => {
      const userAggregate = UserAggregate.create('test@example.com', 'John Doe');
      await repository.save(userAggregate);
      
      const foundUser = await repository.findByEmail('test@example.com');
      
      expect(foundUser).toBeDefined();
      expect(foundUser!.getUser().name).toBe('John Doe');
    });
  });
});" "PostgreSQL Repository Integration Tests"

echo -e "${BLUE}🌐 Step 5: Creating E2E Tests...${NC}"

# Create E2E tests for API endpoints
create_file "tests/e2e/api/auth.e2e.test.ts" "import request from 'supertest';
import { Express } from 'express';
import { createApp } from '../../../src/startup';

describe('Auth API E2E', () => {
  let app: Express;

  beforeAll(async () => {
    app = await createApp();
  });

  describe('POST /api/auth/login', () => {
    it('should login with valid credentials', async () => {
      // First create a user
      await request(app)
        .post('/api/users')
        .send({
          email: 'test@example.com',
          name: 'Test User',
          password: 'password123'
        });

      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'test@example.com',
          password: 'password123'
        });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('token');
      expect(typeof response.body.token).toBe('string');
    });

    it('should return 401 for invalid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'test@example.com',
          password: 'wrongpassword'
        });

      expect(response.status).toBe(401);
      expect(response.body).toHaveProperty('error');
    });

    it('should return 400 for missing credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'test@example.com'
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('error');
    });
  });
});" "Auth E2E Tests"

create_file "tests/e2e/api/users.e2e.test.ts" "import request from 'supertest';
import { Express } from 'express';
import { createApp } from '../../../src/startup';

describe('Users API E2E', () => {
  let app: Express;
  let authToken: string;

  beforeAll(async () => {
    app = await createApp();
    
    // Create a user and get auth token
    await request(app)
      .post('/api/users')
      .send({
        email: 'admin@example.com',
        name: 'Admin User',
        password: 'password123'
      });

    const loginResponse = await request(app)
      .post('/api/auth/login')
      .send({
        email: 'admin@example.com',
        password: 'password123'
      });

    authToken = loginResponse.body.token;
  });

  describe('POST /api/users', () => {
    it('should create a new user', async () => {
      const response = await request(app)
        .post('/api/users')
        .set('Authorization', \`Bearer \${authToken}\`)
        .send({
          email: 'newuser@example.com',
          name: 'New User',
          password: 'password123'
        });

      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('id');
    });

    it('should return 400 for invalid data', async () => {
      const response = await request(app)
        .post('/api/users')
        .set('Authorization', \`Bearer \${authToken}\`)
        .send({
          email: 'invalid-email',
          name: 'Test User'
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('errors');
    });

    it('should return 401 without auth token', async () => {
      const response = await request(app)
        .post('/api/users')
        .send({
          email: 'test@example.com',
          name: 'Test User'
        });

      expect(response.status).toBe(401);
    });
  });

  describe('GET /api/users', () => {
    it('should get paginated users', async () => {
      const response = await request(app)
        .get('/api/users')
        .set('Authorization', \`Bearer \${authToken}\`)
        .query({ page: 1, limit: 10 });

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('users');
      expect(response.body).toHaveProperty('total');
      expect(response.body).toHaveProperty('page');
      expect(response.body).toHaveProperty('limit');
      expect(Array.isArray(response.body.users)).toBe(true);
    });

    it('should search users', async () => {
      const response = await request(app)
        .get('/api/users')
        .set('Authorization', \`Bearer \${authToken}\`)
        .query({ search: 'Admin' });

      expect(response.status).toBe(200);
      expect(response.body.users.length).toBeGreaterThan(0);
    });
  });
});" "Users E2E Tests"

echo -e "${BLUE}🎭 Step 6: Creating Test Utilities and Mocks...${NC}"

create_file "tests/utils/TestDataBuilder.ts" "import { User } from '../../src/Domain/Entities/User';
import { UserAggregate } from '../../src/Domain/Aggregates/UserAggregate';

export class TestDataBuilder {
  public static createUser(overrides: Partial<{
    id: string;
    email: string;
    name: string;
    createdAt: Date;
    updatedAt: Date;
  }> = {}): User {
    return new User(
      overrides.id || '123e4567-e89b-12d3-a456-426614174000',
      overrides.email || 'test@example.com',
      overrides.name || 'Test User',
      overrides.createdAt || new Date('2023-01-01'),
      overrides.updatedAt || new Date('2023-01-01')
    );
  }

  public static createUserAggregate(overrides: Partial<{
    email: string;
    name: string;
  }> = {}): UserAggregate {
    return UserAggregate.create(
      overrides.email || 'test@example.com',
      overrides.name || 'Test User'
    );
  }

  public static createMultipleUsers(count: number): User[] {
    return Array.from({ length: count }, (_, index) =>
      this.createUser({
        id: \`user-\${index + 1}\`,
        email: \`user\${index + 1}@example.com\`,
        name: \`User \${index + 1}\`
      })
    );
  }
}" "Test Data Builder"

create_file "tests/mocks/MockUserRepository.ts" "import { IUserRepository } from '../../src/Infrastructure/Data/Repositories/IUserRepository';
import { UserAggregate } from '../../src/Domain/Aggregates/UserAggregate';

export class MockUserRepository implements IUserRepository {
  private users: Map<string, UserAggregate> = new Map();

  async findById(id: string): Promise<UserAggregate | null> {
    return this.users.get(id) || null;
  }

  async findByEmail(email: string): Promise<UserAggregate | null> {
    for (const user of this.users.values()) {
      if (user.getUser().email === email) {
        return user;
      }
    }
    return null;
  }

  async findMany(options: {
    page: number;
    limit: number;
    search?: string;
  }): Promise<{ users: UserAggregate[]; total: number }> {
    let users = Array.from(this.users.values());

    if (options.search) {
      users = users.filter(user =>
        user.getUser().name.toLowerCase().includes(options.search!.toLowerCase()) ||
        user.getUser().email.toLowerCase().includes(options.search!.toLowerCase())
      );
    }

    const total = users.length;
    const startIndex = (options.page - 1) * options.limit;
    const endIndex = startIndex + options.limit;
    const paginatedUsers = users.slice(startIndex, endIndex);

    return { users: paginatedUsers, total };
  }

  async save(userAggregate: UserAggregate): Promise<void> {
    this.users.set(userAggregate.getId(), userAggregate);
  }

  async delete(id: string): Promise<void> {
    this.users.delete(id);
  }

  // Test helper methods
  clear(): void {
    this.users.clear();
  }

  getAll(): UserAggregate[] {
    return Array.from(this.users.values());
  }
}" "Mock User Repository"

create_file "tests/mocks/MockEventPublisher.ts" "import { IEventPublisher } from '../../src/Infrastructure/Messaging/IEventPublisher';
import { DomainEvent } from '../../src/SharedKernel/DomainEvent';

export class MockEventPublisher implements IEventPublisher {
  private publishedEvents: DomainEvent[] = [];

  async publish(event: DomainEvent): Promise<void> {
    this.publishedEvents.push(event);
  }

  async publishBatch(events: DomainEvent[]): Promise<void> {
    this.publishedEvents.push(...events);
  }

  // Test helper methods
  getPublishedEvents(): DomainEvent[] {
    return [...this.publishedEvents];
  }

  getEventsByType<T extends DomainEvent>(eventType: new (...args: any[]) => T): T[] {
    return this.publishedEvents.filter(event => event instanceof eventType) as T[];
  }

  clear(): void {
    this.publishedEvents = [];
  }

  hasPublishedEvent(eventType: new (...args: any[]) => DomainEvent): boolean {
    return this.publishedEvents.some(event => event instanceof eventType);
  }
}" "Mock Event Publisher"

echo -e "${BLUE}📊 Step 7: Creating Test Scripts...${NC}"

create_file "scripts/test-setup.sh" "#!/bin/bash

# Test setup script
set -e

echo \"🧪 Setting up test environment...\"

# Start test database
docker run -d --name nexus-test-db \
  -e POSTGRES_DB=nexus_v3_test \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password \
  -p 5433:5432 \
  postgres:15-alpine

# Start test Redis
docker run -d --name nexus-test-redis \
  -p 6380:6379 \
  redis:7-alpine

# Wait for services to be ready
echo \"⏳ Waiting for services to be ready...\"
sleep 10

# Run migrations
npm run db:migrate

echo \"✅ Test environment ready!\"" "Test Setup Script"

create_file "scripts/test-teardown.sh" "#!/bin/bash

# Test teardown script
set -e

echo \"🧹 Tearing down test environment...\"

# Stop and remove test containers
docker stop nexus-test-db nexus-test-redis || true
docker rm nexus-test-db nexus-test-redis || true

echo \"✅ Test environment cleaned up!\"" "Test Teardown Script"

chmod +x scripts/test-setup.sh scripts/test-teardown.sh

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["07-testing"] = "completed" | .current_phase = "08-dependencies"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Testing Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Test setup files: Created"
echo -e "  • Unit tests: $(find tests/unit -name "*.test.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Integration tests: $(find tests/integration -name "*.test.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • E2E tests: $(find tests/e2e -name "*.test.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Test utilities: $(find tests/utils tests/mocks -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Test scripts: 2 files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/08-update-dependencies.sh${NC}"
