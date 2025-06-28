// User roles
export enum UserRole {
  ADMIN = 'admin',
  USER = 'user',
  MODERATOR = 'moderator'
}

// User status
export enum UserStatus {
  ACTIVE = 'active',
  INACTIVE = 'inactive',
  SUSPENDED = 'suspended',
  PENDING = 'pending'
}

// User interface
export interface User {
  id: string
  email: string
  name: string
  avatar?: string
  role: UserRole
  status: UserStatus
  emailVerified: boolean
  createdAt: Date
  updatedAt: Date
  lastLoginAt?: Date
  profile?: UserProfile
}

// User profile
export interface UserProfile {
  id: string
  userId: string
  bio?: string
  website?: string
  location?: string
  phone?: string
  dateOfBirth?: Date
  preferences: UserPreferences
  createdAt: Date
  updatedAt: Date
}

// User preferences
export interface UserPreferences {
  theme: 'light' | 'dark' | 'system'
  language: string
  timezone: string
  notifications: NotificationPreferences
}

// Notification preferences
export interface NotificationPreferences {
  email: boolean
  push: boolean
  sms: boolean
  marketing: boolean
  security: boolean
}

// User creation/update types
export interface CreateUserRequest {
  email: string
  password: string
  name: string
  role?: UserRole
}

export interface UpdateUserRequest {
  name?: string
  avatar?: string
  role?: UserRole
  status?: UserStatus
}

export interface UpdateUserProfileRequest {
  bio?: string
  website?: string
  location?: string
  phone?: string
  dateOfBirth?: Date
}

export interface UpdateUserPreferencesRequest {
  theme?: 'light' | 'dark' | 'system'
  language?: string
  timezone?: string
  notifications?: Partial<NotificationPreferences>
}

// User session
export interface UserSession {
  id: string
  userId: string
  token: string
  refreshToken: string
  expiresAt: Date
  createdAt: Date
  ipAddress?: string
  userAgent?: string
}
