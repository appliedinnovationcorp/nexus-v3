#!/bin/bash

# Migration Script 02: Application Layer Migration
# This script migrates commands, queries, handlers, and application services

set -e

echo "🎯 Starting Application Layer Migration..."

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
    elif [ -d "$src" ]; then
        cp -r "$src"/* "$dest"/ 2>/dev/null || true
        echo -e "${GREEN}✅ Copied $desc directory: $src -> $dest${NC}"
    else
        echo -e "${YELLOW}⚠️  Source not found for $desc: $src${NC}"
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

echo -e "${BLUE}📝 Step 1: Migrating Commands...${NC}"

# Migrate existing commands
safe_copy "services/user-domain/src/application/commands/create-user.command.ts" "src/Application/Commands/CreateUserCommand.ts" "Create User Command"

# Create additional commands based on domain analysis
create_file "src/Application/Commands/CreateUserCommand.ts" "export class CreateUserCommand {
  constructor(
    public readonly email: string,
    public readonly name: string,
    public readonly password?: string
  ) {}
}" "Create User Command"

create_file "src/Application/Commands/UpdateUserCommand.ts" "export class UpdateUserCommand {
  constructor(
    public readonly userId: string,
    public readonly name?: string,
    public readonly email?: string
  ) {}
}" "Update User Command"

create_file "src/Application/Commands/DeleteUserCommand.ts" "export class DeleteUserCommand {
  constructor(
    public readonly userId: string
  ) {}
}" "Delete User Command"

create_file "src/Application/Commands/AuthenticateUserCommand.ts" "export class AuthenticateUserCommand {
  constructor(
    public readonly email: string,
    public readonly password: string,
    public readonly provider: string = 'local'
  ) {}
}" "Authenticate User Command"

echo -e "${BLUE}⚡ Step 2: Creating Command Handlers...${NC}"

# Create command handlers
create_file "src/Application/Commands/Handlers/CreateUserHandler.ts" "import { CreateUserCommand } from '../CreateUserCommand';
import { UserAggregate } from '../../../Domain/Aggregates/UserAggregate';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';
import { IEventPublisher } from '../../../Infrastructure/Messaging/IEventPublisher';

export class CreateUserHandler {
  constructor(
    private readonly userRepository: IUserRepository,
    private readonly eventPublisher: IEventPublisher
  ) {}

  public async handle(command: CreateUserCommand): Promise<string> {
    // Check if user already exists
    const existingUser = await this.userRepository.findByEmail(command.email);
    if (existingUser) {
      throw new Error('User with this email already exists');
    }

    // Create user aggregate
    const userAggregate = UserAggregate.create(command.email, command.name);
    
    // Save to repository
    await this.userRepository.save(userAggregate);
    
    // Publish domain events
    const events = userAggregate.getUncommittedEvents();
    for (const event of events) {
      await this.eventPublisher.publish(event);
    }
    
    userAggregate.markEventsAsCommitted();
    
    return userAggregate.getId();
  }
}" "Create User Handler"

create_file "src/Application/Commands/Handlers/UpdateUserHandler.ts" "import { UpdateUserCommand } from '../UpdateUserCommand';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';
import { IEventPublisher } from '../../../Infrastructure/Messaging/IEventPublisher';

export class UpdateUserHandler {
  constructor(
    private readonly userRepository: IUserRepository,
    private readonly eventPublisher: IEventPublisher
  ) {}

  public async handle(command: UpdateUserCommand): Promise<void> {
    const userAggregate = await this.userRepository.findById(command.userId);
    if (!userAggregate) {
      throw new Error('User not found');
    }

    if (command.name) {
      userAggregate.updateUser(command.name);
    }

    await this.userRepository.save(userAggregate);
    
    const events = userAggregate.getUncommittedEvents();
    for (const event of events) {
      await this.eventPublisher.publish(event);
    }
    
    userAggregate.markEventsAsCommitted();
  }
}" "Update User Handler"

create_file "src/Application/Commands/Handlers/AuthenticateUserHandler.ts" "import { AuthenticateUserCommand } from '../AuthenticateUserCommand';
import { AuthAggregate } from '../../../Domain/Aggregates/AuthAggregate';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';
import { IAuthRepository } from '../../../Infrastructure/Data/Repositories/IAuthRepository';
import { IPasswordService } from '../../../Infrastructure/ExternalServices/IPasswordService';
import { ITokenService } from '../../../Infrastructure/ExternalServices/ITokenService';

export class AuthenticateUserHandler {
  constructor(
    private readonly userRepository: IUserRepository,
    private readonly authRepository: IAuthRepository,
    private readonly passwordService: IPasswordService,
    private readonly tokenService: ITokenService
  ) {}

  public async handle(command: AuthenticateUserCommand): Promise<string> {
    const user = await this.userRepository.findByEmail(command.email);
    if (!user) {
      throw new Error('Invalid credentials');
    }

    const isValidPassword = await this.passwordService.verify(
      command.password,
      user.getUser().password || ''
    );
    
    if (!isValidPassword) {
      throw new Error('Invalid credentials');
    }

    const token = await this.tokenService.generate(user.getId());
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours

    const authAggregate = AuthAggregate.create(
      user.getId(),
      command.provider,
      token,
      expiresAt
    );

    await this.authRepository.save(authAggregate);

    return token;
  }
}" "Authenticate User Handler"

echo -e "${BLUE}✅ Step 3: Creating Command Validators...${NC}"

create_file "src/Application/Commands/Validators/CreateUserValidator.ts" "import { CreateUserCommand } from '../CreateUserCommand';

export class CreateUserValidator {
  public validate(command: CreateUserCommand): string[] {
    const errors: string[] = [];

    if (!command.email || command.email.trim().length === 0) {
      errors.push('Email is required');
    }

    if (!this.isValidEmail(command.email)) {
      errors.push('Email format is invalid');
    }

    if (!command.name || command.name.trim().length === 0) {
      errors.push('Name is required');
    }

    if (command.name && command.name.length > 100) {
      errors.push('Name must be less than 100 characters');
    }

    return errors;
  }

  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }
}" "Create User Validator"

create_file "src/Application/Commands/Validators/UpdateUserValidator.ts" "import { UpdateUserCommand } from '../UpdateUserCommand';

export class UpdateUserValidator {
  public validate(command: UpdateUserCommand): string[] {
    const errors: string[] = [];

    if (!command.userId || command.userId.trim().length === 0) {
      errors.push('User ID is required');
    }

    if (command.name !== undefined && command.name.trim().length === 0) {
      errors.push('Name cannot be empty');
    }

    if (command.name && command.name.length > 100) {
      errors.push('Name must be less than 100 characters');
    }

    if (command.email && !this.isValidEmail(command.email)) {
      errors.push('Email format is invalid');
    }

    return errors;
  }

  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }
}" "Update User Validator"

echo -e "${BLUE}🔍 Step 4: Migrating Queries...${NC}"

# Migrate existing queries
safe_copy "services/user-domain/src/application/queries/get-user.query.ts" "src/Application/Queries/GetUserQuery.ts" "Get User Query"

# Create additional queries
create_file "src/Application/Queries/GetUserQuery.ts" "export class GetUserQuery {
  constructor(
    public readonly userId: string
  ) {}
}" "Get User Query"

create_file "src/Application/Queries/GetUserByEmailQuery.ts" "export class GetUserByEmailQuery {
  constructor(
    public readonly email: string
  ) {}
}" "Get User By Email Query"

create_file "src/Application/Queries/GetUsersQuery.ts" "export class GetUsersQuery {
  constructor(
    public readonly page: number = 1,
    public readonly limit: number = 10,
    public readonly search?: string
  ) {}
}" "Get Users Query"

echo -e "${BLUE}📊 Step 5: Creating DTOs...${NC}"

create_file "src/Application/Queries/Dtos/UserDto.ts" "export class UserDto {
  constructor(
    public readonly id: string,
    public readonly email: string,
    public readonly name: string,
    public readonly createdAt: Date,
    public readonly updatedAt: Date,
    public readonly isActive: boolean
  ) {}

  public static fromDomain(user: any): UserDto {
    return new UserDto(
      user.id,
      user.email,
      user.name,
      user.createdAt,
      user.updatedAt,
      user.isActive()
    );
  }
}" "User DTO"

create_file "src/Application/Queries/Dtos/UserListDto.ts" "import { UserDto } from './UserDto';

export class UserListDto {
  constructor(
    public readonly users: UserDto[],
    public readonly total: number,
    public readonly page: number,
    public readonly limit: number
  ) {}
}" "User List DTO"

create_file "src/Application/Queries/Dtos/AuthDto.ts" "export class AuthDto {
  constructor(
    public readonly token: string,
    public readonly expiresAt: Date,
    public readonly user: {
      id: string;
      email: string;
      name: string;
    }
  ) {}
}" "Auth DTO"

echo -e "${BLUE}🔎 Step 6: Creating Query Handlers...${NC}"

create_file "src/Application/Queries/Handlers/GetUserHandler.ts" "import { GetUserQuery } from '../GetUserQuery';
import { UserDto } from '../Dtos/UserDto';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';

export class GetUserHandler {
  constructor(
    private readonly userRepository: IUserRepository
  ) {}

  public async handle(query: GetUserQuery): Promise<UserDto | null> {
    const userAggregate = await this.userRepository.findById(query.userId);
    
    if (!userAggregate) {
      return null;
    }

    return UserDto.fromDomain(userAggregate.getUser());
  }
}" "Get User Handler"

create_file "src/Application/Queries/Handlers/GetUserByEmailHandler.ts" "import { GetUserByEmailQuery } from '../GetUserByEmailQuery';
import { UserDto } from '../Dtos/UserDto';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';

export class GetUserByEmailHandler {
  constructor(
    private readonly userRepository: IUserRepository
  ) {}

  public async handle(query: GetUserByEmailQuery): Promise<UserDto | null> {
    const userAggregate = await this.userRepository.findByEmail(query.email);
    
    if (!userAggregate) {
      return null;
    }

    return UserDto.fromDomain(userAggregate.getUser());
  }
}" "Get User By Email Handler"

create_file "src/Application/Queries/Handlers/GetUsersHandler.ts" "import { GetUsersQuery } from '../GetUsersQuery';
import { UserListDto } from '../Dtos/UserListDto';
import { UserDto } from '../Dtos/UserDto';
import { IUserRepository } from '../../../Infrastructure/Data/Repositories/IUserRepository';

export class GetUsersHandler {
  constructor(
    private readonly userRepository: IUserRepository
  ) {}

  public async handle(query: GetUsersQuery): Promise<UserListDto> {
    const { users, total } = await this.userRepository.findMany({
      page: query.page,
      limit: query.limit,
      search: query.search
    });

    const userDtos = users.map(userAggregate => 
      UserDto.fromDomain(userAggregate.getUser())
    );

    return new UserListDto(userDtos, total, query.page, query.limit);
  }
}" "Get Users Handler"

echo -e "${BLUE}📡 Step 7: Creating Application Event Handlers...${NC}"

create_file "src/Application/Events/UserCreatedHandler.ts" "import { UserCreatedEvent } from '../../Domain/Events/UserCreatedEvent';
import { IEmailService } from '../../Infrastructure/ExternalServices/IEmailService';
import { ILogger } from '../../Infrastructure/ExternalServices/ILogger';

export class UserCreatedHandler {
  constructor(
    private readonly emailService: IEmailService,
    private readonly logger: ILogger
  ) {}

  public async handle(event: UserCreatedEvent): Promise<void> {
    try {
      // Send welcome email
      await this.emailService.sendWelcomeEmail(event.email, event.name);
      
      // Log user creation
      this.logger.info('User created successfully', {
        userId: event.userId,
        email: event.email,
        occurredOn: event.occurredOn
      });
    } catch (error) {
      this.logger.error('Failed to handle UserCreated event', {
        userId: event.userId,
        error: error.message
      });
    }
  }
}" "User Created Handler"

create_file "src/Application/Events/AuthenticationHandler.ts" "import { AuthenticationEvent } from '../../Domain/Events/AuthenticationEvent';
import { ILogger } from '../../Infrastructure/ExternalServices/ILogger';
import { ISecurityService } from '../../Infrastructure/ExternalServices/ISecurityService';

export class AuthenticationHandler {
  constructor(
    private readonly logger: ILogger,
    private readonly securityService: ISecurityService
  ) {}

  public async handle(event: AuthenticationEvent): Promise<void> {
    try {
      // Log authentication attempt
      this.logger.info('Authentication attempt', {
        userId: event.userId,
        provider: event.provider,
        success: event.success,
        occurredOn: event.occurredOn
      });

      // Check for suspicious activity
      if (!event.success) {
        await this.securityService.recordFailedLogin(event.userId);
      }
    } catch (error) {
      this.logger.error('Failed to handle Authentication event', {
        userId: event.userId,
        error: error.message
      });
    }
  }
}" "Authentication Handler"

# Migrate existing API types to DTOs
echo -e "${BLUE}📦 Step 8: Migrating API Types to DTOs...${NC}"

if [ -f "packages/api/src/index.ts" ]; then
    safe_copy "packages/api/src/index.ts" "src/Application/Queries/Dtos/ApiTypes.ts" "API Types"
fi

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["02-application"] = "completed" | .current_phase = "03-infrastructure"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Application Layer Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Commands: $(find src/Application/Commands -name "*.ts" -not -path "*/Handlers/*" -not -path "*/Validators/*" | wc -l) files"
echo -e "  • Command Handlers: $(find src/Application/Commands/Handlers -name "*.ts" | wc -l) files"
echo -e "  • Command Validators: $(find src/Application/Commands/Validators -name "*.ts" | wc -l) files"
echo -e "  • Queries: $(find src/Application/Queries -name "*.ts" -not -path "*/Handlers/*" -not -path "*/Dtos/*" | wc -l) files"
echo -e "  • Query Handlers: $(find src/Application/Queries/Handlers -name "*.ts" | wc -l) files"
echo -e "  • DTOs: $(find src/Application/Queries/Dtos -name "*.ts" | wc -l) files"
echo -e "  • Event Handlers: $(find src/Application/Events -name "*.ts" | wc -l) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/03-migrate-infrastructure.sh${NC}"
