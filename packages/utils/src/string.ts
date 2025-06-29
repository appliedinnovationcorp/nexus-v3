/**
 * Capitalizes the first letter of a string and converts the rest to lowercase
 * 
 * @param str - The string to capitalize
 * @returns The capitalized string
 * 
 * @example
 * // Returns "Hello"
 * capitalize("hello")
 * 
 * @example
 * // Returns "World"
 * capitalize("WORLD")
 * 
 * @throws Error if str is null or undefined
 */
export function capitalize(str: string): string {
  if (str === null || str === undefined) {
    throw new Error('String to capitalize cannot be null or undefined')
  }
  if (!str) return str
  return str.charAt(0).toUpperCase() + str.slice(1).toLowerCase()
}

/**
 * Converts a string to kebab-case (lowercase with hyphens)
 * 
 * @param str - The string to convert
 * @returns The kebab-cased string
 * 
 * @example
 * // Returns "hello-world"
 * kebabCase("HelloWorld")
 * 
 * @example
 * // Returns "my-variable-name"
 * kebabCase("myVariableName")
 * 
 * @throws Error if str is null or undefined
 */
export function kebabCase(str: string): string {
  if (str === null || str === undefined) {
    throw new Error('String to convert cannot be null or undefined')
  }
  return str
    .replace(/([a-z])([A-Z])/g, '$1-$2')
    .replace(/[\s_]+/g, '-')
    .toLowerCase()
}

/**
 * Converts a string to camelCase
 * 
 * @param str - The string to convert
 * @returns The camelCased string
 * 
 * @example
 * // Returns "helloWorld"
 * camelCase("hello world")
 * 
 * @example
 * // Returns "myVariableName"
 * camelCase("my-variable-name")
 * 
 * @throws Error if str is null or undefined
 */
export function camelCase(str: string): string {
  if (str === null || str === undefined) {
    throw new Error('String to convert cannot be null or undefined')
  }
  return str
    .replace(/(?:^\w|[A-Z]|\b\w)/g, (word, index) => {
      return index === 0 ? word.toLowerCase() : word.toUpperCase()
    })
    .replace(/\s+/g, '')
}

/**
 * Converts a string to PascalCase
 * 
 * @param str - The string to convert
 * @returns The PascalCased string
 * 
 * @example
 * // Returns "HelloWorld"
 * pascalCase("hello world")
 * 
 * @example
 * // Returns "MyVariableName"
 * pascalCase("my-variable-name")
 * 
 * @throws Error if str is null or undefined
 */
export function pascalCase(str: string): string {
  if (str === null || str === undefined) {
    throw new Error('String to convert cannot be null or undefined')
  }
  return str
    .replace(/(?:^\w|[A-Z]|\b\w)/g, (word) => word.toUpperCase())
    .replace(/\s+/g, '')
}

/**
 * Truncates a string to a specified length and adds a suffix
 * 
 * @param str - The string to truncate
 * @param length - Maximum length of the resulting string
 * @param suffix - Suffix to add when truncating (default: '...')
 * @returns The truncated string with suffix if needed
 * 
 * @example
 * // Returns "Hello..."
 * truncate("Hello World", 8)
 * 
 * @example
 * // Returns "Hello World" (no truncation needed)
 * truncate("Hello World", 20)
 * 
 * @throws Error if str is null or undefined
 * @throws Error if length is negative
 */
export function truncate(str: string, length: number, suffix: string = '...'): string {
  if (str === null || str === undefined) {
    throw new Error('String to truncate cannot be null or undefined')
  }
  if (length < 0) {
    throw new Error('Length cannot be negative')
  }
  if (str.length <= length) return str
  return str.slice(0, length - suffix.length) + suffix
}

/**
 * Generates a cryptographically secure random string
 * 
 * @param length - Length of the random string (default: 8)
 * @param charset - Character set to use (default: alphanumeric)
 * @returns A cryptographically secure random string
 * 
 * @example
 * // Returns something like "aB3xY9mK"
 * secureRandomString(8)
 * 
 * @example
 * // Returns something like "abc123"
 * secureRandomString(6, "abc123")
 * 
 * @throws Error if length is negative or zero
 * @throws Error if charset is empty
 */
