#!/bin/bash

# Migration Script 05: Shared Kernel Migration
# This script migrates common utilities, base classes, and shared types

set -e

echo "🔧 Starting Shared Kernel Migration..."

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

echo -e "${BLUE}🏗️  Step 1: Creating Base Domain Classes...${NC}"

# Create base entity
create_file "src/SharedKernel/BaseEntity.ts" "export abstract class BaseEntity {
  protected constructor(public readonly id: string) {
    if (!id || id.trim().length === 0) {
      throw new Error('Entity ID cannot be empty');
    }
  }

  public equals(other: BaseEntity): boolean {
    if (!(other instanceof BaseEntity)) {
      return false;
    }
    return this.id === other.id;
  }

  public getId(): string {
    return this.id;
  }
}" "Base Entity"

# Create aggregate root
create_file "src/SharedKernel/AggregateRoot.ts" "import { BaseEntity } from './BaseEntity';
import { DomainEvent } from './DomainEvent';

export abstract class AggregateRoot extends BaseEntity {
  private domainEvents: DomainEvent[] = [];

  protected constructor(id: string) {
    super(id);
  }

  protected addDomainEvent(event: DomainEvent): void {
    this.domainEvents.push(event);
  }

  public getUncommittedEvents(): DomainEvent[] {
    return [...this.domainEvents];
  }

  public markEventsAsCommitted(): void {
    this.domainEvents = [];
  }

  public clearEvents(): void {
    this.domainEvents = [];
  }
}" "Aggregate Root"

# Create domain event base class
create_file "src/SharedKernel/DomainEvent.ts" "export abstract class DomainEvent {
  public readonly occurredOn: Date;

  protected constructor(occurredOn?: Date) {
    this.occurredOn = occurredOn || new Date();
  }

  public abstract getEventName(): string;
}" "Domain Event"

# Create value object base class
create_file "src/SharedKernel/ValueObject.ts" "export abstract class ValueObject<T> {
  protected readonly value: T;

  protected constructor(value: T) {
    this.value = value;
  }

  public getValue(): T {
    return this.value;
  }

  public equals(other: ValueObject<T>): boolean {
    if (!(other instanceof ValueObject)) {
      return false;
    }
    return JSON.stringify(this.value) === JSON.stringify(other.value);
  }
}" "Value Object"

echo -e "${BLUE}📦 Step 2: Migrating Utilities...${NC}"

# Migrate utilities from packages
safe_copy "packages/utils/src" "src/SharedKernel/Utils" "Utilities"
safe_copy "packages/constants/src" "src/SharedKernel/Constants" "Constants"
safe_copy "packages/validators/src" "src/SharedKernel/Validators" "Validators"

# Migrate shared kernel from services
if [ -d "services/shared-kernel/src" ]; then
    safe_copy "services/shared-kernel/src" "src/SharedKernel" "Service Shared Kernel"
fi

