#!/bin/bash

set -e

# GDPR Compliance Toolkit
# Comprehensive GDPR compliance management and automation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[GDPR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[GDPR TOOLKIT]${NC} $1"
}

# Configuration
COMPLIANCE_DB_URL=${DATABASE_URL:-"postgresql://compliance_admin:compliance_secure_pass@localhost:5432/compliance_db"}
GDPR_SERVICE_URL=${GDPR_SERVICE_URL:-"http://localhost:3020"}
ANONYMIZATION_SERVICE_URL=${ANONYMIZATION_SERVICE_URL:-"http://localhost:3021"}

# Data Subject Rights Request Processing
process_data_subject_request() {
    local request_type=$1
    local email=$2
    local verification_token=$3
    
    print_header "Processing Data Subject Request: $request_type for $email"
    
    case $request_type in
        "access")
            process_access_request "$email" "$verification_token"
            ;;
        "rectification")
            process_rectification_request "$email" "$verification_token"
            ;;
        "erasure")
            process_erasure_request "$email" "$verification_token"
            ;;
        "portability")
            process_portability_request "$email" "$verification_token"
            ;;
        "restriction")
            process_restriction_request "$email" "$verification_token"
            ;;
        "objection")
            process_objection_request "$email" "$verification_token"
            ;;
        *)
            print_error "Unknown request type: $request_type"
            exit 1
            ;;
    esac
}

process_access_request() {
    local email=$1
    local token=$2
    
    print_status "Processing Right of Access request for $email"
    
    # Verify identity
    if ! verify_data_subject_identity "$email" "$token"; then
        print_error "Identity verification failed"
        return 1
    fi
    
    # Generate data export
    local export_file="/tmp/gdpr_export_$(date +%Y%m%d_%H%M%S).json"
    
    curl -s -X POST "$GDPR_SERVICE_URL/api/data-subject/export" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"verification_token\":\"$token\"}" \
        -o "$export_file"
    
    if [[ $? -eq 0 ]]; then
        print_status "Data export generated: $export_file"
        
        # Log the access request
        log_gdpr_activity "access_request_fulfilled" "$email" "Data export provided"
    else
        print_error "Failed to generate data export"
        return 1
    fi
}

process_erasure_request() {
    local email=$1
    local token=$2
    
    print_status "Processing Right to Erasure request for $email"
    
    # Check for legal holds
    if check_legal_holds "$email"; then
        print_warning "Legal hold active - erasure request cannot be fulfilled"
        log_gdpr_activity "erasure_request_denied" "$email" "Legal hold active"
        return 1
    fi
    
    # Check for legitimate interests
    if check_legitimate_interests "$email"; then
        print_warning "Legitimate interests override - erasure request denied"
        log_gdpr_activity "erasure_request_denied" "$email" "Legitimate interests"
        return 1
    fi
    
    # Perform anonymization instead of deletion
    print_status "Anonymizing data for $email"
    
    curl -s -X POST "$ANONYMIZATION_SERVICE_URL/api/anonymize/user" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"method\":\"k_anonymity\",\"k\":5}"
    
    if [[ $? -eq 0 ]]; then
        print_status "Data anonymized successfully"
        log_gdpr_activity "erasure_request_fulfilled" "$email" "Data anonymized"
    else
        print_error "Failed to anonymize data"
        return 1
    fi
}

# Consent Management
manage_consent() {
    local action=$1
    local email=$2
    local purpose=$3
    local lawful_basis=$4
    
    print_header "Managing Consent: $action for $email"
    
    case $action in
        "record")
            record_consent "$email" "$purpose" "$lawful_basis"
            ;;
        "withdraw")
            withdraw_consent "$email" "$purpose"
            ;;
        "update")
            update_consent "$email" "$purpose" "$lawful_basis"
            ;;
        "check")
            check_consent "$email" "$purpose"
            ;;
        *)
            print_error "Unknown consent action: $action"
            exit 1
            ;;
    esac
}

