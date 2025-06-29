#!/bin/bash

set -e

# APM Integration Script
# Helps integrate APM agents into applications

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[APM]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[APM INTEGRATION]${NC} $1"
}

# Generate APM configuration for different languages
generate_apm_config() {
    local language=$1
    local service_name=$2
    local service_version=${3:-"1.0.0"}
    
    print_header "Generating APM configuration for $language"
    
    case $language in
        "nodejs"|"javascript")
            generate_nodejs_apm_config "$service_name" "$service_version"
            ;;
        "python")
            generate_python_apm_config "$service_name" "$service_version"
            ;;
        "java")
            generate_java_apm_config "$service_name" "$service_version"
            ;;
        "dotnet"|"csharp")
            generate_dotnet_apm_config "$service_name" "$service_version"
            ;;
        "go"|"golang")
            generate_go_apm_config "$service_name" "$service_version"
            ;;
        "rum"|"browser")
            generate_rum_config "$service_name" "$service_version"
            ;;
        *)
            print_error "Unsupported language: $language"
            return 1
            ;;
    esac
}

generate_nodejs_apm_config() {
    local service_name=$1
    local service_version=$2
    
    print_status "Generating Node.js APM configuration..."
    
    # Create APM configuration file
    cat > "apm-${service_name}.js" << EOF
// Elastic APM Node.js Agent Configuration
// Add this as the FIRST import in your main application file

const apm = require('elastic-apm-node').start({
  // Service configuration
  serviceName: '${service_name}',
  serviceVersion: '${service_version}',
  environment: process.env.NODE_ENV || 'development',
  
  // APM Server configuration
  serverUrl: process.env.ELASTIC_APM_SERVER_URL || 'http://localhost:8200',
  secretToken: process.env.ELASTIC_APM_SECRET_TOKEN,
  
  // Performance configuration
  captureBody: 'all',
  captureHeaders: true,
  captureErrorLogStackTraces: 'always',
  
  // Sampling configuration
  transactionSampleRate: 1.0,
  
  // Custom configuration
  logLevel: 'info',
  active: true,
  
  // Framework-specific configuration
  frameworkName: 'express', // or 'koa', 'hapi', etc.
  
  // Distributed tracing
  usePathAsTransactionName: true,
  
  // Custom tags
  globalLabels: {
    cluster: 'nexus-v3',
    datacenter: 'local'
  }
});

module.exports = apm;
EOF

    # Create package.json dependencies
    cat > "apm-dependencies.json" << EOF
{
  "dependencies": {
    "elastic-apm-node": "^3.49.1"
  }
}
EOF

    # Create Docker environment variables
    cat > "apm-docker.env" << EOF
# Elastic APM Environment Variables
ELASTIC_APM_SERVICE_NAME=${service_name}
ELASTIC_APM_SERVICE_VERSION=${service_version}
ELASTIC_APM_SERVER_URL=http://apm-server:8200
ELASTIC_APM_ENVIRONMENT=development
ELASTIC_APM_ACTIVE=true
ELASTIC_APM_CAPTURE_BODY=all
ELASTIC_APM_CAPTURE_HEADERS=true
ELASTIC_APM_LOG_LEVEL=info
EOF

    print_status "Node.js APM configuration generated ✅"
    print_status "Files created: apm-${service_name}.js, apm-dependencies.json, apm-docker.env"
}

generate_python_apm_config() {
    local service_name=$1
    local service_version=$2
    
    print_status "Generating Python APM configuration..."
    
    # Create APM configuration file
    cat > "apm_${service_name}.py" << EOF
# Elastic APM Python Agent Configuration
import os
from elasticapm.contrib.django.middleware import ElasticAPMMiddleware
from elasticapm.contrib.flask import ElasticAPM

# APM Configuration
APM_CONFIG = {
    'SERVICE_NAME': '${service_name}',
    'SERVICE_VERSION': '${service_version}',
    'ENVIRONMENT': os.getenv('ENVIRONMENT', 'development'),
    'SERVER_URL': os.getenv('ELASTIC_APM_SERVER_URL', 'http://localhost:8200'),
    'SECRET_TOKEN': os.getenv('ELASTIC_APM_SECRET_TOKEN'),
    'CAPTURE_BODY': 'all',
    'CAPTURE_HEADERS': True,
    'TRANSACTION_SAMPLE_RATE': 1.0,
    'DEBUG': True,
    'LOG_LEVEL': 'info',
    'GLOBAL_LABELS': {
        'cluster': 'nexus-v3',
        'datacenter': 'local'
    }
}

# Django Integration
def setup_django_apm(app):
    app.config['ELASTIC_APM'] = APM_CONFIG
    ElasticAPMMiddleware(app)
    return app

# Flask Integration
def setup_flask_apm(app):
    app.config['ELASTIC_APM'] = APM_CONFIG
    apm = ElasticAPM(app)
    return app, apm

# FastAPI Integration
def setup_fastapi_apm():
    from elasticapm.contrib.starlette import ElasticAPMMiddleware
    return ElasticAPMMiddleware, APM_CONFIG
EOF

    # Create requirements.txt
    cat > "apm-requirements.txt" << EOF
elastic-apm[flask]==6.18.1
# For Django: elastic-apm[django]==6.18.1
# For FastAPI: elastic-apm[starlette]==6.18.1
EOF

    print_status "Python APM configuration generated ✅"
    print_status "Files created: apm_${service_name}.py, apm-requirements.txt"
}

