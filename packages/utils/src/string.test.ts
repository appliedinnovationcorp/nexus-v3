import { describe, it, expect, vi } from 'vitest'
import {
  capitalize,
  kebabCase,
  camelCase,
  pascalCase,
  truncate,
  secureRandomString,
  randomString,
  slugify,
  getInitials,
  maskString,
} from './string'

describe('String utilities', () => {
  describe('capitalize', () => {
    it('capitalizes first letter and lowercases rest', () => {
      expect(capitalize('hello')).toBe('Hello')
      expect(capitalize('WORLD')).toBe('World')
      expect(capitalize('hELLo WoRLD')).toBe('Hello world')
    })

    it('handles empty string', () => {
      expect(capitalize('')).toBe('')
    })

    it('throws error for null/undefined', () => {
      expect(() => capitalize(null as any)).toThrow('String to capitalize cannot be null or undefined')
      expect(() => capitalize(undefined as any)).toThrow('String to capitalize cannot be null or undefined')
    })
  })

  describe('kebabCase', () => {
    it('converts to kebab-case', () => {
      expect(kebabCase('HelloWorld')).toBe('hello-world')
      expect(kebabCase('myVariableName')).toBe('my-variable-name')
      expect(kebabCase('hello world')).toBe('hello-world')
      expect(kebabCase('hello_world')).toBe('hello-world')
    })

    it('throws error for null/undefined', () => {
      expect(() => kebabCase(null as any)).toThrow('String to convert cannot be null or undefined')
    })
  })

  describe('camelCase', () => {
    it('converts to camelCase', () => {
      expect(camelCase('hello world')).toBe('helloWorld')
      expect(camelCase('my-variable-name')).toBe('myVariableName')
      expect(camelCase('Hello World')).toBe('helloWorld')
    })

    it('throws error for null/undefined', () => {
      expect(() => camelCase(null as any)).toThrow('String to convert cannot be null or undefined')
    })
  })

  describe('pascalCase', () => {
    it('converts to PascalCase', () => {
      expect(pascalCase('hello world')).toBe('HelloWorld')
      expect(pascalCase('my-variable-name')).toBe('MyVariableName')
    })

    it('throws error for null/undefined', () => {
      expect(() => pascalCase(null as any)).toThrow('String to convert cannot be null or undefined')
    })
  })

  describe('truncate', () => {
    it('truncates string with default suffix', () => {
      expect(truncate('Hello World', 8)).toBe('Hello...')
      expect(truncate('Hello World', 20)).toBe('Hello World')
    })

    it('truncates with custom suffix', () => {
      expect(truncate('Hello World', 8, '---')).toBe('Hello---')
    })

    it('throws error for negative length', () => {
      expect(() => truncate('hello', -1)).toThrow('Length cannot be negative')
    })

    it('throws error for null/undefined', () => {
      expect(() => truncate(null as any, 5)).toThrow('String to truncate cannot be null or undefined')
    })
  })

  describe('secureRandomString', () => {
    it('generates string of correct length', () => {
      const result = secureRandomString(10)
      expect(result).toHaveLength(10)
    })

    it('uses custom charset', () => {
      const result = secureRandomString(10, 'abc')
      expect(result).toMatch(/^[abc]+$/)
    })

    it('throws error for invalid length', () => {
      expect(() => secureRandomString(0)).toThrow('Length must be positive')
      expect(() => secureRandomString(-1)).toThrow('Length must be positive')
    })

    it('throws error for empty charset', () => {
      expect(() => secureRandomString(5, '')).toThrow('Charset cannot be empty')
    })
  })

  describe('randomString (deprecated)', () => {
    it('generates string of correct length', () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {})
      const result = randomString(8)
      expect(result).toHaveLength(8)
      expect(consoleSpy).toHaveBeenCalledWith(
        'randomString() is deprecated and not cryptographically secure. Use secureRandomString() instead.'
      )
      consoleSpy.mockRestore()
    })
  })

  describe('slugify', () => {
    it('creates URL-friendly slug', () => {
      expect(slugify('Hello World!')).toBe('hello-world')
      expect(slugify('My Awesome Post!!!')).toBe('my-awesome-post')
      expect(slugify('  Spaced  Out  ')).toBe('spaced-out')
    })

    it('throws error for null/undefined', () => {
      expect(() => slugify(null as any)).toThrow('String to slugify cannot be null or undefined')
    })
  })

  describe('getInitials', () => {
    it('extracts initials from name', () => {
      expect(getInitials('John Doe')).toBe('JD')
      expect(getInitials('John Doe Smith', 3)).toBe('JDS')
      expect(getInitials('John')).toBe('J')
    })

    it('handles extra spaces', () => {
      expect(getInitials('John  Doe')).toBe('JD')
      expect(getInitials(' John Doe ')).toBe('JD')
    })

    it('throws error for negative maxLength', () => {
      expect(() => getInitials('John Doe', -1)).toThrow('Max length cannot be negative')
    })

    it('throws error for null/undefined', () => {
      expect(() => getInitials(null as any)).toThrow('Name cannot be null or undefined')
    })
  })

  describe('maskString', () => {
    it('masks string correctly', () => {
      expect(maskString('johnsmith', 2, 2, '*')).toBe('jo******th')
      expect(maskString('email@example.com', 2, 12, '*')).toBe('em***@example.com')
    })

    it('returns original string if too short', () => {
      expect(maskString('abc', 2, 2)).toBe('abc')
    })

    it('throws error for negative positions', () => {
      expect(() => maskString('test', -1, 2)).toThrow('Visible start and end positions cannot be negative')
      expect(() => maskString('test', 2, -1)).toThrow('Visible start and end positions cannot be negative')
    })

    it('throws error for null/undefined', () => {
      expect(() => maskString(null as any)).toThrow('String to mask cannot be null or undefined')
    })
  })
})