record_consent() {
    local email=$1
    local purpose=$2
    local lawful_basis=$3
    
    print_status "Recording consent for $email - Purpose: $purpose"
    
    local consent_data=$(cat <<EOF
{
    "email": "$email",
    "purpose": "$purpose",
    "lawful_basis": "$lawful_basis",
    "consent_given": true,
    "consent_method": "explicit",
    "consent_version": "2.0",
    "processing_categories": ["profile_data", "usage_analytics"],
    "data_categories": ["personal_identifiers", "behavioral_data"],
    "retention_period": 730,
    "third_party_sharing": false
}
EOF
    )
    
    curl -s -X POST "$GDPR_SERVICE_URL/api/consent/record" \
        -H "Content-Type: application/json" \
        -d "$consent_data"
    
    if [[ $? -eq 0 ]]; then
        print_status "Consent recorded successfully"
        log_gdpr_activity "consent_recorded" "$email" "Purpose: $purpose"
    else
        print_error "Failed to record consent"
        return 1
    fi
}

withdraw_consent() {
    local email=$1
    local purpose=$2
    
    print_status "Withdrawing consent for $email - Purpose: $purpose"
    
    curl -s -X POST "$GDPR_SERVICE_URL/api/consent/withdraw" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"purpose\":\"$purpose\"}"
    
    if [[ $? -eq 0 ]]; then
        print_status "Consent withdrawn successfully"
        log_gdpr_activity "consent_withdrawn" "$email" "Purpose: $purpose"
        
        # Trigger data processing review
        review_processing_after_withdrawal "$email" "$purpose"
    else
        print_error "Failed to withdraw consent"
        return 1
    fi
}

# Privacy Impact Assessment
conduct_pia() {
    local processing_activity=$1
    local data_categories=$2
    local risk_level=$3
    
    print_header "Conducting Privacy Impact Assessment"
    print_status "Activity: $processing_activity"
    print_status "Data Categories: $data_categories"
    print_status "Risk Level: $risk_level"
    
    local pia_id=$(uuidgen)
    local pia_file="/tmp/pia_${pia_id}.json"
    
    # Generate PIA template
    cat > "$pia_file" <<EOF
{
    "pia_id": "$pia_id",
    "processing_activity": "$processing_activity",
    "data_categories": "$data_categories",
    "risk_level": "$risk_level",
    "assessment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "assessor": "$(whoami)",
    "necessity_assessment": {
        "data_minimization": "pending",
        "purpose_limitation": "pending",
        "storage_limitation": "pending"
    },
    "risk_assessment": {
        "likelihood": "pending",
        "severity": "pending",
        "overall_risk": "pending"
    },
    "mitigation_measures": [],
    "consultation_required": false,
    "dpo_review_required": true,
    "status": "draft"
}
EOF
    
    print_status "PIA template generated: $pia_file"
    
    # Submit to GDPR service
    curl -s -X POST "$GDPR_SERVICE_URL/api/pia/create" \
        -H "Content-Type: application/json" \
        -d @"$pia_file"
    
    if [[ $? -eq 0 ]]; then
        print_status "PIA submitted for review"
        log_gdpr_activity "pia_initiated" "$processing_activity" "PIA ID: $pia_id"
    else
        print_error "Failed to submit PIA"
        return 1
    fi
}

# Data Breach Response
handle_data_breach() {
    local breach_type=$1
    local affected_records=$2
    local severity=$3
    
    print_header "Handling Data Breach"
    print_status "Type: $breach_type"
    print_status "Affected Records: $affected_records"
    print_status "Severity: $severity"
    
    local breach_id=$(uuidgen)
    local breach_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create breach record
    local breach_data=$(cat <<EOF
{
    "breach_id": "$breach_id",
    "breach_type": "$breach_type",
    "discovery_date": "$breach_timestamp",
    "affected_records": $affected_records,
    "severity": "$severity",
    "containment_status": "in_progress",
    "notification_required": $([ "$severity" = "high" ] && echo "true" || echo "false"),
    "authority_notification_deadline": "$(date -u -d '+72 hours' +%Y-%m-%dT%H:%M:%SZ)",
    "data_subject_notification_required": $([ $affected_records -gt 100 ] && echo "true" || echo "false"),
    "remediation_actions": [],
    "lessons_learned": []
}
EOF
    )
    
    # Submit breach report
    curl -s -X POST "$GDPR_SERVICE_URL/api/breach/report" \
        -H "Content-Type: application/json" \
        -d "$breach_data"
    
    if [[ $? -eq 0 ]]; then
        print_status "Breach reported - ID: $breach_id"
        
        # Check if authority notification required
        if [[ "$severity" = "high" ]]; then
            print_warning "High severity breach - Authority notification required within 72 hours"
            schedule_authority_notification "$breach_id"
        fi
        
        # Check if data subject notification required
        if [[ $affected_records -gt 100 ]]; then
            print_warning "Large breach - Data subject notification may be required"
            assess_data_subject_notification "$breach_id"
        fi
        
        log_gdpr_activity "breach_reported" "system" "Breach ID: $breach_id"
    else
        print_error "Failed to report breach"
        return 1
    fi
}