generate_rum_config() {
    local service_name=$1
    local service_version=$2
    
    print_status "Generating RUM (Browser) configuration..."
    
    # Create RUM configuration
    cat > "rum-${service_name}.js" << EOF
// Elastic APM Real User Monitoring (RUM) Configuration
import { init as initApm } from '@elastic/apm-rum'

const apm = initApm({
  // Service configuration
  serviceName: '${service_name}-frontend',
  serviceVersion: '${service_version}',
  environment: process.env.NODE_ENV || 'development',
  
  // APM Server configuration
  serverUrl: process.env.REACT_APP_APM_SERVER_URL || 'http://localhost:8200',
  
  // Performance configuration
  active: true,
  instrument: true,
  disableInstrumentations: [],
  
  // Page load configuration
  pageLoadTraceId: true,
  pageLoadSampled: true,
  pageLoadSpanId: true,
  
  // Transaction configuration
  transactionSampleRate: 1.0,
  
  // Error configuration
  capturePageLoadSpanId: true,
  
  // Custom configuration
  logLevel: 'warn',
  
  // Distributed tracing
  distributedTracingOrigins: [
    'http://localhost:3000',
    'http://localhost:8000',
    /https?:\\/\\/.*\\.nexus-v3\\.local.*/
  ],
  
  // Custom tags
  globalLabels: {
    cluster: 'nexus-v3',
    platform: 'web'
  },
  
  // User context
  context: {
    tags: {
      application: '${service_name}'
    }
  }
});

// Custom transaction tracking
export const trackCustomTransaction = (name, type = 'custom') => {
  const transaction = apm.startTransaction(name, type);
  return transaction;
};

// Custom error tracking
export const trackError = (error, context = {}) => {
  apm.captureError(error, context);
};

// Custom span tracking
export const trackSpan = (name, type = 'custom', fn) => {
  const span = apm.startSpan(name, type);
  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(() => span && span.end());
    }
    return result;
  } catch (error) {
    if (span) span.end();
    throw error;
  }
};

export default apm;
EOF

    # Create HTML integration example
    cat > "rum-html-example.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${service_name} - RUM Integration</title>
    <!-- Elastic APM RUM Agent -->
    <script src="https://unpkg.com/@elastic/apm-rum@5.12.1/dist/bundles/elastic-apm-rum.umd.min.js"></script>
    <script>
        elasticApm.init({
            serviceName: '${service_name}-frontend',
            serviceVersion: '${service_version}',
            serverUrl: 'http://localhost:8200',
            environment: 'development',
            active: true,
            transactionSampleRate: 1.0,
            distributedTracingOrigins: ['http://localhost:3000'],
            globalLabels: {
                cluster: 'nexus-v3',
                platform: 'web'
            }
        });
    </script>
</head>
<body>
    <h1>${service_name} Application</h1>
    <p>RUM monitoring is now active!</p>
    
    <script>
        // Custom transaction example
        const transaction = elasticApm.startTransaction('page-interaction', 'user-interaction');
        
        // Simulate some work
        setTimeout(() => {
            transaction.end();
        }, 1000);
        
        // Custom error tracking
        window.addEventListener('error', (event) => {
            elasticApm.captureError(event.error);
        });
    </script>
</body>
</html>
EOF

    # Create package.json for npm
    cat > "rum-package.json" << EOF
{
  "dependencies": {
    "@elastic/apm-rum": "^5.12.1",
    "@elastic/apm-rum-react": "^2.0.1"
  }
}
EOF

    print_status "RUM configuration generated ✅"
    print_status "Files created: rum-${service_name}.js, rum-html-example.html, rum-package.json"
}

