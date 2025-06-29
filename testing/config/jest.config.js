// Jest Configuration for Comprehensive Test Suite
// Enterprise-grade testing with coverage, performance, and quality metrics

const path = require('path');

module.exports = {
  // Test environment configuration
  testEnvironment: 'node',
  testEnvironmentOptions: {
    NODE_ENV: 'test',
  },

  // Root directories for tests
  roots: ['<rootDir>/src', '<rootDir>/tests'],

  // Test file patterns
  testMatch: [
    '**/__tests__/**/*.(js|jsx|ts|tsx)',
    '**/*.(test|spec).(js|jsx|ts|tsx)',
  ],

  // File extensions to consider
  moduleFileExtensions: ['js', 'jsx', 'ts', 'tsx', 'json', 'node'],

  // Transform configuration
  transform: {
    '^.+\\.(ts|tsx)$': 'ts-jest',
    '^.+\\.(js|jsx)$': 'babel-jest',
  },

  // Module name mapping for aliases
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@tests/(.*)$': '<rootDir>/tests/$1',
    '^@fixtures/(.*)$': '<rootDir>/tests/fixtures/$1',
    '^@mocks/(.*)$': '<rootDir>/tests/__mocks__/$1',
  },

  // Setup files
  setupFilesAfterEnv: [
    '<rootDir>/testing/config/jest.setup.js',
    '<rootDir>/testing/config/jest.matchers.js',
  ],

  // Coverage configuration
  collectCoverage: true,
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.{js,jsx,ts,tsx}',
    '!src/**/*.config.{js,jsx,ts,tsx}',
    '!src/**/index.{js,jsx,ts,tsx}',
    '!src/**/__tests__/**',
    '!src/**/__mocks__/**',
  ],

  // Coverage thresholds (>90% requirement)
  coverageThreshold: {
    global: {
      branches: 90,
      functions: 90,
      lines: 90,
      statements: 90,
    },
    // Per-file thresholds for critical components
    './src/services/': {
      branches: 95,
      functions: 95,
      lines: 95,
      statements: 95,
    },
    './src/utils/': {
      branches: 92,
      functions: 92,
      lines: 92,
      statements: 92,
    },
  },

  // Coverage reporters
  coverageReporters: [
    'text',
    'text-summary',
    'html',
    'lcov',
    'json',
    'json-summary',
    'cobertura',
    'clover',
  ],

  // Coverage directory
  coverageDirectory: '<rootDir>/coverage',

  // Test reporters
  reporters: [
    'default',
    [
      'jest-junit',
      {
        outputDirectory: '<rootDir>/test-results/jest',
        outputName: 'junit.xml',
        ancestorSeparator: ' › ',
        uniqueOutputName: 'false',
        suiteNameTemplate: '{filepath}',
        classNameTemplate: '{classname}',
        titleTemplate: '{title}',
      },
    ],
    [
      'jest-html-reporters',
      {
        publicPath: '<rootDir>/test-results/html',
        filename: 'jest-report.html',
        expand: true,
        hideIcon: false,
        pageTitle: 'Nexus V3 Test Report',
      },
    ],
    [
      'jest-sonar-reporter',
      {
        outputDirectory: '<rootDir>/test-results/sonar',
        outputName: 'test-report.xml',
      },
    ],
  ],

  // Global test timeout
  testTimeout: 30000,

  // Verbose output
  verbose: true,

  // Detect open handles
  detectOpenHandles: true,

  // Force exit after tests complete
  forceExit: true,

  // Clear mocks between tests
  clearMocks: true,

  // Restore mocks after each test
  restoreMocks: true,

  // Reset modules between tests
  resetModules: true,

  // Error on deprecated features
  errorOnDeprecated: true,

  // Notify mode for watch
  notify: true,
  notifyMode: 'failure-change',

  // Watch plugins
  watchPlugins: [
    'jest-watch-typeahead/filename',
    'jest-watch-typeahead/testname',
    'jest-watch-select-projects',
  ],

  // Projects for different test types
  projects: [
    {
      displayName: 'unit',
      testMatch: ['<rootDir>/tests/unit/**/*.(test|spec).(js|jsx|ts|tsx)'],
      testEnvironment: 'node',
    },
    {
      displayName: 'integration',
      testMatch: ['<rootDir>/tests/integration/**/*.(test|spec).(js|jsx|ts|tsx)'],
      testEnvironment: 'node',
      setupFilesAfterEnv: ['<rootDir>/testing/config/integration.setup.js'],
    },
    {
      displayName: 'contract',
      testMatch: ['<rootDir>/tests/contract/**/*.(test|spec).(js|jsx|ts|tsx)'],
      testEnvironment: 'node',
      setupFilesAfterEnv: ['<rootDir>/testing/config/contract.setup.js'],
    },
  ],

  // Global variables
  globals: {
    'ts-jest': {
      tsconfig: '<rootDir>/tsconfig.test.json',
      isolatedModules: true,
    },
    __DEV__: true,
    __TEST__: true,
    __PROD__: false,
  },

  // Module directories
  moduleDirectories: ['node_modules', '<rootDir>/src', '<rootDir>/tests'],

  // Ignore patterns
  testPathIgnorePatterns: [
    '<rootDir>/node_modules/',
    '<rootDir>/dist/',
    '<rootDir>/build/',
    '<rootDir>/coverage/',
  ],

  // Transform ignore patterns
  transformIgnorePatterns: [
    'node_modules/(?!(.*\\.mjs$|@testing-library|@babel))',
  ],

  // Snapshot serializers
  snapshotSerializers: [
    'enzyme-to-json/serializer',
    'jest-serializer-html',
  ],

  // Max workers for parallel execution
  maxWorkers: '50%',

  // Cache directory
  cacheDirectory: '<rootDir>/node_modules/.cache/jest',

  // Bail on first test failure (for CI)
  bail: process.env.CI ? 1 : 0,

  // Silent mode for CI
  silent: process.env.CI === 'true',

  // Custom matchers and utilities
  setupFiles: [
    '<rootDir>/testing/config/polyfills.js',
    '<rootDir>/testing/config/env.js',
  ],
};
