// Authentication and Authorization Type Definitions

export interface User {
  id: string;
  keycloakId: string;
  email: string;
  username: string;
  firstName?: string;
  lastName?: string;
  phone?: string;
  emailVerified: boolean;
  phoneVerified: boolean;
  mfaEnabled: boolean;
  mfaSecret?: string;
  backupCodes?: string[];
  lastLoginAt?: Date;
  failedLoginAttempts: number;
  lockedUntil?: Date;
  passwordChangedAt?: Date;
  status: UserStatus;
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
  version: number;
}

export enum UserStatus {
  ACTIVE = 'ACTIVE',
  INACTIVE = 'INACTIVE',
  SUSPENDED = 'SUSPENDED',
  LOCKED = 'LOCKED'
}

export interface Session {
  id: string;
  sessionToken: string;
  userId: string;
  ipAddress?: string;
  userAgent?: string;
  deviceFingerprint?: string;
  isMobile: boolean;
  location?: GeoLocation;
  expiresAt: Date;
  lastActivityAt: Date;
  isActive: boolean;
  logoutReason?: string;
  createdAt: Date;
}

export interface GeoLocation {
  country?: string;
  region?: string;
  city?: string;
  latitude?: number;
  longitude?: number;
}

export interface ApiKey {
  id: string;
  keyId: string;
  keyHash: string;
  keyPrefix: string;
  userId?: string;
  name: string;
  description?: string;
  scopes: string[];
  rateLimitPerHour: number;
  rateLimitPerDay: number;
  allowedIps?: string[];
  allowedDomains?: string[];
  lastUsedAt?: Date;
  usageCount: number;
  expiresAt?: Date;
  isActive: boolean;
  autoRotate: boolean;
  rotationIntervalDays: number;
  nextRotationAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface MfaMethod {
  id: string;
  userId: string;
  methodType: MfaMethodType;
  methodData: Record<string, any>;
  isPrimary: boolean;
  isVerified: boolean;
  backupCodes?: string[];
  createdAt: Date;
  verifiedAt?: Date;
  lastUsedAt?: Date;
}

export enum MfaMethodType {
  TOTP = 'TOTP',
  SMS = 'SMS',
  EMAIL = 'EMAIL',
  WEBAUTHN = 'WEBAUTHN',
  BACKUP_CODES = 'BACKUP_CODES'
}

export interface Role {
  id: string;
  name: string;
  displayName?: string;
  description?: string;
  parentRoleId?: string;
  isSystemRole: boolean;
  isActive: boolean;
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
}

export interface Permission {
  id: string;
  name: string;
  displayName?: string;
  description?: string;
  resource: string;
  action: string;
  conditions: Record<string, any>;
  isSystemPermission: boolean;
  createdAt: Date;
}

export interface UserRole {
  id: string;
  userId: string;
  roleId: string;
  assignedBy?: string;
  assignedAt: Date;
  expiresAt?: Date;
  isActive: boolean;
  conditions: Record<string, any>;
}

export interface Group {
  id: string;
  name: string;
  displayName?: string;
  description?: string;
  parentGroupId?: string;
  isActive: boolean;
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
}

export interface JwtPayload {
  sub: string; // user ID
  email: string;
  username: string;
  roles: string[];
  permissions: string[];
  sessionId: string;
  iat: number;
  exp: number;
  jti: string;
  iss: string;
  aud: string;
  scope?: string;
}

export interface RefreshTokenPayload {
  sub: string;
  sessionId: string;
  tokenVersion: number;
  iat: number;
  exp: number;
  jti: string;
}

export interface AuthEvent {
  id: number;
  eventType: string;
  userId?: string;
  sessionId?: string;
  apiKeyId?: string;
  ipAddress?: string;
  userAgent?: string;
  resource?: string;
  action?: string;
  result: AuthEventResult;
  errorMessage?: string;
  metadata: Record<string, any>;
  createdAt: Date;
}

export enum AuthEventResult {
  SUCCESS = 'SUCCESS',
  FAILURE = 'FAILURE',
  ERROR = 'ERROR'
}

export interface RateLimit {
  id: string;
  identifier: string;
  identifierType: RateLimitType;
  endpoint?: string;
  requestCount: number;
  windowStart: Date;
  windowEnd: Date;
  createdAt: Date;
}

export enum RateLimitType {
  IP = 'IP',
  USER = 'USER',
  API_KEY = 'API_KEY'
}

// Request/Response Types
export interface LoginRequest {
  email: string;
  password: string;
  rememberMe?: boolean;
  mfaCode?: string;
  deviceFingerprint?: string;
}

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  tokenType: string;
  user: Partial<User>;
  mfaRequired?: boolean;
  mfaMethods?: MfaMethodType[];
}

