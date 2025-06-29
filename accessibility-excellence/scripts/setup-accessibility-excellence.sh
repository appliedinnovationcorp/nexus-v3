#!/bin/bash

# Enterprise Accessibility Excellence System Setup Script
# Implements comprehensive WCAG 2.1 AA compliance and accessibility testing

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root for security reasons"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check Node.js (for local development)
    if ! command -v node &> /dev/null; then
        warn "Node.js is not installed. Some features may be limited."
    fi
    
    # Check available disk space (minimum 15GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=15728640  # 15GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error "Insufficient disk space. At least 15GB required."
        exit 1
    fi
    
    # Check available memory (minimum 8GB)
    available_memory=$(free -k | awk 'NR==2{print $2}')
    required_memory=8388608  # 8GB in KB
    
    if [[ $available_memory -lt $required_memory ]]; then
        warn "Less than 8GB RAM available. Performance may be impacted."
    fi
    
    log "System requirements check completed successfully"
}

# Create directory structure
create_directories() {
    log "Creating directory structure..."
    
    local dirs=(
        "config"
        "scripts"
        "docker/pa11y-service"
        "docker/axe-service"
        "docker/wave-service"
        "docker/lighthouse-accessibility"
        "docker/contrast-analyzer"
        "docker/screen-reader-service"
        "docker/keyboard-nav-service"
        "docker/accessibility-orchestrator"
        "docker/accessibility-dashboard"
        "docker/wcag-compliance"
        "testing/automated"
        "testing/manual"
        "auditing/reports"
        "auditing/templates"
        "monitoring/dashboards"
        "monitoring/alerts"
        "components/accessible"
        "components/patterns"
        "utils/helpers"
        "utils/validators"
        "reports/pa11y"
        "reports/axe"
        "reports/wave"
        "reports/lighthouse"
        "reports/contrast"
        "reports/screen-reader"
        "reports/keyboard-nav"
        "reports/wcag"
        "training/materials"
        "training/guidelines"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        info "Created directory: $dir"
    done
    
    log "Directory structure created successfully"
}

# Generate configuration files
generate_configs() {
    log "Generating configuration files..."
    
    # Pa11y Configuration
    cat > config/pa11y-config.json << 'EOF'
{
  "standard": "WCAG2AA",
  "timeout": 30000,
  "wait": 2000,
  "chromeLaunchConfig": {
    "ignoreHTTPSErrors": true,
    "args": [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu"
    ]
  },
  "rules": [
    "color-contrast",
    "document-title",
    "duplicate-id",
    "empty-heading",
    "heading-order",
    "html-has-lang",
    "html-lang-valid",
    "image-alt",
    "input-image-alt",
    "label",
    "landmark-banner-is-top-level",
    "landmark-complementary-is-top-level",
    "landmark-contentinfo-is-top-level",
    "landmark-main-is-top-level",
    "landmark-no-duplicate-banner",
    "landmark-no-duplicate-contentinfo",
    "landmark-one-main",
    "link-name",
    "list",
    "listitem",
    "meta-refresh",
    "meta-viewport",
    "page-has-heading-one",
    "region",
    "skip-link",
    "tabindex"
  ],
  "ignore": [
    "notice",
    "warning"
  ],
  "includeNotices": false,
  "includeWarnings": false,
  "reporter": "json",
  "level": "error"
}
EOF
    
    # Axe Configuration
    cat > config/axe-config.json << 'EOF'
{
  "rules": {
    "color-contrast": { "enabled": true },
    "document-title": { "enabled": true },
    "duplicate-id": { "enabled": true },
    "empty-heading": { "enabled": true },
    "heading-order": { "enabled": true },
    "html-has-lang": { "enabled": true },
    "html-lang-valid": { "enabled": true },
    "image-alt": { "enabled": true },
    "input-image-alt": { "enabled": true },
    "label": { "enabled": true },
    "landmark-banner-is-top-level": { "enabled": true },
    "landmark-complementary-is-top-level": { "enabled": true },
    "landmark-contentinfo-is-top-level": { "enabled": true },
    "landmark-main-is-top-level": { "enabled": true },
    "landmark-no-duplicate-banner": { "enabled": true },
    "landmark-no-duplicate-contentinfo": { "enabled": true },
    "landmark-one-main": { "enabled": true },
    "link-name": { "enabled": true },
    "list": { "enabled": true },
    "listitem": { "enabled": true },
    "meta-refresh": { "enabled": true },
    "meta-viewport": { "enabled": true },
    "page-has-heading-one": { "enabled": true },
    "region": { "enabled": true },
    "skip-link": { "enabled": true },
    "tabindex": { "enabled": true },
    "focus-order-semantics": { "enabled": true },
    "keyboard-navigation": { "enabled": true },
    "aria-allowed-attr": { "enabled": true },
    "aria-allowed-role": { "enabled": true },
    "aria-hidden-body": { "enabled": true },
    "aria-hidden-focus": { "enabled": true },
    "aria-input-field-name": { "enabled": true },
    "aria-label": { "enabled": true },
    "aria-labelledby": { "enabled": true },
    "aria-required-attr": { "enabled": true },
    "aria-required-children": { "enabled": true },
    "aria-required-parent": { "enabled": true },
    "aria-roles": { "enabled": true },
    "aria-valid-attr": { "enabled": true },
    "aria-valid-attr-value": { "enabled": true }
  },
  "tags": ["wcag2a", "wcag2aa", "wcag21aa"],
  "reporter": "v2",
  "resultTypes": ["violations", "incomplete", "passes"],
  "runOnly": {
    "type": "tag",
    "values": ["wcag2a", "wcag2aa", "wcag21aa"]
  }
}
EOF
    
    # WCAG Compliance Configuration
    cat > config/wcag-config.json << 'EOF'
{
  "version": "2.1",
  "level": "AA",
  "guidelines": {
    "1.1.1": {
      "name": "Non-text Content",
      "level": "A",
      "description": "All non-text content has a text alternative"
    },
    "1.2.1": {
      "name": "Audio-only and Video-only (Prerecorded)",
      "level": "A",
      "description": "Alternative for time-based media"
    },
    "1.2.2": {
      "name": "Captions (Prerecorded)",
      "level": "A",
      "description": "Captions for prerecorded audio content"
    },
    "1.2.3": {
      "name": "Audio Description or Media Alternative (Prerecorded)",
      "level": "A",
      "description": "Audio description or full text alternative"
    },
    "1.2.4": {
      "name": "Captions (Live)",
      "level": "AA",
      "description": "Captions for live audio content"
    },
    "1.2.5": {
      "name": "Audio Description (Prerecorded)",
      "level": "AA",
      "description": "Audio description for prerecorded video"
    },
    "1.3.1": {
      "name": "Info and Relationships",
      "level": "A",
      "description": "Information and relationships conveyed through presentation can be programmatically determined"
    },
    "1.3.2": {
      "name": "Meaningful Sequence",
      "level": "A",
      "description": "Content can be presented in a meaningful sequence"
    },
    "1.3.3": {
      "name": "Sensory Characteristics",
      "level": "A",
      "description": "Instructions don't rely solely on sensory characteristics"
    },
    "1.3.4": {
      "name": "Orientation",
      "level": "AA",
      "description": "Content doesn't restrict its view to a single display orientation"
    },
    "1.3.5": {
      "name": "Identify Input Purpose",
      "level": "AA",
      "description": "Input purpose can be programmatically determined"
    },
    "1.4.1": {
      "name": "Use of Color",
      "level": "A",
      "description": "Color is not the only means of conveying information"
    },
    "1.4.2": {
      "name": "Audio Control",
      "level": "A",
      "description": "Audio that plays automatically can be paused or stopped"
    },
    "1.4.3": {
      "name": "Contrast (Minimum)",
      "level": "AA",
      "description": "Text has a contrast ratio of at least 4.5:1"
    },
    "1.4.4": {
      "name": "Resize text",
      "level": "AA",
      "description": "Text can be resized up to 200% without loss of functionality"
    },
    "1.4.5": {
      "name": "Images of Text",
      "level": "AA",
      "description": "Images of text are avoided where possible"
    },
    "1.4.10": {
      "name": "Reflow",
      "level": "AA",
      "description": "Content can be presented without horizontal scrolling"
    },
    "1.4.11": {
      "name": "Non-text Contrast",
      "level": "AA",
      "description": "UI components have sufficient contrast"
    },
    "1.4.12": {
      "name": "Text Spacing",
      "level": "AA",
      "description": "Text spacing can be adjusted without loss of functionality"
    },
    "1.4.13": {
      "name": "Content on Hover or Focus",
      "level": "AA",
      "description": "Additional content triggered by hover or focus is dismissible"
    },
    "2.1.1": {
      "name": "Keyboard",
      "level": "A",
      "description": "All functionality is available from a keyboard"
    },
    "2.1.2": {
      "name": "No Keyboard Trap",
      "level": "A",
      "description": "Keyboard focus is not trapped"
    },
    "2.1.4": {
      "name": "Character Key Shortcuts",
      "level": "A",
      "description": "Character key shortcuts can be turned off or remapped"
    },
    "2.2.1": {
      "name": "Timing Adjustable",
      "level": "A",
      "description": "Time limits can be turned off, adjusted, or extended"
    },
    "2.2.2": {
      "name": "Pause, Stop, Hide",
      "level": "A",
      "description": "Moving, blinking, or auto-updating content can be paused"
    },
    "2.3.1": {
      "name": "Three Flashes or Below Threshold",
      "level": "A",
      "description": "Content doesn't flash more than three times per second"
    },
    "2.4.1": {
      "name": "Bypass Blocks",
      "level": "A",
      "description": "Skip links or other mechanisms to bypass blocks of content"
    },
    "2.4.2": {
      "name": "Page Titled",
      "level": "A",
      "description": "Web pages have descriptive titles"
    },
    "2.4.3": {
      "name": "Focus Order",
      "level": "A",
      "description": "Focus order is logical and intuitive"
    },
    "2.4.4": {
      "name": "Link Purpose (In Context)",
      "level": "A",
      "description": "Link purpose can be determined from link text or context"
    },
    "2.4.5": {
      "name": "Multiple Ways",
      "level": "AA",
      "description": "Multiple ways to locate a web page"
    },
    "2.4.6": {
      "name": "Headings and Labels",
      "level": "AA",
      "description": "Headings and labels describe topic or purpose"
    },
    "2.4.7": {
      "name": "Focus Visible",
      "level": "AA",
      "description": "Keyboard focus indicator is visible"
    },
    "2.5.1": {
      "name": "Pointer Gestures",
      "level": "A",
      "description": "Multipoint or path-based gestures have single-point alternatives"
    },
    "2.5.2": {
      "name": "Pointer Cancellation",
      "level": "A",
      "description": "Functions triggered by single-point activation can be cancelled"
    },
    "2.5.3": {
      "name": "Label in Name",
      "level": "A",
      "description": "Accessible name contains the visible label text"
    },
    "2.5.4": {
      "name": "Motion Actuation",
      "level": "A",
      "description": "Motion-based functionality can be disabled"
    },
    "3.1.1": {
      "name": "Language of Page",
      "level": "A",
      "description": "Default language of web page is programmatically determined"
    },
    "3.1.2": {
      "name": "Language of Parts",
      "level": "AA",
      "description": "Language of parts is programmatically determined"
    },
    "3.2.1": {
      "name": "On Focus",
      "level": "A",
      "description": "Focus doesn't trigger unexpected context changes"
    },
    "3.2.2": {
      "name": "On Input",
      "level": "A",
      "description": "Input doesn't trigger unexpected context changes"
    },
    "3.2.3": {
      "name": "Consistent Navigation",
      "level": "AA",
      "description": "Navigation is consistent across pages"
    },
    "3.2.4": {
      "name": "Consistent Identification",
      "level": "AA",
      "description": "Components with same functionality are identified consistently"
    },
    "3.3.1": {
      "name": "Error Identification",
      "level": "A",
      "description": "Input errors are identified and described"
    },
    "3.3.2": {
      "name": "Labels or Instructions",
      "level": "A",
      "description": "Labels or instructions are provided for user input"
    },
    "3.3.3": {
      "name": "Error Suggestion",
      "level": "AA",
      "description": "Error suggestions are provided when possible"
    },
    "3.3.4": {
      "name": "Error Prevention (Legal, Financial, Data)",
      "level": "AA",
      "description": "Error prevention for important transactions"
    },
    "4.1.1": {
      "name": "Parsing",
      "level": "A",
      "description": "Markup is valid and properly nested"
    },
    "4.1.2": {
      "name": "Name, Role, Value",
      "level": "A",
      "description": "Name, role, and value can be programmatically determined"
    },
    "4.1.3": {
      "name": "Status Messages",
      "level": "AA",
      "description": "Status messages can be programmatically determined"
    }
  }
}
EOF
    
    log "Configuration files generated successfully"
}

# Create Docker service files
create_docker_services() {
    log "Creating Docker service files..."
    
    # Pa11y Service Dockerfile
    cat > docker/pa11y-service/Dockerfile << 'EOF'
FROM node:18-alpine

# Install Chrome dependencies
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont

# Set Chrome path
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nextjs -u 1001

# Set ownership
RUN chown -R nextjs:nodejs /app
USER nextjs

EXPOSE 4000

CMD ["node", "server.js"]
EOF
    
    # Pa11y Service Package.json
    cat > docker/pa11y-service/package.json << 'EOF'
{
  "name": "pa11y-service",
  "version": "1.0.0",
  "description": "Enterprise Pa11y Accessibility Testing Service",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "pa11y": "^7.0.0",
    "puppeteer": "^21.6.1",
    "redis": "^4.6.10",
    "mongodb": "^6.3.0",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "compression": "^1.7.4",
    "prom-client": "^15.1.0",
    "winston": "^3.11.0",
    "uuid": "^9.0.1",
    "node-cron": "^3.0.3"
  }
}
EOF
    
    log "Docker service files created successfully"
}