export function secureRandomString(
  length: number = 8, 
  charset: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
): string {
  if (length <= 0) {
    throw new Error('Length must be positive')
  }
  if (!charset) {
    throw new Error('Charset cannot be empty')
  }

  // Use crypto.getRandomValues for browser or crypto.randomBytes for Node.js
  let randomBytes: Uint8Array
  
  if (typeof window !== 'undefined' && window.crypto && window.crypto.getRandomValues) {
    // Browser environment
    randomBytes = new Uint8Array(length)
    window.crypto.getRandomValues(randomBytes)
  } else if (typeof require !== 'undefined') {
    // Node.js environment
    try {
      const crypto = require('crypto')
      const buffer = crypto.randomBytes(length)
      randomBytes = new Uint8Array(buffer)
    } catch (error) {
      throw new Error('Crypto module not available')
    }
  } else {
    throw new Error('No secure random number generator available')
  }

  let result = ''
  for (let i = 0; i < length; i++) {
    const randomIndex = randomBytes[i] % charset.length
    result += charset.charAt(randomIndex)
  }

  return result
}

/**
 * @deprecated Use secureRandomString instead for cryptographically secure random strings
 * Generates a random string using Math.random() (NOT cryptographically secure)
 * 
 * @param length - Length of the random string (default: 8)
 * @returns A random string (NOT cryptographically secure)
 */
export function randomString(length: number = 8): string {
  console.warn('randomString() is deprecated and not cryptographically secure. Use secureRandomString() instead.')
  
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  let result = ''
  
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  
  return result
}

/**
 * Generates a URL-friendly slug from a string
 * 
 * @param str - The string to convert to a slug
 * @returns A URL-friendly slug
 * 
 * @example
 * // Returns "hello-world"
 * slugify("Hello World!")
 * 
 * @example
 * // Returns "my-awesome-post"
 * slugify("My Awesome Post!!!")
 * 
 * @throws Error if str is null or undefined
 */
export function slugify(str: string): string {
  if (str === null || str === undefined) {
    throw new Error('String to slugify cannot be null or undefined')
  }
  return str
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '')
    .replace(/[\s_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

/**
 * Extracts initials from a full name
 * 
 * @param name - The full name to extract initials from
 * @param maxLength - Maximum number of initials to return (default: 2)
 * @returns The initials in uppercase
 * 
 * @example
 * // Returns "JD"
 * getInitials("John Doe")
 * 
 * @example
 * // Returns "JDS"
 * getInitials("John Doe Smith", 3)
 * 
 * @throws Error if name is null or undefined
 * @throws Error if maxLength is negative
 */
export function getInitials(name: string, maxLength: number = 2): string {
  if (name === null || name === undefined) {
    throw new Error('Name cannot be null or undefined')
  }
  if (maxLength < 0) {
    throw new Error('Max length cannot be negative')
  }
  return name
    .split(' ')
    .filter(word => word.length > 0)
    .map(word => word.charAt(0).toUpperCase())
    .slice(0, maxLength)
    .join('')
}

/**
 * Masks a string by replacing middle characters with a mask character
 * 
 * @param str - The string to mask
 * @param visibleStart - Number of characters to show at the beginning (default: 2)
 * @param visibleEnd - Number of characters to show at the end (default: 2)
 * @param maskChar - Character to use for masking (default: '*')
 * @returns The masked string
 * 
 * @example
 * // Returns "jo******th"
 * maskString("johnsmith", 2, 2, "*")
 * 
 * @example
 * // Returns "em***@example.com"
 * maskString("email@example.com", 2, 12, "*")
 * 
 * @throws Error if str is null or undefined
 * @throws Error if visibleStart or visibleEnd are negative
 */
export function maskString(str: string, visibleStart: number = 2, visibleEnd: number = 2, maskChar: string = '*'): string {
  if (str === null || str === undefined) {
    throw new Error('String to mask cannot be null or undefined')
  }
  if (visibleStart < 0 || visibleEnd < 0) {
    throw new Error('Visible start and end positions cannot be negative')
  }
  
  if (str.length <= visibleStart + visibleEnd) {
    return str
  }
  
  const start = str.slice(0, visibleStart)
  const end = str.slice(-visibleEnd)
  const middle = maskChar.repeat(str.length - visibleStart - visibleEnd)
  
  return start + middle + end
}
