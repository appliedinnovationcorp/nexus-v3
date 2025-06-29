import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '../../utils/cn'

const inputVariants = cva(
  'flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50',
  {
    variants: {
      variant: {
        default: 'border-input',
        error: 'border-destructive focus-visible:ring-destructive',
        success: 'border-green-500 focus-visible:ring-green-500',
      },
      size: {
        default: 'h-10',
        sm: 'h-9 px-2 text-xs',
        lg: 'h-11 px-4',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  }
)

export interface InputProps
  extends React.InputHTMLAttributes<HTMLInputElement>,
    VariantProps<typeof inputVariants> {
  /**
   * Error message to display below the input
   */
  error?: string
  /**
   * Label text to display above the input
   */
  label?: string
  /**
   * Helper text to display below the input
   */
  helperText?: string
  /**
   * Whether the input is required
   */
  required?: boolean
  /**
   * Icon to display on the left side of the input
   */
  leftIcon?: React.ReactNode
  /**
   * Icon to display on the right side of the input
   */
  rightIcon?: React.ReactNode
  /**
   * Whether to show a loading spinner
   */
  loading?: boolean
}

/**
 * Input component with label, error handling, and accessibility features
 * 
 * @example
 * <Input
 *   label="Email"
 *   placeholder="Enter your email"
 *   type="email"
 *   required
 *   error="Please enter a valid email"
 * />
 */
const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ 
    className, 
    variant, 
    size, 
    error, 
    label, 
    helperText, 
    required, 
    leftIcon, 
    rightIcon, 
    loading,
    id, 
    type,
    disabled,
    ...props 
  }, ref) => {
    const inputId = id || React.useId()
    const errorId = `${inputId}-error`
    const helperId = `${inputId}-helper`
    const labelId = `${inputId}-label`
    
    // Determine variant based on error state
    const inputVariant = error ? 'error' : variant
    
    return (
      <div className="space-y-2">
        {label && (
          <label 
            id={labelId}
            htmlFor={inputId}
            className={cn(
              "block text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70",
              error ? "text-destructive" : "text-foreground"
            )}
          >
            {label}
            {required && (
              <span className="ml-1 text-destructive" aria-label="required">
                *
              </span>
            )}
          </label>
        )}
        
        <div className="relative">
          {leftIcon && (
            <div className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground">
              {leftIcon}
            </div>
          )}
          
          <input
            id={inputId}
            type={type}
            className={cn(
              inputVariants({ variant: inputVariant, size, className }),
              leftIcon && "pl-10",
              (rightIcon || loading) && "pr-10"
            )}
            ref={ref}
            disabled={disabled || loading}
            aria-invalid={!!error}
            aria-describedby={cn(
              error && errorId,
              helperText && !error && helperId
            )}
            aria-labelledby={label ? labelId : undefined}
            aria-required={required}
            {...props}
          />
          
          {(rightIcon || loading) && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
              {loading ? (
                <svg
                  className="h-4 w-4 animate-spin"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  />
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="m4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
              ) : (
                rightIcon
              )}
            </div>
          )}
        </div>
        
        {error && (
          <p 
            id={errorId} 
            className="text-sm text-destructive"
            role="alert"
            aria-live="polite"
          >
            {error}
          </p>
        )}
        
        {helperText && !error && (
          <p 
            id={helperId} 
            className="text-sm text-muted-foreground"
          >
            {helperText}
          </p>
        )}
      </div>
    )
  }
)

Input.displayName = 'Input'

export { Input, inputVariants }
