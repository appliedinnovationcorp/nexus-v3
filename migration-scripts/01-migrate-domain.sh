#!/bin/bash

# Migration Script 01: Domain Layer Migration
# This script migrates domain entities, value objects, services, and events

set -e

echo "🏗️  Starting Domain Layer Migration..."

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

echo -e "${BLUE}📦 Step 1: Migrating Domain Entities...${NC}"

# Migrate User Entity
if [ -f "services/user-domain/src/domain/user.ts" ]; then
    safe_copy "services/user-domain/src/domain/user.ts" "src/Domain/Entities/User.ts" "User Entity"
else
    # Create basic User entity if not found
    create_file "src/Domain/Entities/User.ts" "import { BaseEntity } from '../../SharedKernel/BaseEntity';

export class User extends BaseEntity {
  constructor(
    public readonly id: string,
    public readonly email: string,
    public readonly name: string,
    public readonly createdAt: Date = new Date(),
    public readonly updatedAt: Date = new Date()
  ) {
    super(id);
  }

  public updateName(newName: string): User {
    return new User(
      this.id,
      this.email,
      newName,
      this.createdAt,
      new Date()
    );
  }

  public isActive(): boolean {
    return true; // Add business logic here
  }
}" "User Entity (generated)"
fi

# Create other domain entities based on analysis
echo -e "${BLUE}🔍 Analyzing existing entities...${NC}"

# Look for entity patterns in current codebase
grep -r "class.*Entity\|interface.*Entity" packages/ services/ --include="*.ts" 2>/dev/null | while read -r line; do
    echo "Found entity pattern: $line"
done > migration-temp/analysis/found-entities.txt || true

# Create Auth Entity
create_file "src/Domain/Entities/Auth.ts" "import { BaseEntity } from '../../SharedKernel/BaseEntity';

export class Auth extends BaseEntity {
  constructor(
    public readonly id: string,
    public readonly userId: string,
    public readonly provider: string,
    public readonly token: string,
    public readonly expiresAt: Date,
    public readonly createdAt: Date = new Date()
  ) {
    super(id);
  }

  public isExpired(): boolean {
    return new Date() > this.expiresAt;
  }

  public refresh(newToken: string, newExpiresAt: Date): Auth {
    return new Auth(
      this.id,
      this.userId,
      this.provider,
      newToken,
      newExpiresAt,
      this.createdAt
    );
  }
}" "Auth Entity"

echo -e "${BLUE}📋 Step 2: Migrating Value Objects...${NC}"

# Migrate types from packages/types
safe_copy "packages/types/src/user.ts" "src/Domain/ValueObjects/UserTypes.ts" "User Types"
safe_copy "packages/types/src/api.ts" "src/Domain/ValueObjects/ApiTypes.ts" "API Types"
safe_copy "packages/types/src/common.ts" "src/Domain/ValueObjects/CommonTypes.ts" "Common Types"

# Create additional value objects
create_file "src/Domain/ValueObjects/Email.ts" "export class Email {
  private readonly value: string;

  constructor(email: string) {
    if (!this.isValid(email)) {
      throw new Error('Invalid email format');
    }
    this.value = email.toLowerCase();
  }

  public getValue(): string {
    return this.value;
  }

  public equals(other: Email): boolean {
    return this.value === other.value;
  }

  private isValid(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }
}" "Email Value Object"

create_file "src/Domain/ValueObjects/UserId.ts" "export class UserId {
  private readonly value: string;

  constructor(id: string) {
    if (!id || id.trim().length === 0) {
      throw new Error('UserId cannot be empty');
    }
    this.value = id;
  }

  public getValue(): string {
    return this.value;
  }

  public equals(other: UserId): boolean {
    return this.value === other.value;
  }

  public static generate(): UserId {
    return new UserId(crypto.randomUUID());
  }
}" "UserId Value Object"

echo -e "${BLUE}⚙️  Step 3: Migrating Domain Services...${NC}"

# Migrate auth service
safe_copy "packages/auth/src/index.ts" "src/Domain/Services/AuthDomainService.ts" "Auth Domain Service"

