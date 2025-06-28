import { format, formatDistanceToNow, isValid, parseISO } from 'date-fns'

/**
 * Format a date to a readable string
 */
export function formatDate(date: Date | string, formatStr: string = 'PPP'): string {
  const dateObj = typeof date === 'string' ? parseISO(date) : date
  
  if (!isValid(dateObj)) {
    throw new Error('Invalid date provided')
  }
  
  return format(dateObj, formatStr)
}

/**
 * Get relative time from now (e.g., "2 hours ago")
 */
export function getRelativeTime(date: Date | string): string {
  const dateObj = typeof date === 'string' ? parseISO(date) : date
  
  if (!isValid(dateObj)) {
    throw new Error('Invalid date provided')
  }
  
  return formatDistanceToNow(dateObj, { addSuffix: true })
}

/**
 * Check if a date is today
 */
export function isToday(date: Date | string): boolean {
  const dateObj = typeof date === 'string' ? parseISO(date) : date
  const today = new Date()
  
  return (
    dateObj.getDate() === today.getDate() &&
    dateObj.getMonth() === today.getMonth() &&
    dateObj.getFullYear() === today.getFullYear()
  )
}

/**
 * Get start and end of day for a given date
 */
export function getDayBounds(date: Date | string): { start: Date; end: Date } {
  const dateObj = typeof date === 'string' ? parseISO(date) : new Date(date)
  
  const start = new Date(dateObj)
  start.setHours(0, 0, 0, 0)
  
  const end = new Date(dateObj)
  end.setHours(23, 59, 59, 999)
  
  return { start, end }
}
