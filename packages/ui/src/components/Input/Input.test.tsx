import * as React from 'react'
import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import { Input } from './Input'

describe('Input', () => {
  it('renders correctly', () => {
    render(<Input placeholder="Enter text" />)
    expect(screen.getByPlaceholderText('Enter text')).toBeInTheDocument()
  })

  it('renders with label', () => {
    render(<Input label="Email" placeholder="Enter email" />)
    
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByText('Email')).toBeInTheDocument()
  })

  it('shows required indicator', () => {
    render(<Input label="Email" required />)
    
    expect(screen.getByText('*')).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toHaveAttribute('aria-required', 'true')
  })

  it('displays error message', () => {
    render(<Input label="Email" error="Invalid email" />)
    
    const input = screen.getByLabelText('Email')
    const errorMessage = screen.getByText('Invalid email')
    
    expect(input).toHaveAttribute('aria-invalid', 'true')
    expect(input).toHaveAttribute('aria-describedby', expect.stringContaining('error'))
    expect(errorMessage).toHaveAttribute('role', 'alert')
    expect(errorMessage).toHaveAttribute('aria-live', 'polite')
  })

  it('displays helper text', () => {
    render(<Input label="Password" helperText="Must be at least 8 characters" />)
    
    const input = screen.getByLabelText('Password')
    const helperText = screen.getByText('Must be at least 8 characters')
    
    expect(input).toHaveAttribute('aria-describedby', expect.stringContaining('helper'))
    expect(helperText).toBeInTheDocument()
  })

  it('prioritizes error over helper text', () => {
    render(
      <Input 
        label="Email" 
        error="Invalid email" 
        helperText="Enter your email address" 
      />
    )
    
    expect(screen.getByText('Invalid email')).toBeInTheDocument()
    expect(screen.queryByText('Enter your email address')).not.toBeInTheDocument()
  })

  it('handles input changes', () => {
    const handleChange = vi.fn()
    render(<Input onChange={handleChange} />)
    
    const input = screen.getByRole('textbox')
    fireEvent.change(input, { target: { value: 'test' } })
    
    expect(handleChange).toHaveBeenCalledTimes(1)
    expect(input).toHaveValue('test')
  })

  it('shows loading state', () => {
    render(<Input loading />)
    
    const input = screen.getByRole('textbox')
    expect(input).toBeDisabled()
    expect(screen.getByRole('textbox').parentElement?.querySelector('svg')).toBeInTheDocument()
  })

  it('renders with icons', () => {
    const LeftIcon = () => <span data-testid="left-icon">@</span>
    const RightIcon = () => <span data-testid="right-icon">✓</span>

    render(<Input leftIcon={<LeftIcon />} rightIcon={<RightIcon />} />)

    expect(screen.getByTestId('left-icon')).toBeInTheDocument()
    expect(screen.getByTestId('right-icon')).toBeInTheDocument()
  })

  it('applies different variants', () => {
    const { rerender } = render(<Input variant="error" />)
    expect(screen.getByRole('textbox')).toHaveClass('border-destructive')

    rerender(<Input variant="success" />)
    expect(screen.getByRole('textbox')).toHaveClass('border-green-500')
  })

  it('applies different sizes', () => {
    const { rerender } = render(<Input size="sm" />)
    expect(screen.getByRole('textbox')).toHaveClass('h-9')

    rerender(<Input size="lg" />)
    expect(screen.getByRole('textbox')).toHaveClass('h-11')
  })

  it('is disabled when disabled prop is true', () => {
    render(<Input disabled />)
    expect(screen.getByRole('textbox')).toBeDisabled()
  })

  it('supports different input types', () => {
    const { rerender } = render(<Input type="email" />)
    expect(screen.getByRole('textbox')).toHaveAttribute('type', 'email')

    rerender(<Input type="password" />)
    expect(screen.getByDisplayValue('')).toHaveAttribute('type', 'password')
  })

  it('forwards ref correctly', () => {
    const ref = React.createRef<HTMLInputElement>()
    render(<Input ref={ref} />)
    
    expect(ref.current).toBeInstanceOf(HTMLInputElement)
  })

  it('generates unique IDs', () => {
    render(
      <div>
        <Input label="First" />
        <Input label="Second" />
      </div>
    )
    
    const inputs = screen.getAllByRole('textbox')
    expect(inputs[0].id).not.toBe(inputs[1].id)
  })

  it('uses provided ID', () => {
    render(<Input id="custom-id" label="Custom" />)
    
    const input = screen.getByRole('textbox')
    expect(input).toHaveAttribute('id', 'custom-id')
    expect(screen.getByText('Custom')).toHaveAttribute('for', 'custom-id')
  })
})
