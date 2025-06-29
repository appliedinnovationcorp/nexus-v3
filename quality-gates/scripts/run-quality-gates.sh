#!/bin/bash

# Quality Gates Execution Script
# Runs comprehensive quality checks on the project

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="nexus-v3"
API_URL="http://localhost:3001"
TARGET_URL="http://localhost:3000"
COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if Quality Gates services are running
check_services() {
    log "Checking Quality Gates services..."
    
    local services=(
        "http://localhost:3001/health:Quality Gates Orchestrator"
        "http://localhost:9000/api/system/status:SonarQube"
        "http://localhost:8080:OWASP ZAP"
        "http://localhost:4000:Pa11y Dashboard"
        "http://localhost:9001:Lighthouse CI"
    )
    
    for service in "${services[@]}"; do
        IFS=':' read -r url name <<< "$service"
        if ! curl -s -f "$url" > /dev/null 2>&1; then
            error "$name is not running. Please start Quality Gates services first."
        fi
    done
    
    log "All services are running"
}

# Execute quality gates
execute_quality_gates() {
    log "Executing quality gates for project: $PROJECT_NAME"
    
    local payload=$(cat << EOF
{
    "project": "$PROJECT_NAME",
    "gates": [
        {
            "type": "code_quality"
        },
        {
            "type": "security_scan"
        },
        {
            "type": "performance"
        },
        {
            "type": "accessibility"
        },
        {
            "type": "lint"
        }
    ],
    "config": {
        "target_url": "$TARGET_URL",
        "commit_hash": "$COMMIT_HASH",
        "branch": "$BRANCH",
        "files": ["**/*.{js,ts,jsx,tsx}"],
        "image": "nexus-v3:latest"
    }
}
EOF
    )
    
    log "Sending request to Quality Gates API..."
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$API_URL/api/quality-gates/execute")
    
    if [ $? -ne 0 ]; then
        error "Failed to execute quality gates"
    fi
    
    echo "$response" | jq '.' > quality-gates-results.json
    
    # Parse results
    local overall_status=$(echo "$response" | jq -r '.overall')
    local timestamp=$(echo "$response" | jq -r '.timestamp')
    
    log "Quality Gates execution completed at $timestamp"
    log "Overall status: $overall_status"
    
    # Display detailed results
    display_results "$response"
    
    # Return appropriate exit code
    if [ "$overall_status" = "PASSED" ]; then
        log "✅ All quality gates PASSED"
        return 0
    else
        error "❌ Quality gates FAILED"
        return 1
    fi
}

# Display detailed results
display_results() {
    local response="$1"
    
    echo
    echo -e "${BLUE}=== QUALITY GATES RESULTS ===${NC}"
    echo
    
    local results=$(echo "$response" | jq -r '.results[]')
    
    while IFS= read -r result; do
        local gate_type=$(echo "$result" | jq -r '.type')
        local passed=$(echo "$result" | jq -r '.passed')
        local violations=$(echo "$result" | jq -r '.violations[]?' 2>/dev/null || echo "")
        
        if [ "$passed" = "true" ]; then
            echo -e "${GREEN}✅ $gate_type: PASSED${NC}"
        else
            echo -e "${RED}❌ $gate_type: FAILED${NC}"
            if [ -n "$violations" ]; then
                echo -e "${RED}   Violations:${NC}"
                echo "$violations" | while IFS= read -r violation; do
                    echo -e "${RED}   - $violation${NC}"
                done
            fi
        fi
        
        # Display metrics if available
        local metrics=$(echo "$result" | jq -r '.metrics // empty')
        if [ -n "$metrics" ] && [ "$metrics" != "null" ]; then
            echo -e "${BLUE}   Metrics:${NC}"
            echo "$metrics" | jq -r 'to_entries[] | "   - \(.key): \(.value)"'
        fi
        
        echo
    done <<< "$(echo "$response" | jq -c '.results[]')"
}

# Generate report
generate_report() {
    log "Generating quality gates report..."
    
    local timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
    local report_file="quality-gates-report-$timestamp.html"
    
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Quality Gates Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .metric { margin: 5px 0; }
        .violation { color: #dc3545; margin: 5px 0; }
        .gate { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Quality Gates Report</h1>
        <p><strong>Project:</strong> nexus-v3</p>
        <p><strong>Timestamp:</strong> $(date)</p>
        <p><strong>Commit:</strong> $COMMIT_HASH</p>
        <p><strong>Branch:</strong> $BRANCH</p>
    </div>
EOF
    
    if [ -f "quality-gates-results.json" ]; then
        local overall=$(jq -r '.overall' quality-gates-results.json)
        echo "    <h2 class=\"$( [ "$overall" = "PASSED" ] && echo "passed" || echo "failed" )\">Overall Status: $overall</h2>" >> "$report_file"
        
        echo "    <h3>Gate Results:</h3>" >> "$report_file"
        
        jq -c '.results[]' quality-gates-results.json | while IFS= read -r result; do
            local gate_type=$(echo "$result" | jq -r '.type')
            local passed=$(echo "$result" | jq -r '.passed')
            local status_class=$( [ "$passed" = "true" ] && echo "passed" || echo "failed" )
            local status_text=$( [ "$passed" = "true" ] && echo "PASSED" || echo "FAILED" )
            
            echo "    <div class=\"gate\">" >> "$report_file"
            echo "        <h4 class=\"$status_class\">$gate_type: $status_text</h4>" >> "$report_file"
            
            # Add metrics
            local metrics=$(echo "$result" | jq -r '.metrics // empty')
            if [ -n "$metrics" ] && [ "$metrics" != "null" ]; then
                echo "        <h5>Metrics:</h5>" >> "$report_file"
                echo "$metrics" | jq -r 'to_entries[] | "<div class=\"metric\"><strong>\(.key):</strong> \(.value)</div>"' >> "$report_file"
            fi
            
            # Add violations
            local violations=$(echo "$result" | jq -r '.violations[]?' 2>/dev/null || echo "")
            if [ -n "$violations" ]; then
                echo "        <h5>Violations:</h5>" >> "$report_file"
                echo "$violations" | while IFS= read -r violation; do
                    echo "        <div class=\"violation\">• $violation</div>" >> "$report_file"
                done
            fi
            
            echo "    </div>" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << 'EOF'
</body>
</html>
EOF
    
    log "Report generated: $report_file"
}

# Main execution
main() {
    log "Starting Quality Gates execution..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --target-url)
                TARGET_URL="$2"
                shift 2
                ;;
            --api-url)
                API_URL="$2"
                shift 2
                ;;
            --report)
                GENERATE_REPORT=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --project NAME      Project name (default: nexus-v3)"
                echo "  --target-url URL    Target URL for testing (default: http://localhost:3000)"
                echo "  --api-url URL       Quality Gates API URL (default: http://localhost:3001)"
                echo "  --report            Generate HTML report"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    check_services
    
    if execute_quality_gates; then
        log "✅ Quality Gates execution completed successfully"
        
        if [ "${GENERATE_REPORT:-false}" = "true" ]; then
            generate_report
        fi
        
        exit 0
    else
        error "❌ Quality Gates execution failed"
        exit 1
    fi
}

# Execute main function
main "$@"
