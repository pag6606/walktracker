import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    include: [
      'test/*.js',
      'test/**/*.js'
    ],
    exclude: [
      'node_modules/',
      'dist/',
      'e2e/',
      '_bmad-output/',
      '*.config.js'
    ],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: [
        '*.js',
        'test/*.js'
      ],
      exclude: [
        'node_modules/',
        'dist/',
        'e2e/',
        '_bmad-output/',
        '*.config.js',
        'test/index-tests.js',
        'e2e/*.js'
      ]
    },
    testTimeout: 10000,
    hookTimeout: 10000
  }
});