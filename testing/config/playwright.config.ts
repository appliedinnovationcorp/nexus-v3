import { defineConfig, devices } from '@playwright/test';
import path from 'path';

/**
 * Playwright Configuration for End-to-End Testing
 * Enterprise-grade E2E testing with cross-browser support, visual regression, and accessibility testing
 */
export default defineConfig({
  // Test directory
  testDir: path.join(__dirname, '../e2e'),

  // Global test timeout
  timeout: 60000,

  // Expect timeout for assertions
  expect: {
    timeout: 10000,
    // Visual comparison threshold
    threshold: 0.2,
    // Animation handling
    toHaveScreenshot: {
      mode: 'css',
      animations: 'disabled',
    },
    toMatchSnapshot: {
      threshold: 0.2,
      maxDiffPixels: 1000,
    },
  },

  // Test execution configuration
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,

  // Reporting configuration
  reporter: [
    ['html', { 
      outputFolder: 'test-results/playwright-report',
      open: 'never',
    }],
    ['junit', { 
      outputFile: 'test-results/playwright/junit.xml',
    }],
    ['json', { 
      outputFile: 'test-results/playwright/results.json',
    }],
    ['allure-playwright', {
      detail: true,
      outputFolder: 'test-results/allure-results',
      suiteTitle: false,
    }],
    // Custom reporter for CI/CD integration
    ['./testing/reporters/playwright-custom-reporter.ts'],
  ],

  // Global setup and teardown
  globalSetup: path.join(__dirname, '../setup/global-setup.ts'),
  globalTeardown: path.join(__dirname, '../setup/global-teardown.ts'),

  // Test output directory
  outputDir: 'test-results/playwright-artifacts',

  // Use configuration
  use: {
    // Base URL for tests
    baseURL: process.env.BASE_URL || 'http://localhost:3000',

    // Browser context options
    viewport: { width: 1280, height: 720 },
    ignoreHTTPSErrors: true,
    
    // Screenshots and videos
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    trace: 'retain-on-failure',

    // Timeouts
    actionTimeout: 15000,
    navigationTimeout: 30000,

    // Locale and timezone
    locale: 'en-US',
    timezoneId: 'America/New_York',

    // Permissions
    permissions: ['notifications', 'geolocation'],

    // Color scheme
    colorScheme: 'light',

    // Reduced motion for consistent testing
    reducedMotion: 'reduce',

    // Extra HTTP headers
    extraHTTPHeaders: {
      'Accept-Language': 'en-US,en;q=0.9',
    },
  },

  // Project configurations for different browsers and test types
  projects: [
    // Setup project for authentication
    {
      name: 'setup',
      testMatch: /.*\.setup\.ts/,
      teardown: 'cleanup',
    },
    {
      name: 'cleanup',
      testMatch: /.*\.teardown\.ts/,
    },

    // Desktop browsers
    {
      name: 'chromium',
      use: { 
        ...devices['Desktop Chrome'],
        // Enable Chrome DevTools Protocol for performance testing
        launchOptions: {
          args: ['--enable-automation', '--disable-background-timer-throttling'],
        },
      },
      dependencies: ['setup'],
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
      dependencies: ['setup'],
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
      dependencies: ['setup'],
    },

    // Mobile browsers
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
      dependencies: ['setup'],
    },
    {
      name: 'mobile-safari',
      use: { ...devices['iPhone 12'] },
      dependencies: ['setup'],
    },

    // Tablet browsers
    {
      name: 'tablet',
      use: { ...devices['iPad Pro'] },
      dependencies: ['setup'],
    },

    // Accessibility testing
    {
      name: 'accessibility',
      testMatch: /.*\.a11y\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        // Enable accessibility tree
        launchOptions: {
          args: ['--force-renderer-accessibility'],
        },
      },
      dependencies: ['setup'],
    },

    // Visual regression testing
    {
      name: 'visual-regression',
      testMatch: /.*\.visual\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        // Consistent rendering for visual tests
        launchOptions: {
          args: [
            '--disable-web-security',
            '--disable-features=TranslateUI',
            '--disable-ipc-flooding-protection',
          ],
        },
      },
      dependencies: ['setup'],
    },

    // Performance testing
    {
      name: 'performance',
      testMatch: /.*\.perf\.spec\.ts/,
      use: {
        ...devices['Desktop Chrome'],
        // Performance monitoring
        launchOptions: {
          args: ['--enable-automation', '--no-sandbox'],
        },
      },
      dependencies: ['setup'],
    },

    // API testing
    {
      name: 'api',
      testMatch: /.*\.api\.spec\.ts/,
      use: {
        // No browser needed for API tests
        baseURL: process.env.API_BASE_URL || 'http://localhost:3000/api',
      },
    },
  ],

  // Web server configuration
  webServer: process.env.CI ? undefined : {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
    env: {
      NODE_ENV: 'test',
    },
  },

  // Metadata
  metadata: {
    'test-suite': 'nexus-v3-e2e',
    'environment': process.env.NODE_ENV || 'test',
    'version': process.env.npm_package_version || '1.0.0',
  },
});