# Create common utilities if not migrated
if [ ! -d "src/SharedKernel/Utils" ]; then
    mkdir -p src/SharedKernel/Utils
    
    create_file "src/SharedKernel/Utils/DateUtils.ts" "export class DateUtils {
  public static formatDate(date: Date, format: string = 'YYYY-MM-DD'): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');

    return format
      .replace('YYYY', year.toString())
      .replace('MM', month)
      .replace('DD', day)
      .replace('HH', hours)
      .replace('mm', minutes)
      .replace('ss', seconds);
  }

  public static isValidDate(date: any): boolean {
    return date instanceof Date && !isNaN(date.getTime());
  }

  public static addDays(date: Date, days: number): Date {
    const result = new Date(date);
    result.setDate(result.getDate() + days);
    return result;
  }

  public static diffInDays(date1: Date, date2: Date): number {
    const timeDiff = Math.abs(date2.getTime() - date1.getTime());
    return Math.ceil(timeDiff / (1000 * 3600 * 24));
  }

  public static isToday(date: Date): boolean {
    const today = new Date();
    return date.toDateString() === today.toDateString();
  }
}" "Date Utils"

    create_file "src/SharedKernel/Utils/StringUtils.ts" "export class StringUtils {
  public static isEmpty(str: string | null | undefined): boolean {
    return !str || str.trim().length === 0;
  }

  public static isNotEmpty(str: string | null | undefined): boolean {
    return !this.isEmpty(str);
  }

  public static capitalize(str: string): string {
    if (this.isEmpty(str)) return str || '';
    return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase();
  }

  public static camelCase(str: string): string {
    return str
      .replace(/(?:^\w|[A-Z]|\b\w)/g, (word, index) => {
        return index === 0 ? word.toLowerCase() : word.toUpperCase();
      })
      .replace(/\s+/g, '');
  }

  public static kebabCase(str: string): string {
    return str
      .replace(/([a-z])([A-Z])/g, '\$1-\$2')
      .replace(/\s+/g, '-')
      .toLowerCase();
  }

  public static truncate(str: string, length: number, suffix: string = '...'): string {
    if (str.length <= length) return str;
    return str.substring(0, length - suffix.length) + suffix;
  }

  public static generateSlug(str: string): string {
    return str
      .toLowerCase()
      .replace(/[^a-z0-9 -]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .trim();
  }
}" "String Utils"

    create_file "src/SharedKernel/Utils/ValidationUtils.ts" "export class ValidationUtils {
  public static isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  public static isValidUrl(url: string): boolean {
    try {
      new URL(url);
      return true;
    } catch {
      return false;
    }
  }

  public static isValidUUID(uuid: string): boolean {
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(uuid);
  }

  public static isValidPhoneNumber(phone: string): boolean {
    const phoneRegex = /^\+?[\d\s\-\(\)]{10,}$/;
    return phoneRegex.test(phone);
  }

  public static isStrongPassword(password: string): boolean {
    // At least 8 characters, 1 uppercase, 1 lowercase, 1 number, 1 special character
    const strongPasswordRegex = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@\$!%*?&])[A-Za-z\d@\$!%*?&]{8,}$/;
    return strongPasswordRegex.test(password);
  }

  public static sanitizeInput(input: string): string {
    return input
      .replace(/[<>\"']/g, '')
      .trim();
  }
}" "Validation Utils"
fi

echo -e "${BLUE}🔧 Step 3: Creating Common Constants...${NC}"

if [ ! -d "src/SharedKernel/Constants" ]; then
    mkdir -p src/SharedKernel/Constants
    
    create_file "src/SharedKernel/Constants/AppConstants.ts" "export const AppConstants = {
  APP_NAME: 'Nexus V3',
  VERSION: '1.0.0',
  
  // Pagination
  DEFAULT_PAGE_SIZE: 10,
  MAX_PAGE_SIZE: 100,
  
  // Validation
  MIN_PASSWORD_LENGTH: 8,
  MAX_NAME_LENGTH: 100,
  MAX_EMAIL_LENGTH: 255,
  
  // Token
  TOKEN_EXPIRY_HOURS: 24,
  REFRESH_TOKEN_EXPIRY_DAYS: 30,
  
  // File Upload
  MAX_FILE_SIZE_MB: 10,
  ALLOWED_FILE_TYPES: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
  
  // Rate Limiting
  MAX_REQUESTS_PER_MINUTE: 60,
  MAX_LOGIN_ATTEMPTS: 5,
  LOCKOUT_DURATION_MINUTES: 15,
} as const;" "App Constants"

    create_file "src/SharedKernel/Constants/ErrorMessages.ts" "export const ErrorMessages = {
  // Validation
  REQUIRED_FIELD: 'This field is required',
  INVALID_EMAIL: 'Please enter a valid email address',
  INVALID_PASSWORD: 'Password must be at least 8 characters long',
  PASSWORDS_DONT_MATCH: 'Passwords do not match',
  
  // Authentication
  INVALID_CREDENTIALS: 'Invalid email or password',
  ACCOUNT_LOCKED: 'Account is temporarily locked due to too many failed attempts',
  TOKEN_EXPIRED: 'Your session has expired. Please log in again',
  UNAUTHORIZED: 'You are not authorized to perform this action',
  
  // User Management
  USER_NOT_FOUND: 'User not found',
  USER_ALREADY_EXISTS: 'A user with this email already exists',
  USER_INACTIVE: 'User account is inactive',
  
  // General
  INTERNAL_SERVER_ERROR: 'An internal server error occurred',
  BAD_REQUEST: 'Invalid request data',
  NOT_FOUND: 'Resource not found',
  FORBIDDEN: 'Access forbidden',
  
  // File Upload
  FILE_TOO_LARGE: 'File size exceeds the maximum allowed limit',
  INVALID_FILE_TYPE: 'File type is not allowed',
  
  // Rate Limiting
  TOO_MANY_REQUESTS: 'Too many requests. Please try again later',
} as const;" "Error Messages"

    create_file "src/SharedKernel/Constants/HttpStatusCodes.ts" "export const HttpStatusCodes = {
  // Success
  OK: 200,
  CREATED: 201,
  ACCEPTED: 202,
  NO_CONTENT: 204,
  
  // Client Error
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  METHOD_NOT_ALLOWED: 405,
  CONFLICT: 409,
  UNPROCESSABLE_ENTITY: 422,
  TOO_MANY_REQUESTS: 429,
  
  // Server Error
  INTERNAL_SERVER_ERROR: 500,
  NOT_IMPLEMENTED: 501,
  BAD_GATEWAY: 502,
  SERVICE_UNAVAILABLE: 503,
  GATEWAY_TIMEOUT: 504,
} as const;" "HTTP Status Codes"
fi

