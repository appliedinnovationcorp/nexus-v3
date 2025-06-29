import { describe, it, expect } from 'vitest'
import {
  isValidEmail,
  isValidPhone,
  isValidUrl,
  validatePassword,
  isValidCreditCard,
  isAlphanumeric,
  isValidHexColor,
} from './validation'

describe('Validation utilities', () => {
  describe('isValidEmail', () => {
    it('validates correct emails', () => {
      expect(isValidEmail('user@example.com')).toBe(true)
      expect(isValidEmail('test.email@domain.co.uk')).toBe(true)
      expect(isValidEmail('user+tag@example.org')).toBe(true)
    })

    it('rejects invalid emails', () => {
      expect(isValidEmail('invalid-email')).toBe(false)
      expect(isValidEmail('user@')).toBe(false)
      expect(isValidEmail('@domain.com')).toBe(false)
      expect(isValidEmail('user..double@domain.com')).toBe(false)
      expect(isValidEmail('.user@domain.com')).toBe(false)
      expect(isValidEmail('user.@domain.com')).toBe(false)
    })

    it('rejects emails with parts too long', () => {
      const longLocal = 'a'.repeat(65) + '@domain.com'
      const longDomain = 'user@' + 'a'.repeat(256) + '.com'
      
      expect(isValidEmail(longLocal)).toBe(false)
      expect(isValidEmail(longDomain)).toBe(false)
    })

    it('throws error for null/undefined', () => {
      expect(() => isValidEmail(null as any)).toThrow('Email cannot be null or undefined')
      expect(() => isValidEmail(undefined as any)).toThrow('Email cannot be null or undefined')
    })
  })

  describe('isValidPhone', () => {
    it('validates phone numbers in flexible mode', () => {
      expect(isValidPhone('+1234567890')).toBe(true)
      expect(isValidPhone('(123) 456-7890')).toBe(true)
      expect(isValidPhone('123-456-7890')).toBe(true)
      expect(isValidPhone('1234567890')).toBe(true)
    })

    it('validates phone numbers in strict mode', () => {
      expect(isValidPhone('+1234567890', true)).toBe(true)
      expect(isValidPhone('+44123456789', true)).toBe(true)
      expect(isValidPhone('1234567890', true)).toBe(false) // No + prefix
      expect(isValidPhone('+0123456789', true)).toBe(false) // Starts with 0
    })

    it('rejects invalid phone numbers', () => {
      expect(isValidPhone('123')).toBe(false) // Too short
      expect(isValidPhone('abc123def456')).toBe(false) // Contains letters
      expect(isValidPhone('')).toBe(false)
    })

    it('throws error for null/undefined', () => {
      expect(() => isValidPhone(null as any)).toThrow('Phone number cannot be null or undefined')
    })
  })

  describe('isValidUrl', () => {
    it('validates correct URLs', () => {
      expect(isValidUrl('https://example.com')).toBe(true)
      expect(isValidUrl('http://subdomain.example.org/path')).toBe(true)
      expect(isValidUrl('https://example.com:8080/path?query=value')).toBe(true)
    })

    it('rejects invalid URLs', () => {
      expect(isValidUrl('not-a-url')).toBe(false)
      expect(isValidUrl('ftp://example.com')).toBe(false) // Not in allowed protocols
      expect(isValidUrl('https://')).toBe(false) // No hostname
    })

    it('respects allowed protocols', () => {
      expect(isValidUrl('ftp://example.com', ['ftp:'])).toBe(true)
      expect(isValidUrl('https://example.com', ['ftp:'])).toBe(false)
    })

    it('throws error for null/undefined', () => {
      expect(() => isValidUrl(null as any)).toThrow('URL cannot be null or undefined')
    })
  })

  describe('validatePassword', () => {
    it('validates strong password', () => {
      const result = validatePassword('MySecure123!')
      expect(result.isValid).toBe(true)
      expect(result.strength).toBe('strong')
      expect(result.feedback).toHaveLength(0)
    })

    it('validates weak password', () => {
      const result = validatePassword('123')
      expect(result.isValid).toBe(false)
      expect(result.strength).toBe('very-weak')
      expect(result.feedback.length).toBeGreaterThan(0)
    })

    it('detects common patterns', () => {
      const result = validatePassword('Password123!')
      expect(result.feedback.some(f => f.includes('common patterns'))).toBe(true)
    })

    it('gives bonus for longer passwords', () => {
      const short = validatePassword('Abc123!')
      const long = validatePassword('MyVeryLongPassword123!')
      expect(long.score).toBeGreaterThan(short.score)
    })

    it('respects custom minimum length', () => {
      const result = validatePassword('Abc123!', 10)
      expect(result.feedback.some(f => f.includes('10 characters'))).toBe(true)
    })

    it('throws error for null/undefined', () => {
      expect(() => validatePassword(null as any)).toThrow('Password cannot be null or undefined')
    })
  })

  describe('isValidCreditCard', () => {
    it('validates correct credit card numbers', () => {
      expect(isValidCreditCard('4532015112830366')).toBe(true) // Visa
      expect(isValidCreditCard('5555555555554444')).toBe(true) // Mastercard
      expect(isValidCreditCard('4532-0151-1283-0366')).toBe(true) // With dashes
    })

    it('rejects invalid credit card numbers', () => {
      expect(isValidCreditCard('1234567890123456')).toBe(false) // Invalid Luhn
      expect(isValidCreditCard('123')).toBe(false) // Too short
      expect(isValidCreditCard('12345678901234567890')).toBe(false) // Too long
    })
  })

  describe('isAlphanumeric', () => {
    it('validates alphanumeric strings', () => {
      expect(isAlphanumeric('abc123')).toBe(true)
      expect(isAlphanumeric('ABC123')).toBe(true)
      expect(isAlphanumeric('123')).toBe(true)
      expect(isAlphanumeric('abc')).toBe(true)
    })

    it('rejects non-alphanumeric strings', () => {
      expect(isAlphanumeric('abc-123')).toBe(false)
      expect(isAlphanumeric('abc 123')).toBe(false)
      expect(isAlphanumeric('abc@123')).toBe(false)
    })
  })

  describe('isValidHexColor', () => {
    it('validates hex colors', () => {
      expect(isValidHexColor('#FF0000')).toBe(true)
      expect(isValidHexColor('#f00')).toBe(true)
      expect(isValidHexColor('#123ABC')).toBe(true)
    })

    it('rejects invalid hex colors', () => {
      expect(isValidHexColor('FF0000')).toBe(false) // No #
      expect(isValidHexColor('#GG0000')).toBe(false) // Invalid characters
      expect(isValidHexColor('#FF00')).toBe(false) // Wrong length
    })
  })
})