generate_java_apm_config() {
    local service_name=$1
    local service_version=$2
    
    print_status "Generating Java APM configuration..."
    
    # Create application.properties
    cat > "application-apm.properties" << EOF
# Elastic APM Java Agent Configuration
elastic.apm.service_name=${service_name}
elastic.apm.service_version=${service_version}
elastic.apm.environment=development
elastic.apm.server_urls=http://localhost:8200
elastic.apm.application_packages=com.nexusv3
elastic.apm.capture_body=all
elastic.apm.capture_headers=true
elastic.apm.transaction_sample_rate=1.0
elastic.apm.log_level=INFO
elastic.apm.active=true
elastic.apm.global_labels=cluster=nexus-v3,datacenter=local
EOF

    # Create Docker run command
    cat > "java-apm-docker.sh" << EOF
#!/bin/bash
# Java APM Docker Integration

# Download APM agent
curl -L -O https://github.com/elastic/apm-agent-java/releases/latest/download/elastic-apm-agent.jar

# Run with APM agent
java -javaagent:elastic-apm-agent.jar \\
     -Delastic.apm.service_name=${service_name} \\
     -Delastic.apm.service_version=${service_version} \\
     -Delastic.apm.server_urls=http://localhost:8200 \\
     -Delastic.apm.environment=development \\
     -Delastic.apm.application_packages=com.nexusv3 \\
     -jar your-application.jar
EOF

    chmod +x "java-apm-docker.sh"

    print_status "Java APM configuration generated ✅"
    print_status "Files created: application-apm.properties, java-apm-docker.sh"
}

# Generate OpenTelemetry configuration
generate_otel_config() {
    local service_name=$1
    local language=$2
    
    print_header "Generating OpenTelemetry configuration for $service_name ($language)"
    
    case $language in
        "nodejs")
            generate_otel_nodejs "$service_name"
            ;;
        "python")
            generate_otel_python "$service_name"
            ;;
        *)
            print_warning "OpenTelemetry configuration for $language not implemented yet"
            ;;
    esac
}

generate_otel_nodejs() {
    local service_name=$1
    
    cat > "otel-${service_name}.js" << EOF
// OpenTelemetry Node.js Configuration
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-otlp-http');

// Configure resource
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: '${service_name}',
  [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: 'development',
});

// Configure exporters
const jaegerExporter = new JaegerExporter({
  endpoint: 'http://localhost:14268/api/traces',
});

const otlpExporter = new OTLPTraceExporter({
  url: 'http://localhost:4318/v1/traces',
});

// Initialize SDK
const sdk = new NodeSDK({
  resource,
  traceExporter: otlpExporter,
  instrumentations: [getNodeAutoInstrumentations()],
});

// Start SDK
sdk.start();

console.log('OpenTelemetry started successfully');

module.exports = sdk;
EOF

    cat > "otel-dependencies.json" << EOF
{
  "dependencies": {
    "@opentelemetry/sdk-node": "^0.45.0",
    "@opentelemetry/auto-instrumentations-node": "^0.40.0",
    "@opentelemetry/exporter-jaeger": "^1.17.0",
    "@opentelemetry/exporter-otlp-http": "^0.45.0"
  }
}
EOF

    print_status "OpenTelemetry Node.js configuration generated ✅"
}

# Main function
main() {
    case $1 in
        "generate")
            generate_apm_config "$2" "$3" "$4"
            ;;
        "otel")
            generate_otel_config "$2" "$3"
            ;;
        *)
            echo "APM Integration Helper"
            echo ""
            echo "Usage:"
            echo "  $0 generate <language> <service_name> [service_version]"
            echo "  $0 otel <service_name> <language>"
            echo ""
            echo "Supported languages:"
            echo "  • nodejs/javascript - Node.js applications"
            echo "  • python - Python applications (Django/Flask/FastAPI)"
            echo "  • java - Java applications"
            echo "  • dotnet/csharp - .NET applications"
            echo "  • go/golang - Go applications"
            echo "  • rum/browser - Browser/Frontend applications"
            echo ""
            echo "Examples:"
            echo "  $0 generate nodejs user-service 1.2.0"
            echo "  $0 generate python api-gateway 2.1.0"
            echo "  $0 generate rum frontend-app 1.0.0"
            echo "  $0 otel user-service nodejs"
            ;;
    esac
}

main "$@"