# Initialize services
initialize_services() {
    log "Initializing Accessibility Excellence services..."
    
    # Pull required Docker images
    docker-compose -f docker-compose.accessibility-excellence.yml pull
    
    # Build custom services
    docker-compose -f docker-compose.accessibility-excellence.yml build
    
    log "Services initialized successfully"
}

# Start services
start_services() {
    log "Starting Accessibility Excellence services..."
    
    # Start infrastructure services first
    docker-compose -f docker-compose.accessibility-excellence.yml up -d redis-accessibility mongodb-accessibility
    
    # Wait for infrastructure to be ready
    sleep 15
    
    # Start application services
    docker-compose -f docker-compose.accessibility-excellence.yml up -d
    
    # Wait for services to be ready
    sleep 30
    
    log "All services started successfully"
}

# Verify installation
verify_installation() {
    log "Verifying Accessibility Excellence installation..."
    
    local services=(
        "http://localhost:4000/health:Pa11y Service"
        "http://localhost:4001/health:Axe Service"
        "http://localhost:4002/health:WAVE Service"
        "http://localhost:4003/health:Lighthouse Accessibility"
        "http://localhost:4004/health:Contrast Analyzer"
        "http://localhost:4005/health:Screen Reader Service"
        "http://localhost:4006/health:Keyboard Navigation Service"
        "http://localhost:4007/health:Accessibility Orchestrator"
        "http://localhost:4008:Accessibility Dashboard"
        "http://localhost:4009/health:WCAG Compliance"
        "http://localhost:3311:Grafana Accessibility"
        "http://localhost:5603:Kibana Accessibility"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r url name <<< "$service"
        if curl -s "$url" > /dev/null 2>&1; then
            info "✓ $name is running"
        else
            warn "✗ $name is not responding"
        fi
    done
    
    log "Installation verification completed"
}

# Display access information
display_access_info() {
    log "Accessibility Excellence System Setup Complete!"
    
    echo ""
    echo "♿ ACCESSIBILITY EXCELLENCE ACCESS INFORMATION"
    echo "============================================="
    echo ""
    echo "🚀 Core Testing Services:"
    echo "   • Pa11y Service:               http://localhost:4000"
    echo "   • Axe-Core Service:            http://localhost:4001"
    echo "   • WAVE Service:                http://localhost:4002"
    echo "   • Lighthouse Accessibility:    http://localhost:4003"
    echo "   • Contrast Analyzer:           http://localhost:4004"
    echo "   • Screen Reader Service:       http://localhost:4005"
    echo "   • Keyboard Navigation:         http://localhost:4006"
    echo ""
    echo "🎯 Management & Orchestration:"
    echo "   • Accessibility Orchestrator:  http://localhost:4007"
    echo "   • Accessibility Dashboard:     http://localhost:4008"
    echo "   • WCAG Compliance Checker:     http://localhost:4009"
    echo ""
    echo "📊 Monitoring & Analytics:"
    echo "   • Grafana Accessibility:       http://localhost:3311 (admin/accessibility123)"
    echo "   • Prometheus Accessibility:    http://localhost:9096"
    echo "   • Kibana Accessibility:        http://localhost:5603"
    echo "   • ElasticSearch Accessibility: http://localhost:9202"
    echo ""
    echo "📋 WCAG 2.1 AA Compliance Features:"
    echo "   • Automated accessibility testing with Pa11y, Axe, WAVE, and Lighthouse"
    echo "   • Color contrast analysis with WCAG AA compliance checking"
    echo "   • Screen reader compatibility testing and optimization"
    echo "   • Keyboard navigation validation and focus management"
    echo "   • Semantic HTML structure validation"
    echo "   • ARIA attributes and roles verification"
    echo "   • Alternative text and media accessibility checks"
    echo "   • Form accessibility and error handling validation"
    echo ""
    echo "🔧 Testing Capabilities:"
    echo "   • Automated WCAG 2.1 AA compliance scanning"
    echo "   • Real-time accessibility monitoring"
    echo "   • Batch testing for multiple pages/components"
    echo "   • Accessibility regression testing"
    echo "   • Custom accessibility rule configuration"
    echo "   • Detailed violation reports with remediation guidance"
    echo ""
    echo "📈 Enterprise Features:"
    echo "   • Comprehensive accessibility analytics and reporting"
    echo "   • Performance metrics and trend analysis"
    echo "   • Automated accessibility testing in CI/CD pipelines"
    echo "   • Team collaboration and issue tracking"
    echo "   • Accessibility training materials and guidelines"
    echo "   • Integration with popular development tools"
    echo ""
    echo "🔧 Management Commands:"
    echo "   • Stop services:    docker-compose -f docker-compose.accessibility-excellence.yml down"
    echo "   • View logs:        docker-compose -f docker-compose.accessibility-excellence.yml logs -f"
    echo "   • Restart:          docker-compose -f docker-compose.accessibility-excellence.yml restart"
    echo ""
}

# Main execution
main() {
    log "Starting Enterprise Accessibility Excellence System Setup..."
    
    check_root
    check_requirements
    create_directories
    generate_configs
    create_docker_services
    initialize_services
    start_services
    verify_installation
    display_access_info
    
    log "Enterprise Accessibility Excellence System setup completed successfully!"
}

# Run main function
main "$@"