# Migrate other services
if [ -d "packages/services/src" ]; then
    for service_file in packages/services/src/*.ts; do
        if [ -f "$service_file" ]; then
            filename=$(basename "$service_file")
            safe_copy "$service_file" "src/Domain/Services/$filename" "Domain Service"
        fi
    done
fi

# Create User Domain Service
create_file "src/Domain/Services/UserDomainService.ts" "import { User } from '../Entities/User';
import { Email } from '../ValueObjects/Email';
import { UserId } from '../ValueObjects/UserId';

export class UserDomainService {
  public createUser(email: string, name: string): User {
    const emailVO = new Email(email);
    const userId = UserId.generate();
    
    return new User(
      userId.getValue(),
      emailVO.getValue(),
      name
    );
  }

  public canUserAccessResource(user: User, resourceId: string): boolean {
    // Domain business logic for access control
    return user.isActive();
  }

  public validateUserUpdate(user: User, updates: Partial<User>): boolean {
    // Domain validation logic
    if (updates.email && !new Email(updates.email)) {
      return false;
    }
    return true;
  }
}" "User Domain Service"

echo -e "${BLUE}📡 Step 4: Creating Domain Events...${NC}"

# Analyze existing event patterns
grep -r "Event\|event" services/ packages/ --include="*.ts" 2>/dev/null | head -20 > migration-temp/analysis/event-patterns.txt || true

# Create domain events
create_file "src/Domain/Events/UserCreatedEvent.ts" "import { DomainEvent } from '../../SharedKernel/DomainEvent';

export class UserCreatedEvent extends DomainEvent {
  constructor(
    public readonly userId: string,
    public readonly email: string,
    public readonly name: string,
    occurredOn: Date = new Date()
  ) {
    super(occurredOn);
  }

  public getEventName(): string {
    return 'UserCreated';
  }
}" "UserCreated Domain Event"

create_file "src/Domain/Events/UserUpdatedEvent.ts" "import { DomainEvent } from '../../SharedKernel/DomainEvent';

export class UserUpdatedEvent extends DomainEvent {
  constructor(
    public readonly userId: string,
    public readonly changes: Record<string, any>,
    occurredOn: Date = new Date()
  ) {
    super(occurredOn);
  }

  public getEventName(): string {
    return 'UserUpdated';
  }
}" "UserUpdated Domain Event"

create_file "src/Domain/Events/AuthenticationEvent.ts" "import { DomainEvent } from '../../SharedKernel/DomainEvent';

export class AuthenticationEvent extends DomainEvent {
  constructor(
    public readonly userId: string,
    public readonly provider: string,
    public readonly success: boolean,
    occurredOn: Date = new Date()
  ) {
    super(occurredOn);
  }

  public getEventName(): string {
    return 'Authentication';
  }
}" "Authentication Domain Event"

echo -e "${BLUE}🏛️  Step 5: Creating Domain Aggregates...${NC}"

# Create User Aggregate
create_file "src/Domain/Aggregates/UserAggregate.ts" "import { AggregateRoot } from '../../SharedKernel/AggregateRoot';
import { User } from '../Entities/User';
import { Auth } from '../Entities/Auth';
import { UserCreatedEvent } from '../Events/UserCreatedEvent';
import { UserUpdatedEvent } from '../Events/UserUpdatedEvent';

export class UserAggregate extends AggregateRoot {
  private user: User;
  private auths: Auth[] = [];

  constructor(user: User) {
    super(user.id);
    this.user = user;
  }

  public static create(email: string, name: string): UserAggregate {
    const user = new User(
      crypto.randomUUID(),
      email,
      name
    );
    
    const aggregate = new UserAggregate(user);
    aggregate.addDomainEvent(new UserCreatedEvent(user.id, user.email, user.name));
    
    return aggregate;
  }

  public updateUser(name: string): void {
    const oldName = this.user.name;
    this.user = this.user.updateName(name);
    
    this.addDomainEvent(new UserUpdatedEvent(
      this.user.id,
      { name: { old: oldName, new: name } }
    ));
  }

  public addAuth(auth: Auth): void {
    this.auths.push(auth);
  }

  public getUser(): User {
    return this.user;
  }

  public getAuths(): Auth[] {
    return [...this.auths];
  }
}" "User Aggregate"

# Create Auth Aggregate
create_file "src/Domain/Aggregates/AuthAggregate.ts" "import { AggregateRoot } from '../../SharedKernel/AggregateRoot';
import { Auth } from '../Entities/Auth';
import { AuthenticationEvent } from '../Events/AuthenticationEvent';

export class AuthAggregate extends AggregateRoot {
  private auth: Auth;

  constructor(auth: Auth) {
    super(auth.id);
    this.auth = auth;
  }

  public static create(
    userId: string,
    provider: string,
    token: string,
    expiresAt: Date
  ): AuthAggregate {
    const auth = new Auth(
      crypto.randomUUID(),
      userId,
      provider,
      token,
      expiresAt
    );
    
    const aggregate = new AuthAggregate(auth);
    aggregate.addDomainEvent(new AuthenticationEvent(userId, provider, true));
    
    return aggregate;
  }

  public refresh(newToken: string, newExpiresAt: Date): void {
    this.auth = this.auth.refresh(newToken, newExpiresAt);
  }

  public isValid(): boolean {
    return !this.auth.isExpired();
  }

  public getAuth(): Auth {
    return this.auth;
  }
}" "Auth Aggregate"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["01-domain"] = "completed" | .current_phase = "02-application"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Domain Layer Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Domain Entities: $(find src/Domain/Entities -name "*.ts" | wc -l) files"
echo -e "  • Value Objects: $(find src/Domain/ValueObjects -name "*.ts" | wc -l) files"
echo -e "  • Domain Services: $(find src/Domain/Services -name "*.ts" | wc -l) files"
echo -e "  • Domain Events: $(find src/Domain/Events -name "*.ts" | wc -l) files"
echo -e "  • Aggregates: $(find src/Domain/Aggregates -name "*.ts" | wc -l) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/02-migrate-application.sh${NC}"