echo -e "${BLUE}🎯 Step 4: Creating Common Types...${NC}"

create_file "src/SharedKernel/Types/CommonTypes.ts" "// Common result type for operations that can fail
export type Result<T, E = Error> = {
  success: true;
  data: T;
} | {
  success: false;
  error: E;
};

// Pagination types
export interface PaginationOptions {
  page: number;
  limit: number;
  search?: string;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
  hasNext: boolean;
  hasPrevious: boolean;
}

// API Response types
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  timestamp: string;
}

export interface ApiError {
  code: string;
  message: string;
  details?: any;
}

// Event types
export interface EventMetadata {
  eventId: string;
  eventType: string;
  aggregateId: string;
  aggregateType: string;
  version: number;
  occurredOn: Date;
  userId?: string;
}

// Configuration types
export interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  ssl?: boolean;
  poolSize?: number;
}

export interface EmailConfig {
  host: string;
  port: number;
  secure: boolean;
  auth: {
    user: string;
    pass: string;
  };
  from: string;
}

export interface JwtConfig {
  secret: string;
  expiresIn: string;
  refreshExpiresIn: string;
}" "Common Types"

echo -e "${BLUE}🛡️  Step 5: Creating Exception Classes...${NC}"

create_file "src/SharedKernel/Exceptions/DomainException.ts" "export abstract class DomainException extends Error {
  public readonly code: string;

  protected constructor(message: string, code: string) {
    super(message);
    this.name = this.constructor.name;
    this.code = code;
    
    // Maintains proper stack trace for where our error was thrown
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }
}" "Domain Exception"

create_file "src/SharedKernel/Exceptions/ValidationException.ts" "import { DomainException } from './DomainException';

export class ValidationException extends DomainException {
  public readonly validationErrors: string[];

  constructor(message: string, validationErrors: string[] = []) {
    super(message, 'VALIDATION_ERROR');
    this.validationErrors = validationErrors;
  }

  public static fromErrors(errors: string[]): ValidationException {
    return new ValidationException('Validation failed', errors);
  }
}" "Validation Exception"

create_file "src/SharedKernel/Exceptions/NotFoundException.ts" "import { DomainException } from './DomainException';

