import * as React from 'react'
import * as Dialog from '@radix-ui/react-dialog'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '../../utils/cn'

const modalVariants = cva(
  'fixed left-[50%] top-[50%] z-50 grid w-full translate-x-[-50%] translate-y-[-50%] gap-4 border bg-background p-6 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg',
  {
    variants: {
      size: {
        sm: 'max-w-sm',
        default: 'max-w-lg',
        lg: 'max-w-2xl',
        xl: 'max-w-4xl',
        full: 'max-w-[95vw] max-h-[95vh]',
      },
    },
    defaultVariants: {
      size: 'default',
    },
  }
)

export interface ModalProps
  extends React.ComponentPropsWithoutRef<typeof Dialog.Root>,
    VariantProps<typeof modalVariants> {
  /**
   * Whether the modal is open
   */
  open?: boolean
  /**
   * Callback when the modal open state changes
   */
  onOpenChange?: (open: boolean) => void
  /**
   * Modal content
   */
  children: React.ReactNode
  /**
   * Custom className for the modal content
   */
  className?: string
  /**
   * Whether to show the close button
   */
  showCloseButton?: boolean
  /**
   * Whether clicking outside closes the modal
   */
  closeOnOutsideClick?: boolean
  /**
   * Whether pressing escape closes the modal
   */
  closeOnEscape?: boolean
}

/**
 * Modal component built on top of Radix UI Dialog
 * 
 * @example
 * <Modal open={isOpen} onOpenChange={setIsOpen}>
 *   <ModalContent>
 *     <ModalHeader>
 *       <ModalTitle>Modal Title</ModalTitle>
 *       <ModalDescription>Modal description</ModalDescription>
 *     </ModalHeader>
 *     <ModalBody>
 *       <p>Modal content goes here</p>
 *     </ModalBody>
 *     <ModalFooter>
 *       <Button onClick={() => setIsOpen(false)}>Close</Button>
 *     </ModalFooter>
 *   </ModalContent>
 * </Modal>
 */
const Modal = React.forwardRef<
  React.ElementRef<typeof Dialog.Content>,
  ModalProps
>(({ 
  size, 
  className, 
  children, 
  open, 
  onOpenChange, 
  showCloseButton = true,
  closeOnOutsideClick = true,
  closeOnEscape = true,
  ...props 
}, ref) => (
  <Dialog.Root open={open} onOpenChange={onOpenChange} {...props}>
    <Dialog.Portal>
      <Dialog.Overlay className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
      <Dialog.Content
        ref={ref}
        className={cn(modalVariants({ size, className }))}
        onPointerDownOutside={closeOnOutsideClick ? undefined : (e) => e.preventDefault()}
        onEscapeKeyDown={closeOnEscape ? undefined : (e) => e.preventDefault()}
      >
        {children}
        {showCloseButton && (
          <Dialog.Close className="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
            <svg
              className="h-4 w-4"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
            <span className="sr-only">Close</span>
          </Dialog.Close>
        )}
      </Dialog.Content>
    </Dialog.Portal>
  </Dialog.Root>
))
Modal.displayName = 'Modal'

/**
 * Modal trigger component
 */
const ModalTrigger = Dialog.Trigger

/**
 * Modal content wrapper (use this inside Modal)
 */
const ModalContent = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, children, ...props }, ref) => (
  <div ref={ref} className={cn('grid gap-4', className)} {...props}>
    {children}
  </div>
))
ModalContent.displayName = 'ModalContent'

/**
 * Modal header component
 */
const ModalHeader = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn('flex flex-col space-y-1.5 text-center sm:text-left', className)}
    {...props}
  />
))
ModalHeader.displayName = 'ModalHeader'

/**
 * Modal title component
 */
const ModalTitle = React.forwardRef<
  React.ElementRef<typeof Dialog.Title>,
  React.ComponentPropsWithoutRef<typeof Dialog.Title>
>(({ className, ...props }, ref) => (
  <Dialog.Title
    ref={ref}
    className={cn('text-lg font-semibold leading-none tracking-tight', className)}
    {...props}
  />
))
ModalTitle.displayName = 'ModalTitle'

/**
 * Modal description component
 */
const ModalDescription = React.forwardRef<
  React.ElementRef<typeof Dialog.Description>,
  React.ComponentPropsWithoutRef<typeof Dialog.Description>
>(({ className, ...props }, ref) => (
  <Dialog.Description
    ref={ref}
    className={cn('text-sm text-muted-foreground', className)}
    {...props}
  />
))
ModalDescription.displayName = 'ModalDescription'

/**
 * Modal body component
 */
const ModalBody = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div ref={ref} className={cn('py-4', className)} {...props} />
))
ModalBody.displayName = 'ModalBody'

/**
 * Modal footer component
 */
const ModalFooter = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn('flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2', className)}
    {...props}
  />
))
ModalFooter.displayName = 'ModalFooter'

export {
  Modal,
  ModalTrigger,
  ModalContent,
  ModalHeader,
  ModalTitle,
  ModalDescription,
  ModalBody,
  ModalFooter,
  modalVariants,
}