# Utility functions
verify_data_subject_identity() {
    local email=$1
    local token=$2
    
    # Implement identity verification logic
    curl -s -X POST "$GDPR_SERVICE_URL/api/identity/verify" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"token\":\"$token\"}" | \
        jq -r '.verified' | grep -q "true"
}

check_legal_holds() {
    local email=$1
    
    psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT COUNT(*) FROM compliance.legal_holds lh 
         JOIN gdpr.data_subjects ds ON ds.email = '$email' 
         WHERE lh.status = 'ACTIVE';" | \
        grep -q "0" && return 1 || return 0
}

check_legitimate_interests() {
    local email=$1
    
    # Check for legitimate interests that override erasure
    psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT COUNT(*) FROM gdpr.data_processing_activities 
         WHERE data_subject_id = (SELECT id FROM gdpr.data_subjects WHERE email = '$email')
         AND lawful_basis = 'legitimate_interests'
         AND purpose IN ('fraud_prevention', 'security', 'legal_compliance');" | \
        grep -q "0" && return 1 || return 0
}

log_gdpr_activity() {
    local activity=$1
    local subject=$2
    local details=$3
    
    local log_entry=$(cat <<EOF
{
    "event_type": "gdpr_activity",
    "activity": "$activity",
    "subject": "$subject",
    "details": "$details",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "compliance_tags": ["gdpr", "data_protection"]
}
EOF
    )
    
    # Send to audit logging
    curl -s -X POST "http://localhost:8080" \
        -H "Content-Type: application/json" \
        -d "$log_entry" > /dev/null
}

# Generate compliance reports
generate_gdpr_report() {
    local report_type=$1
    local start_date=$2
    local end_date=$3
    
    print_header "Generating GDPR Report: $report_type"
    
    local report_file="/tmp/gdpr_report_$(date +%Y%m%d_%H%M%S).json"
    
    curl -s -X POST "$GDPR_SERVICE_URL/api/reports/generate" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"$report_type\",\"start_date\":\"$start_date\",\"end_date\":\"$end_date\"}" \
        -o "$report_file"
    
    if [[ $? -eq 0 ]]; then
        print_status "Report generated: $report_file"
    else
        print_error "Failed to generate report"
        return 1
    fi
}

# Main function
main() {
    case $1 in
        "request")
            process_data_subject_request "$2" "$3" "$4"
            ;;
        "consent")
            manage_consent "$2" "$3" "$4" "$5"
            ;;
        "pia")
            conduct_pia "$2" "$3" "$4"
            ;;
        "breach")
            handle_data_breach "$2" "$3" "$4"
            ;;
        "report")
            generate_gdpr_report "$2" "$3" "$4"
            ;;
        *)
            echo "GDPR Compliance Toolkit"
            echo ""
            echo "Usage:"
            echo "  $0 request <type> <email> <token>     - Process data subject request"
            echo "  $0 consent <action> <email> <purpose> - Manage consent"
            echo "  $0 pia <activity> <data> <risk>       - Conduct Privacy Impact Assessment"
            echo "  $0 breach <type> <records> <severity> - Handle data breach"
            echo "  $0 report <type> <start> <end>        - Generate compliance report"
            echo ""
            echo "Examples:"
            echo "  $0 request access user@example.com token123"
            echo "  $0 consent record user@example.com marketing consent"
            echo "  $0 pia 'user_profiling' 'behavioral_data' 'high'"
            echo "  $0 breach 'unauthorized_access' 1000 'high'"
            echo "  $0 report 'monthly' '2024-01-01' '2024-01-31'"
            ;;
    esac
}

main "$@"