export class NotFoundException extends DomainException {
  constructor(resource: string, identifier: string) {
    super(\`\${resource} with identifier '\${identifier}' was not found\`, 'NOT_FOUND');
  }
}" "Not Found Exception"

create_file "src/SharedKernel/Exceptions/UnauthorizedException.ts" "import { DomainException } from './DomainException';

export class UnauthorizedException extends DomainException {
  constructor(message: string = 'Unauthorized access') {
    super(message, 'UNAUTHORIZED');
  }
}" "Unauthorized Exception"

echo -e "${BLUE}🔄 Step 6: Creating Helper Functions...${NC}"

create_file "src/SharedKernel/Helpers/ResultHelper.ts" "import { Result } from '../Types/CommonTypes';

export class ResultHelper {
  public static success<T>(data: T): Result<T> {
    return {
      success: true,
      data
    };
  }

  public static failure<T, E = Error>(error: E): Result<T, E> {
    return {
      success: false,
      error
    };
  }

  public static isSuccess<T, E>(result: Result<T, E>): result is { success: true; data: T } {
    return result.success;
  }

  public static isFailure<T, E>(result: Result<T, E>): result is { success: false; error: E } {
    return !result.success;
  }
}" "Result Helper"

create_file "src/SharedKernel/Helpers/PaginationHelper.ts" "import { PaginationOptions, PaginatedResult } from '../Types/CommonTypes';

export class PaginationHelper {
  public static createPaginatedResult<T>(
    items: T[],
    total: number,
    options: PaginationOptions
  ): PaginatedResult<T> {
    const totalPages = Math.ceil(total / options.limit);
    
    return {
      items,
      total,
      page: options.page,
      limit: options.limit,
      totalPages,
      hasNext: options.page < totalPages,
      hasPrevious: options.page > 1
    };
  }

  public static validatePaginationOptions(options: PaginationOptions): PaginationOptions {
    return {
      ...options,
      page: Math.max(1, options.page),
      limit: Math.min(100, Math.max(1, options.limit))
    };
  }

  public static calculateOffset(page: number, limit: number): number {
    return (page - 1) * limit;
  }
}" "Pagination Helper"

echo -e "${BLUE}📋 Step 7: Creating Index Files...${NC}"

create_file "src/SharedKernel/index.ts" "// Base Classes
export { BaseEntity } from './BaseEntity';
export { AggregateRoot } from './AggregateRoot';
export { DomainEvent } from './DomainEvent';
export { ValueObject } from './ValueObject';

// Types
export * from './Types/CommonTypes';

// Constants
export { AppConstants } from './Constants/AppConstants';
export { ErrorMessages } from './Constants/ErrorMessages';
export { HttpStatusCodes } from './Constants/HttpStatusCodes';

// Exceptions
export { DomainException } from './Exceptions/DomainException';
export { ValidationException } from './Exceptions/ValidationException';
export { NotFoundException } from './Exceptions/NotFoundException';
export { UnauthorizedException } from './Exceptions/UnauthorizedException';

// Helpers
export { ResultHelper } from './Helpers/ResultHelper';
export { PaginationHelper } from './Helpers/PaginationHelper';

// Utils
export { DateUtils } from './Utils/DateUtils';
export { StringUtils } from './Utils/StringUtils';
export { ValidationUtils } from './Utils/ValidationUtils';" "Shared Kernel Index"

# Update migration status
echo -e "${BLUE}📊 Updating migration status...${NC}"
jq '.phases["05-shared-kernel"] = "completed" | .current_phase = "06-configuration"' migration-temp/migration-status.json > migration-temp/migration-status-tmp.json && mv migration-temp/migration-status-tmp.json migration-temp/migration-status.json

echo -e "${GREEN}🎉 Shared Kernel Migration Completed!${NC}"
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "  • Base Classes: $(find src/SharedKernel -name "Base*.ts" -o -name "Aggregate*.ts" -o -name "Domain*.ts" -o -name "Value*.ts" | wc -l) files"
echo -e "  • Utilities: $(find src/SharedKernel/Utils -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Constants: $(find src/SharedKernel/Constants -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Types: $(find src/SharedKernel/Types -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Exceptions: $(find src/SharedKernel/Exceptions -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "  • Helpers: $(find src/SharedKernel/Helpers -name "*.ts" 2>/dev/null | wc -l || echo 0) files"
echo -e "${YELLOW}➡️  Next: Run ./migration-scripts/06-migrate-configuration.sh${NC}"