export interface RegisterRequest {
  email: string;
  username: string;
  password: string;
  firstName?: string;
  lastName?: string;
  phone?: string;
}

export interface MfaSetupRequest {
  methodType: MfaMethodType;
  phoneNumber?: string;
  email?: string;
}

export interface MfaSetupResponse {
  secret?: string;
  qrCode?: string;
  backupCodes?: string[];
  verificationRequired: boolean;
}

export interface MfaVerifyRequest {
  methodType: MfaMethodType;
  code: string;
  backupCode?: string;
}

export interface ApiKeyCreateRequest {
  name: string;
  description?: string;
  scopes: string[];
  rateLimitPerHour?: number;
  rateLimitPerDay?: number;
  allowedIps?: string[];
  allowedDomains?: string[];
  expiresAt?: Date;
  autoRotate?: boolean;
  rotationIntervalDays?: number;
}

export interface ApiKeyResponse {
  keyId: string;
  key?: string; // Only returned on creation
  name: string;
  description?: string;
  scopes: string[];
  rateLimitPerHour: number;
  rateLimitPerDay: number;
  allowedIps?: string[];
  allowedDomains?: string[];
  lastUsedAt?: Date;
  usageCount: number;
  expiresAt?: Date;
  isActive: boolean;
  autoRotate: boolean;
  rotationIntervalDays: number;
  nextRotationAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface PermissionCheckRequest {
  resource: string;
  action: string;
  context?: Record<string, any>;
}

export interface PermissionCheckResponse {
  allowed: boolean;
  reason?: string;
  conditions?: Record<string, any>;
}

// Middleware Types
export interface AuthenticatedRequest extends Express.Request {
  user?: User;
  session?: Session;
  apiKey?: ApiKey;
  permissions?: Permission[];
  rateLimitInfo?: {
    remaining: number;
    resetTime: Date;
  };
}

export interface AuthConfig {
  jwt: {
    secret: string;
    refreshSecret: string;
    accessTokenExpiry: string;
    refreshTokenExpiry: string;
    issuer: string;
    audience: string;
  };
  session: {
    secret: string;
    maxAge: number;
    secure: boolean;
    httpOnly: boolean;
    sameSite: 'strict' | 'lax' | 'none';
  };
  mfa: {
    issuer: string;
    window: number;
    backupCodesCount: number;
  };
  rateLimit: {
    windowMs: number;
    maxRequests: number;
    skipSuccessfulRequests: boolean;
  };
  security: {
    bcryptRounds: number;
    maxFailedAttempts: number;
    lockoutDuration: number;
    sessionTimeout: number;
  };
}

// Database Repository Interfaces
export interface UserRepository {
  findById(id: string): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  findByUsername(username: string): Promise<User | null>;
  findByKeycloakId(keycloakId: string): Promise<User | null>;
  create(user: Partial<User>): Promise<User>;
  update(id: string, updates: Partial<User>): Promise<User>;
  delete(id: string): Promise<void>;
  incrementFailedAttempts(id: string): Promise<void>;
  resetFailedAttempts(id: string): Promise<void>;
  lockUser(id: string, until: Date): Promise<void>;
}

export interface SessionRepository {
  findById(id: string): Promise<Session | null>;
  findByToken(token: string): Promise<Session | null>;
  findByUserId(userId: string): Promise<Session[]>;
  create(session: Partial<Session>): Promise<Session>;
  update(id: string, updates: Partial<Session>): Promise<Session>;
  delete(id: string): Promise<void>;
  deleteByUserId(userId: string): Promise<void>;
  cleanupExpired(): Promise<number>;
}

export interface ApiKeyRepository {
  findById(id: string): Promise<ApiKey | null>;
  findByKeyId(keyId: string): Promise<ApiKey | null>;
  findByUserId(userId: string): Promise<ApiKey[]>;
  create(apiKey: Partial<ApiKey>): Promise<ApiKey>;
  update(id: string, updates: Partial<ApiKey>): Promise<ApiKey>;
  delete(id: string): Promise<void>;
  rotateKey(keyId: string): Promise<{ keyId: string; key: string }>;
  findKeysForRotation(): Promise<ApiKey[]>;
}

export interface RoleRepository {
  findById(id: string): Promise<Role | null>;
  findByName(name: string): Promise<Role | null>;
  findAll(): Promise<Role[]>;
  create(role: Partial<Role>): Promise<Role>;
  update(id: string, updates: Partial<Role>): Promise<Role>;
  delete(id: string): Promise<void>;
}

export interface PermissionRepository {
  findById(id: string): Promise<Permission | null>;
  findByName(name: string): Promise<Permission | null>;
  findAll(): Promise<Permission[]>;
  findByResource(resource: string): Promise<Permission[]>;
  create(permission: Partial<Permission>): Promise<Permission>;
  update(id: string, updates: Partial<Permission>): Promise<Permission>;
  delete(id: string): Promise<void>;
}

// Service Interfaces
export interface AuthService {
  login(credentials: LoginRequest, context: AuthContext): Promise<LoginResponse>;
  register(userData: RegisterRequest, context: AuthContext): Promise<User>;
  logout(sessionId: string, context: AuthContext): Promise<void>;
  refreshToken(refreshToken: string, context: AuthContext): Promise<LoginResponse>;
  verifyToken(token: string): Promise<JwtPayload>;
  changePassword(userId: string, oldPassword: string, newPassword: string): Promise<void>;
  resetPassword(email: string): Promise<void>;
  confirmPasswordReset(token: string, newPassword: string): Promise<void>;
}

export interface MfaService {
  setupTotp(userId: string): Promise<MfaSetupResponse>;
  verifyTotp(userId: string, code: string): Promise<boolean>;
  setupSms(userId: string, phoneNumber: string): Promise<MfaSetupResponse>;
  verifySms(userId: string, code: string): Promise<boolean>;
  setupEmail(userId: string, email: string): Promise<MfaSetupResponse>;
  verifyEmail(userId: string, code: string): Promise<boolean>;
  generateBackupCodes(userId: string): Promise<string[]>;
  verifyBackupCode(userId: string, code: string): Promise<boolean>;
  disableMfa(userId: string): Promise<void>;
}

export interface RbacService {
  checkPermission(userId: string, resource: string, action: string, context?: any): Promise<boolean>;
  getUserPermissions(userId: string): Promise<Permission[]>;
  getUserRoles(userId: string): Promise<Role[]>;
  assignRole(userId: string, roleId: string, assignedBy: string): Promise<void>;
  removeRole(userId: string, roleId: string): Promise<void>;
  createRole(role: Partial<Role>): Promise<Role>;
  assignPermissionToRole(roleId: string, permissionId: string): Promise<void>;
  removePermissionFromRole(roleId: string, permissionId: string): Promise<void>;
}

export interface ApiKeyService {
  createApiKey(userId: string, request: ApiKeyCreateRequest): Promise<ApiKeyResponse>;
  getApiKeys(userId: string): Promise<ApiKeyResponse[]>;
  getApiKey(keyId: string): Promise<ApiKeyResponse | null>;
  updateApiKey(keyId: string, updates: Partial<ApiKeyCreateRequest>): Promise<ApiKeyResponse>;
  deleteApiKey(keyId: string): Promise<void>;
  rotateApiKey(keyId: string): Promise<{ keyId: string; key: string }>;
  validateApiKey(key: string): Promise<ApiKey | null>;
  rotateExpiredKeys(): Promise<void>;
}

export interface AuthContext {
  ipAddress?: string;
  userAgent?: string;
  deviceFingerprint?: string;
  location?: GeoLocation;
}

// Error Types
export class AuthError extends Error {
  constructor(
    message: string,
    public code: string,
    public statusCode: number = 400,
    public details?: any
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

export class MfaRequiredError extends AuthError {
  constructor(
    public availableMethods: MfaMethodType[],
    public sessionId: string
  ) {
    super('Multi-factor authentication required', 'MFA_REQUIRED', 200);
  }
}

export class RateLimitError extends AuthError {
  constructor(
    public resetTime: Date,
    public remaining: number = 0
  ) {
    super('Rate limit exceeded', 'RATE_LIMIT_EXCEEDED', 429);
  }
}

export class InsufficientPermissionsError extends AuthError {
  constructor(resource: string, action: string) {
    super(`Insufficient permissions for ${action} on ${resource}`, 'INSUFFICIENT_PERMISSIONS', 403);
  }
}
