/**
 * Validates an email address using comprehensive RFC-compliant regex
 * 
 * @param email - The email address to validate
 * @returns True if the email is valid, false otherwise
 * 
 * @example
 * // Returns true
 * isValidEmail("user@example.com")
 * 
 * @example
 * // Returns false
 * isValidEmail("invalid-email")
 * 
 * @throws Error if email is null or undefined
 */
export function isValidEmail(email: string): boolean {
  if (email === null || email === undefined) {
    throw new Error('Email cannot be null or undefined')
  }
  
  if (!email) return false
  
  // More comprehensive regex that checks for valid TLDs and proper formatting
  const emailRegex = /^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
  
  if (!emailRegex.test(email)) return false
  
  // Additional checks
  const parts = email.split('@')
  if (parts.length !== 2) return false
  if (parts[0].length > 64) return false // Local part too long
  if (parts[1].length > 255) return false // Domain part too long
  
  // Check for consecutive dots
  if (email.includes('..')) return false
  
  // Check for valid characters in local part
  const localPart = parts[0]
  if (localPart.startsWith('.') || localPart.endsWith('.')) return false
  
  return true
}

/**
 * Validates a phone number with international format support
 * 
 * @param phone - The phone number to validate
 * @param strict - Whether to use strict validation (default: false)
 * @returns True if the phone number is valid, false otherwise
 * 
 * @example
 * // Returns true
 * isValidPhone("+1234567890")
 * 
 * @example
 * // Returns true
 * isValidPhone("(123) 456-7890")
 * 
 * @throws Error if phone is null or undefined
 */
export function isValidPhone(phone: string, strict: boolean = false): boolean {
  if (phone === null || phone === undefined) {
    throw new Error('Phone number cannot be null or undefined')
  }
  
  if (!phone) return false
  
  // Remove all non-digit characters for length check
  const digitsOnly = phone.replace(/\D/g, '')
  
  if (strict) {
    // Strict validation: E.164 format
    const e164Regex = /^\+[1-9]\d{1,14}$/
    return e164Regex.test(phone)
  } else {
    // Flexible validation
    const phoneRegex = /^\+?[\d\s\-\(\)]{10,}$/
    return phoneRegex.test(phone) && digitsOnly.length >= 10 && digitsOnly.length <= 15
  }
}

/**
 * Validates a URL with protocol and domain checks
 * 
 * @param url - The URL to validate
 * @param allowedProtocols - Array of allowed protocols (default: ['http:', 'https:'])
 * @returns True if the URL is valid, false otherwise
 * 
 * @example
 * // Returns true
 * isValidUrl("https://example.com")
 * 
 * @example
 * // Returns false
 * isValidUrl("ftp://example.com", ["http:", "https:"])
 * 
 * @throws Error if url is null or undefined
 */
export function isValidUrl(url: string, allowedProtocols: string[] = ['http:', 'https:']): boolean {
  if (url === null || url === undefined) {
    throw new Error('URL cannot be null or undefined')
  }
  
  try {
    const urlObj = new URL(url)
    
    // Check if protocol is allowed
    if (!allowedProtocols.includes(urlObj.protocol)) {
      return false
    }
    
    // Check if hostname exists
    if (!urlObj.hostname) {
      return false
    }
    
    return true
  } catch {
    return false
  }
}

/**
 * Password validation result interface
 */
export interface PasswordValidationResult {
  isValid: boolean
  score: number
  feedback: string[]
  strength: 'very-weak' | 'weak' | 'fair' | 'good' | 'strong'
}

/**
 * Validates password strength with comprehensive checks
 * 
 * @param password - The password to validate
 * @param minLength - Minimum password length (default: 8)
 * @returns Password validation result with score and feedback
 * 
 * @example
 * // Returns { isValid: true, score: 5, feedback: [], strength: 'strong' }
 * validatePassword("MySecure123!")
 * 
 * @example
 * // Returns { isValid: false, score: 1, feedback: [...], strength: 'very-weak' }
 * validatePassword("123")
 * 
 * @throws Error if password is null or undefined
 */
export function validatePassword(password: string, minLength: number = 8): PasswordValidationResult {
  if (password === null || password === undefined) {
    throw new Error('Password cannot be null or undefined')
  }
  
  const feedback: string[] = []
  let score = 0

  // Length check
  if (password.length < minLength) {
    feedback.push(`Password must be at least ${minLength} characters long`)
  } else {
    score += 1
    if (password.length >= 12) score += 0.5 // Bonus for longer passwords
  }

  // Lowercase letter check
  if (!/[a-z]/.test(password)) {
    feedback.push('Password must contain at least one lowercase letter')
  } else {
    score += 1
  }

  // Uppercase letter check
  if (!/[A-Z]/.test(password)) {
    feedback.push('Password must contain at least one uppercase letter')
  } else {
    score += 1
  }

  // Number check
  if (!/\d/.test(password)) {
    feedback.push('Password must contain at least one number')
  } else {
    score += 1
  }

  // Special character check
  if (!/[!@#$%^&*(),.?":{}|<>]/.test(password)) {
    feedback.push('Password must contain at least one special character')
  } else {
    score += 1
  }

  // Common password patterns check
  const commonPatterns = [
    /(.)\1{2,}/, // Repeated characters
    /123456|654321|qwerty|password|admin/i, // Common sequences
  ]
  
  for (const pattern of commonPatterns) {
    if (pattern.test(password)) {
      feedback.push('Password contains common patterns and may be easily guessed')
      score -= 0.5
      break
    }
  }

  // Determine strength
  let strength: PasswordValidationResult['strength']
  if (score < 2) strength = 'very-weak'
  else if (score < 3) strength = 'weak'
  else if (score < 4) strength = 'fair'
  else if (score < 5) strength = 'good'
  else strength = 'strong'

  return {
    isValid: score >= 4 && feedback.length === 0,
    score: Math.max(0, Math.min(5, Math.round(score))),
    feedback,
    strength
  }
}

/**
 * Validate credit card number using Luhn algorithm
 */
export function isValidCreditCard(cardNumber: string): boolean {
  const num = cardNumber.replace(/\D/g, '')
  
  if (num.length < 13 || num.length > 19) {
    return false
  }

  let sum = 0
  let isEven = false

  for (let i = num.length - 1; i >= 0; i--) {
    let digit = parseInt(num.charAt(i), 10)

    if (isEven) {
      digit *= 2
      if (digit > 9) {
        digit -= 9
      }
    }

    sum += digit
    isEven = !isEven
  }

  return sum % 10 === 0
}

/**
 * Validate if string contains only alphanumeric characters
 */
export function isAlphanumeric(str: string): boolean {
  return /^[a-zA-Z0-9]+$/.test(str)
}

/**
 * Validate if string is a valid hex color
 */
export function isValidHexColor(color: string): boolean {
  return /^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/.test(color)
}
