import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('error_rate');
const responseTime = new Trend('response_time');
const requestCount = new Counter('request_count');

// Test configuration
export const options = {
  stages: [
    // Ramp-up
    { duration: '2m', target: 10 },   // Ramp up to 10 users over 2 minutes
    { duration: '5m', target: 10 },   // Stay at 10 users for 5 minutes
    { duration: '2m', target: 20 },   // Ramp up to 20 users over 2 minutes
    { duration: '5m', target: 20 },   // Stay at 20 users for 5 minutes
    { duration: '2m', target: 50 },   // Ramp up to 50 users over 2 minutes
    { duration: '10m', target: 50 },  // Stay at 50 users for 10 minutes
    { duration: '5m', target: 0 },    // Ramp down to 0 users over 5 minutes
  ],
  
  thresholds: {
    // Performance budgets
    http_req_duration: ['p(95)<500', 'p(99)<1000'], // 95% under 500ms, 99% under 1s
    http_req_failed: ['rate<0.01'],                  // Error rate under 1%
    http_reqs: ['rate>10'],                          // Minimum 10 requests per second
    
    // Custom metrics thresholds
    error_rate: ['rate<0.01'],
    response_time: ['p(95)<500'],
  },
  
  // Environment-specific configuration
  ext: {
    loadimpact: {
      distribution: {
        'amazon:us:ashburn': { loadZone: 'amazon:us:ashburn', percent: 50 },
        'amazon:ie:dublin': { loadZone: 'amazon:ie:dublin', percent: 50 },
      },
    },
  },
};

// Base URL from environment variable
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

// Test data
const testUsers = [
  { username: 'testuser1', password: 'password123' },
  { username: 'testuser2', password: 'password123' },
  { username: 'testuser3', password: 'password123' },
];

// Authentication token storage
let authToken = '';

export function setup() {
  console.log(`Starting performance test against: ${BASE_URL}`);
  
  // Setup test data if needed
  const setupResponse = http.get(`${BASE_URL}/api/health`);
  check(setupResponse, {
    'setup - service is healthy': (r) => r.status === 200,
  });
  
  return { baseUrl: BASE_URL };
}

export default function (data) {
  group('Authentication Flow', () => {
    // Login test
    const loginPayload = JSON.stringify({
      username: testUsers[Math.floor(Math.random() * testUsers.length)].username,
      password: 'password123',
    });
    
    const loginParams = {
      headers: {
        'Content-Type': 'application/json',
      },
    };
    
    const loginResponse = http.post(`${BASE_URL}/api/auth/login`, loginPayload, loginParams);
    
    const loginSuccess = check(loginResponse, {
      'login - status is 200': (r) => r.status === 200,
      'login - response time < 500ms': (r) => r.timings.duration < 500,
      'login - has auth token': (r) => r.json('token') !== undefined,
    });
    
    if (loginSuccess) {
      authToken = loginResponse.json('token');
    }
    
    // Track metrics
    errorRate.add(!loginSuccess);
    responseTime.add(loginResponse.timings.duration);
    requestCount.add(1);
    
    sleep(1);
  });
  
  group('API Performance Tests', () => {
    const headers = {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json',
    };
    
    // Test critical API endpoints
    group('User Profile API', () => {
      const profileResponse = http.get(`${BASE_URL}/api/user/profile`, { headers });
      
      check(profileResponse, {
        'profile - status is 200': (r) => r.status === 200,
        'profile - response time < 300ms': (r) => r.timings.duration < 300,
        'profile - has user data': (r) => r.json('user') !== undefined,
      });
      
      errorRate.add(profileResponse.status !== 200);
      responseTime.add(profileResponse.timings.duration);
      requestCount.add(1);
    });
    
    group('Search API', () => {
      const searchResponse = http.get(`${BASE_URL}/api/search?q=test&limit=10`, { headers });
      
      check(searchResponse, {
        'search - status is 200': (r) => r.status === 200,
        'search - response time < 400ms': (r) => r.timings.duration < 400,
        'search - has results': (r) => r.json('results') !== undefined,
        'search - results count <= 10': (r) => r.json('results').length <= 10,
      });
      
      errorRate.add(searchResponse.status !== 200);
      responseTime.add(searchResponse.timings.duration);
      requestCount.add(1);
    });
    
    group('Dashboard API', () => {
      const dashboardResponse = http.get(`${BASE_URL}/api/dashboard`, { headers });
      
      check(dashboardResponse, {
        'dashboard - status is 200': (r) => r.status === 200,
        'dashboard - response time < 600ms': (r) => r.timings.duration < 600,
        'dashboard - has metrics': (r) => r.json('metrics') !== undefined,
      });
      
      errorRate.add(dashboardResponse.status !== 200);
      responseTime.add(dashboardResponse.timings.duration);
      requestCount.add(1);
    });
    
    sleep(Math.random() * 2 + 1); // Random sleep between 1-3 seconds
  });
  
  group('Business Critical Flows', () => {
    const headers = {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json',
    };
    
    // Simulate checkout process
    group('Checkout Flow', () => {
      // Add item to cart
      const addToCartPayload = JSON.stringify({
        productId: 'test-product-1',
        quantity: 1,
      });
      
      const addToCartResponse = http.post(`${BASE_URL}/api/cart/add`, addToCartPayload, { headers });
      
      check(addToCartResponse, {
        'add to cart - status is 200': (r) => r.status === 200,
        'add to cart - response time < 300ms': (r) => r.timings.duration < 300,
      });
      
      // Get cart contents
      const cartResponse = http.get(`${BASE_URL}/api/cart`, { headers });
      
      check(cartResponse, {
        'get cart - status is 200': (r) => r.status === 200,
        'get cart - response time < 200ms': (r) => r.timings.duration < 200,
        'get cart - has items': (r) => r.json('items').length > 0,
      });
      
      // Simulate checkout
      const checkoutPayload = JSON.stringify({
        paymentMethod: 'credit_card',
        shippingAddress: {
          street: '123 Test St',
          city: 'Test City',
          zipCode: '12345',
        },
      });
      
      const checkoutResponse = http.post(`${BASE_URL}/api/checkout`, checkoutPayload, { headers });
      
      const checkoutSuccess = check(checkoutResponse, {
        'checkout - status is 200': (r) => r.status === 200,
        'checkout - response time < 1000ms': (r) => r.timings.duration < 1000,
        'checkout - has order id': (r) => r.json('orderId') !== undefined,
      });
      
      // Track business metrics
      if (checkoutSuccess) {
        requestCount.add(1, { type: 'checkout_success' });
      } else {
        requestCount.add(1, { type: 'checkout_failure' });
      }
      
      errorRate.add(!checkoutSuccess);
      responseTime.add(checkoutResponse.timings.duration);
      requestCount.add(1);
    });
    
    sleep(2);
  });
  
  group('Static Assets Performance', () => {
    // Test static asset loading
    const staticAssets = [
      '/static/css/main.css',
      '/static/js/main.js',
      '/static/images/logo.png',
    ];
    
    staticAssets.forEach((asset) => {
      const assetResponse = http.get(`${BASE_URL}${asset}`);
      
      check(assetResponse, {
        [`${asset} - status is 200`]: (r) => r.status === 200,
        [`${asset} - response time < 200ms`]: (r) => r.timings.duration < 200,
        [`${asset} - has content`]: (r) => r.body.length > 0,
      });
      
      errorRate.add(assetResponse.status !== 200);
      responseTime.add(assetResponse.timings.duration);
      requestCount.add(1);
    });
  });
  
  // Feature flag testing
  group('Feature Flag Integration', () => {
    const headers = {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json',
    };
    
    const featureFlagsResponse = http.get(`${BASE_URL}/api/features`, { headers });
    
    check(featureFlagsResponse, {
      'feature flags - status is 200': (r) => r.status === 200,
      'feature flags - response time < 100ms': (r) => r.timings.duration < 100,
      'feature flags - has flags': (r) => r.json('flags') !== undefined,
    });
    
    errorRate.add(featureFlagsResponse.status !== 200);
    responseTime.add(featureFlagsResponse.timings.duration);
    requestCount.add(1);
  });
}

