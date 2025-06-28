// Common utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>

export type RequiredFields<T, K extends keyof T> = T & Required<Pick<T, K>>

export type DeepPartial<T> = {
  [P in keyof T]?: T[P] extends object ? DeepPartial<T[P]> : T[P]
}

export type Nullable<T> = T | null

export type Maybe<T> = T | null | undefined

// Environment types
export type Environment = 'development' | 'staging' | 'production' | 'test'

// Status types
export type Status = 'active' | 'inactive' | 'pending' | 'suspended'

// Common entity fields
export interface BaseEntity {
  id: string
  createdAt: Date
  updatedAt: Date
}

export interface SoftDeleteEntity extends BaseEntity {
  deletedAt?: Date
}

// File upload types
export interface FileUpload {
  id: string
  filename: string
  originalName: string
  mimetype: string
  size: number
  url: string
  uploadedBy: string
  createdAt: Date
}

// Search and filter types
export interface SearchParams {
  query?: string
  filters?: Record<string, any>
  sort?: {
    field: string
    order: 'asc' | 'desc'
  }
}

// Error types
export interface AppError {
  code: string
  message: string
  details?: any
  timestamp: Date
}

// Configuration types
export interface DatabaseConfig {
  host: string
  port: number
  database: string
  username: string
  password: string
  ssl?: boolean
}

export interface RedisConfig {
  host: string
  port: number
  password?: string
  db?: number
}

export interface EmailConfig {
  host: string
  port: number
  secure: boolean
  auth: {
    user: string
    pass: string
  }
}

// Theme types
export interface Theme {
  colors: {
    primary: string
    secondary: string
    background: string
    foreground: string
    muted: string
    accent: string
    destructive: string
    border: string
    input: string
    ring: string
  }
  fonts: {
    sans: string[]
    serif: string[]
    mono: string[]
  }
  spacing: Record<string, string>
  borderRadius: Record<string, string>
}
