import type { Meta, StoryObj } from '@storybook/react';
import { action } from '@storybook/addon-actions';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  parameters: {
    layout: 'centered',
    docs: {
      description: {
        component: 'A versatile button component with multiple variants and states.',
      },
    },
  },
  tags: ['autodocs'],
  argTypes: {
    variant: {
      control: { type: 'select' },
      options: ['primary', 'secondary', 'outline', 'ghost', 'destructive'],
      description: 'The visual style variant of the button',
    },
    size: {
      control: { type: 'select' },
      options: ['sm', 'md', 'lg'],
      description: 'The size of the button',
    },
    disabled: {
      control: { type: 'boolean' },
      description: 'Whether the button is disabled',
    },
    loading: {
      control: { type: 'boolean' },
      description: 'Whether the button is in a loading state',
    },
    fullWidth: {
      control: { type: 'boolean' },
      description: 'Whether the button should take full width',
    },
    onClick: {
      action: 'clicked',
      description: 'Function called when button is clicked',
    },
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

// Default story
export const Default: Story = {
  args: {
    children: 'Button',
    onClick: action('button-click'),
  },
};

// Primary variant
export const Primary: Story = {
  args: {
    variant: 'primary',
    children: 'Primary Button',
    onClick: action('primary-click'),
  },
};

// Secondary variant
export const Secondary: Story = {
  args: {
    variant: 'secondary',
    children: 'Secondary Button',
    onClick: action('secondary-click'),
  },
};

// Outline variant
export const Outline: Story = {
  args: {
    variant: 'outline',
    children: 'Outline Button',
    onClick: action('outline-click'),
  },
};

// Ghost variant
export const Ghost: Story = {
  args: {
    variant: 'ghost',
    children: 'Ghost Button',
    onClick: action('ghost-click'),
  },
};

// Destructive variant
export const Destructive: Story = {
  args: {
    variant: 'destructive',
    children: 'Delete',
    onClick: action('destructive-click'),
  },
};

// Different sizes
export const Small: Story = {
  args: {
    size: 'sm',
    children: 'Small Button',
    onClick: action('small-click'),
  },
};

export const Medium: Story = {
  args: {
    size: 'md',
    children: 'Medium Button',
    onClick: action('medium-click'),
  },
};

export const Large: Story = {
  args: {
    size: 'lg',
    children: 'Large Button',
    onClick: action('large-click'),
  },
};

// States
export const Disabled: Story = {
  args: {
    disabled: true,
    children: 'Disabled Button',
    onClick: action('disabled-click'),
  },
};

export const Loading: Story = {
  args: {
    loading: true,
    children: 'Loading...',
    onClick: action('loading-click'),
  },
};

export const FullWidth: Story = {
  args: {
    fullWidth: true,
    children: 'Full Width Button',
    onClick: action('full-width-click'),
  },
  parameters: {
    layout: 'padded',
  },
};

// Interactive examples
export const WithIcon: Story = {
  args: {
    children: (
      <>
        <svg
          className="w-4 h-4 mr-2"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M12 6v6m0 0v6m0-6h6m-6 0H6"
          />
        </svg>
        Add Item
      </>
    ),
    onClick: action('icon-button-click'),
  },
};

// Playground story for testing all combinations
export const Playground: Story = {
  args: {
    children: 'Playground Button',
    onClick: action('playground-click'),
  },
};

// Visual regression test story
export const VisualTest: Story = {
  render: () => (
    <div className="space-y-4">
      <div className="flex space-x-2">
        <Button variant="primary">Primary</Button>
        <Button variant="secondary">Secondary</Button>
        <Button variant="outline">Outline</Button>
        <Button variant="ghost">Ghost</Button>
        <Button variant="destructive">Destructive</Button>
      </div>
      <div className="flex space-x-2">
        <Button size="sm">Small</Button>
        <Button size="md">Medium</Button>
        <Button size="lg">Large</Button>
      </div>
      <div className="flex space-x-2">
        <Button disabled>Disabled</Button>
        <Button loading>Loading</Button>
      </div>
    </div>
  ),
  parameters: {
    chromatic: {
      viewports: [320, 768, 1200],
    },
  },
};

// Accessibility test story
export const AccessibilityTest: Story = {
  args: {
    children: 'Accessible Button',
    'aria-label': 'This is an accessible button',
    onClick: action('a11y-click'),
  },
  parameters: {
    a11y: {
      config: {
        rules: [
          {
            id: 'color-contrast',
            enabled: true,
          },
          {
            id: 'button-name',
            enabled: true,
          },
        ],
      },
    },
  },
};