export function teardown(data) {
  console.log('Performance test completed');
  
  // Cleanup test data if needed
  const cleanupResponse = http.delete(`${BASE_URL}/api/test/cleanup`);
  check(cleanupResponse, {
    'cleanup - completed successfully': (r) => r.status === 200 || r.status === 404,
  });
}

// Handle different test scenarios
export function handleSummary(data) {
  const summary = {
    testStart: data.state.testRunDurationMs,
    metrics: {
      http_reqs: data.metrics.http_reqs.values.count,
      http_req_duration_p95: data.metrics.http_req_duration.values['p(95)'],
      http_req_duration_p99: data.metrics.http_req_duration.values['p(99)'],
      http_req_failed_rate: data.metrics.http_req_failed.values.rate,
      vus_max: data.metrics.vus_max.values.max,
    },
    thresholds: data.thresholds,
  };
  
  // Return different formats for different environments
  return {
    'performance-report.json': JSON.stringify(summary, null, 2),
    'performance-report.html': generateHTMLReport(summary),
    stdout: generateConsoleReport(summary),
  };
}

function generateHTMLReport(summary) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
        <title>Performance Test Report</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .metric { margin: 10px 0; padding: 10px; border-left: 4px solid #007cba; }
            .pass { border-left-color: #28a745; }
            .fail { border-left-color: #dc3545; }
        </style>
    </head>
    <body>
        <h1>Performance Test Report</h1>
        <div class="metric ${summary.metrics.http_req_duration_p95 < 500 ? 'pass' : 'fail'}">
            <strong>95th Percentile Response Time:</strong> ${summary.metrics.http_req_duration_p95.toFixed(2)}ms
        </div>
        <div class="metric ${summary.metrics.http_req_failed_rate < 0.01 ? 'pass' : 'fail'}">
            <strong>Error Rate:</strong> ${(summary.metrics.http_req_failed_rate * 100).toFixed(2)}%
        </div>
        <div class="metric">
            <strong>Total Requests:</strong> ${summary.metrics.http_reqs}
        </div>
        <div class="metric">
            <strong>Max Virtual Users:</strong> ${summary.metrics.vus_max}
        </div>
    </body>
    </html>
  `;
}

function generateConsoleReport(summary) {
  return `
Performance Test Summary:
========================
Total Requests: ${summary.metrics.http_reqs}
95th Percentile Response Time: ${summary.metrics.http_req_duration_p95.toFixed(2)}ms
99th Percentile Response Time: ${summary.metrics.http_req_duration_p99.toFixed(2)}ms
Error Rate: ${(summary.metrics.http_req_failed_rate * 100).toFixed(2)}%
Max Virtual Users: ${summary.metrics.vus_max}

Thresholds:
${Object.entries(summary.thresholds).map(([key, value]) => 
  `  ${key}: ${value.ok ? '✓ PASS' : '✗ FAIL'}`
).join('\n')}
  `;
}
