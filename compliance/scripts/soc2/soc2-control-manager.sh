#!/bin/bash

set -e

# SOC 2 Control Manager
# Comprehensive SOC 2 Type II compliance management and monitoring

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[SOC2]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[SOC2 CONTROL MANAGER]${NC} $1"
}

# Configuration
COMPLIANCE_DB_URL=${DATABASE_URL:-"postgresql://compliance_admin:compliance_secure_pass@localhost:5432/compliance_db"}
SOC2_SERVICE_URL=${SOC2_SERVICE_URL:-"http://localhost:3022"}
EVIDENCE_STORAGE_PATH=${EVIDENCE_STORAGE_PATH:-"/tmp/soc2-evidence"}

# Initialize SOC 2 controls
initialize_soc2_controls() {
    print_header "Initializing SOC 2 Controls Framework"
    
    # Create evidence storage directory
    mkdir -p "$EVIDENCE_STORAGE_PATH"
    
    # Initialize standard SOC 2 controls
    local controls_sql="/tmp/soc2_controls_init.sql"
    
    cat > "$controls_sql" <<'EOF'
-- SOC 2 Type II Standard Controls

-- Security Controls (CC)
INSERT INTO soc2.controls (category, control_id, title, description, risk_level, control_type, frequency, owner) VALUES
('Security', 'CC1.1', 'Control Environment', 'Management establishes structures, reporting lines, and appropriate authorities and responsibilities', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'CISO'),
('Security', 'CC1.2', 'Communication and Information', 'Management uses relevant information to support the functioning of internal control', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'CISO'),
('Security', 'CC1.3', 'Monitoring Activities', 'Management evaluates and communicates internal control deficiencies', 'HIGH', 'DETECTIVE', 'MONTHLY', 'CISO'),
('Security', 'CC2.1', 'Risk Assessment Process', 'Management specifies objectives with sufficient clarity to enable identification of risks', 'HIGH', 'PREVENTIVE', 'QUARTERLY', 'Risk Manager'),
('Security', 'CC2.2', 'Risk Identification', 'Management identifies risks to the achievement of objectives', 'HIGH', 'DETECTIVE', 'QUARTERLY', 'Risk Manager'),
('Security', 'CC2.3', 'Risk Analysis', 'Management analyzes risks to the achievement of objectives', 'MEDIUM', 'DETECTIVE', 'QUARTERLY', 'Risk Manager'),
('Security', 'CC3.1', 'Control Activities', 'Management designs control activities to achieve objectives and respond to risks', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Operations Manager'),
('Security', 'CC3.2', 'Technology Controls', 'Management designs the entity''s information system and related technology controls', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'IT Manager'),
('Security', 'CC3.3', 'Policies and Procedures', 'Management implements control activities through policies and procedures', 'MEDIUM', 'PREVENTIVE', 'CONTINUOUS', 'Compliance Officer'),
('Security', 'CC4.1', 'Information and Communication', 'Management obtains or generates relevant, quality information', 'MEDIUM', 'PREVENTIVE', 'CONTINUOUS', 'IT Manager');

-- Availability Controls (A)
INSERT INTO soc2.controls (category, control_id, title, description, risk_level, control_type, frequency, owner) VALUES
('Availability', 'A1.1', 'System Availability', 'Management monitors system performance and availability', 'HIGH', 'DETECTIVE', 'CONTINUOUS', 'IT Operations'),
('Availability', 'A1.2', 'Capacity Management', 'Management monitors system capacity and performance', 'HIGH', 'PREVENTIVE', 'DAILY', 'IT Operations'),
('Availability', 'A1.3', 'Backup and Recovery', 'Management maintains backup and recovery procedures', 'HIGH', 'PREVENTIVE', 'DAILY', 'IT Operations'),
('Availability', 'A2.1', 'Incident Response', 'Management responds to system incidents and outages', 'HIGH', 'CORRECTIVE', 'AS_NEEDED', 'Incident Manager'),
('Availability', 'A2.2', 'Change Management', 'Management controls changes to system components', 'MEDIUM', 'PREVENTIVE', 'PER_CHANGE', 'Change Manager');

-- Processing Integrity Controls (PI)
INSERT INTO soc2.controls (category, control_id, title, description, risk_level, control_type, frequency, owner) VALUES
('Processing Integrity', 'PI1.1', 'Data Input Controls', 'Management implements controls over data input', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Data Manager'),
('Processing Integrity', 'PI1.2', 'Data Processing Controls', 'Management implements controls over data processing', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Data Manager'),
('Processing Integrity', 'PI1.3', 'Data Output Controls', 'Management implements controls over data output', 'MEDIUM', 'DETECTIVE', 'CONTINUOUS', 'Data Manager'),
('Processing Integrity', 'PI2.1', 'Error Handling', 'Management implements error detection and correction procedures', 'MEDIUM', 'CORRECTIVE', 'CONTINUOUS', 'Development Team');

-- Confidentiality Controls (C)
INSERT INTO soc2.controls (category, control_id, title, description, risk_level, control_type, frequency, owner) VALUES
('Confidentiality', 'C1.1', 'Data Classification', 'Management classifies information based on sensitivity', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Data Protection Officer'),
('Confidentiality', 'C1.2', 'Access Controls', 'Management restricts access to confidential information', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Security Team'),
('Confidentiality', 'C1.3', 'Encryption Controls', 'Management encrypts confidential information', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Security Team'),
('Confidentiality', 'C2.1', 'Data Handling', 'Management implements secure data handling procedures', 'MEDIUM', 'PREVENTIVE', 'CONTINUOUS', 'Operations Team');

-- Privacy Controls (P)
INSERT INTO soc2.controls (category, control_id, title, description, risk_level, control_type, frequency, owner) VALUES
('Privacy', 'P1.1', 'Privacy Notice', 'Management provides notice about privacy practices', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Privacy Officer'),
('Privacy', 'P1.2', 'Consent Management', 'Management obtains consent for data collection and use', 'HIGH', 'PREVENTIVE', 'CONTINUOUS', 'Privacy Officer'),
('Privacy', 'P2.1', 'Data Retention', 'Management implements data retention and disposal policies', 'MEDIUM', 'PREVENTIVE', 'CONTINUOUS', 'Data Manager'),
('Privacy', 'P2.2', 'Third Party Management', 'Management oversees third-party data processing', 'HIGH', 'PREVENTIVE', 'QUARTERLY', 'Vendor Manager');
EOF

    psql "$COMPLIANCE_DB_URL" -f "$controls_sql"
    
    if [[ $? -eq 0 ]]; then
        print_status "SOC 2 controls initialized successfully"
    else
        print_error "Failed to initialize SOC 2 controls"
        return 1
    fi
    
    rm -f "$controls_sql"
}

# Control testing and assessment
test_control() {
    local control_id=$1
    local test_type=$2
    local tester=$3
    
    print_header "Testing Control: $control_id"
    print_status "Test Type: $test_type"
    print_status "Tester: $tester"
    
    # Get control details
    local control_info=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT title, description, control_type FROM soc2.controls WHERE control_id = '$control_id';")
    
    if [[ -z "$control_info" ]]; then
        print_error "Control $control_id not found"
        return 1
    fi
    
    print_status "Control: $control_info"
    
    # Create test record
    local test_id=$(uuidgen)
    local test_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Perform automated tests based on control type
    case $control_id in
        "CC3.2"|"C1.3")
            test_encryption_controls "$control_id" "$test_id"
            ;;
        "A1.1"|"A1.2")
            test_availability_controls "$control_id" "$test_id"
            ;;
        "CC1.3"|"A2.1")
            test_monitoring_controls "$control_id" "$test_id"
            ;;
        "C1.2")
            test_access_controls "$control_id" "$test_id"
            ;;
        *)
            test_manual_control "$control_id" "$test_id" "$test_type"
            ;;
    esac
    
    # Update control testing status
    psql "$COMPLIANCE_DB_URL" -c \
        "UPDATE soc2.controls 
         SET last_tested = '$test_timestamp', 
             next_test_due = '$test_timestamp'::timestamp + INTERVAL '3 months',
             testing_status = 'TESTED'
         WHERE control_id = '$control_id';"
    
    print_status "Control testing completed - Test ID: $test_id"
}

test_encryption_controls() {
    local control_id=$1
    local test_id=$2
    
    print_status "Testing encryption controls..."
    
    # Test database encryption
    local db_encryption_status=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT setting FROM pg_settings WHERE name = 'ssl';")
    
    # Test data-at-rest encryption
    local encryption_test_result="PASS"
    local findings=()
    
    if [[ "$db_encryption_status" != *"on"* ]]; then
        encryption_test_result="FAIL"
        findings+=("Database SSL not enabled")
    fi
    
    # Test application-level encryption
    local app_encryption_check=$(curl -s "$SOC2_SERVICE_URL/api/encryption/status" | jq -r '.enabled')
    if [[ "$app_encryption_check" != "true" ]]; then
        encryption_test_result="FAIL"
        findings+=("Application encryption not enabled")
    fi
    
    # Record test results
    record_test_evidence "$control_id" "$test_id" "encryption_test" "$encryption_test_result" "${findings[*]}"
}

test_availability_controls() {
    local control_id=$1
    local test_id=$2
    
    print_status "Testing availability controls..."
    
    # Test system uptime
    local uptime_check=$(curl -s -w "%{http_code}" "$SOC2_SERVICE_URL/health" -o /dev/null)
    local availability_test_result="PASS"
    local findings=()
    
    if [[ "$uptime_check" != "200" ]]; then
        availability_test_result="FAIL"
        findings+=("Health check endpoint not responding")
    fi
    
    # Test backup systems
    local backup_status=$(curl -s "$SOC2_SERVICE_URL/api/backup/status" | jq -r '.last_backup_success')
    if [[ "$backup_status" != "true" ]]; then
        availability_test_result="FAIL"
        findings+=("Backup system failure detected")
    fi
    
    # Record test results
    record_test_evidence "$control_id" "$test_id" "availability_test" "$availability_test_result" "${findings[*]}"
}

test_access_controls() {
    local control_id=$1
    local test_id=$2
    
    print_status "Testing access controls..."
    
    # Test unauthorized access attempts
    local access_test_result="PASS"
    local findings=()
    
    # Attempt unauthorized access
    local unauthorized_response=$(curl -s -w "%{http_code}" "$SOC2_SERVICE_URL/api/admin/users" -o /dev/null)
    if [[ "$unauthorized_response" != "401" && "$unauthorized_response" != "403" ]]; then
        access_test_result="FAIL"
        findings+=("Unauthorized access not properly blocked")
    fi
    
    # Test role-based access
    local rbac_status=$(curl -s "$SOC2_SERVICE_URL/api/access/rbac-status" | jq -r '.enabled')
    if [[ "$rbac_status" != "true" ]]; then
        access_test_result="FAIL"
        findings+=("Role-based access control not enabled")
    fi
    
    # Record test results
    record_test_evidence "$control_id" "$test_id" "access_control_test" "$access_test_result" "${findings[*]}"
}

# Evidence collection and management
collect_evidence() {
    local control_id=$1
    local evidence_type=$2
    local description=$3
    local file_path=$4
    
    print_header "Collecting Evidence for Control: $control_id"
    
    local evidence_id=$(uuidgen)
    local evidence_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local evidence_file="$EVIDENCE_STORAGE_PATH/${control_id}_${evidence_id}"
    
    # Copy evidence file if provided
    if [[ -n "$file_path" && -f "$file_path" ]]; then
        cp "$file_path" "$evidence_file"
        print_status "Evidence file copied to: $evidence_file"
    fi
    
    # Record evidence in database
    psql "$COMPLIANCE_DB_URL" -c \
        "INSERT INTO soc2.evidence (control_id, evidence_type, description, file_path, collected_by, collected_at)
         VALUES (
             (SELECT id FROM soc2.controls WHERE control_id = '$control_id'),
             '$evidence_type',
             '$description',
             '$evidence_file',
             '$(whoami)',
             '$evidence_timestamp'
         );"
    
    if [[ $? -eq 0 ]]; then
        print_status "Evidence collected - ID: $evidence_id"
    else
        print_error "Failed to record evidence"
        return 1
    fi
}

record_test_evidence() {
    local control_id=$1
    local test_id=$2
    local test_type=$3
    local result=$4
    local findings=$5
    
    local evidence_description="Automated test: $test_type - Result: $result"
    if [[ -n "$findings" ]]; then
        evidence_description="$evidence_description - Findings: $findings"
    fi
    
    # Create test report
    local test_report="$EVIDENCE_STORAGE_PATH/${control_id}_test_${test_id}.json"
    cat > "$test_report" <<EOF
{
    "test_id": "$test_id",
    "control_id": "$control_id",
    "test_type": "$test_type",
    "test_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "tester": "$(whoami)",
    "result": "$result",
    "findings": "$findings",
    "automated": true
}
EOF
    
    collect_evidence "$control_id" "test_result" "$evidence_description" "$test_report"
}

# Control assessment and reporting
assess_control_effectiveness() {
    local control_id=$1
    
    print_header "Assessing Control Effectiveness: $control_id"
    
    # Get recent test results
    local test_results=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT COUNT(*) as total_tests,
                SUM(CASE WHEN e.description LIKE '%Result: PASS%' THEN 1 ELSE 0 END) as passed_tests
         FROM soc2.evidence e
         JOIN soc2.controls c ON c.id = e.control_id
         WHERE c.control_id = '$control_id'
         AND e.evidence_type = 'test_result'
         AND e.collected_at > NOW() - INTERVAL '3 months';")
    
    local total_tests=$(echo "$test_results" | awk '{print $1}')
    local passed_tests=$(echo "$test_results" | awk '{print $3}')
    
    if [[ $total_tests -eq 0 ]]; then
        print_warning "No recent test results found for control $control_id"
        return 1
    fi
    
    local effectiveness_rate=$((passed_tests * 100 / total_tests))
    local effectiveness_status
    
    if [[ $effectiveness_rate -ge 95 ]]; then
        effectiveness_status="EFFECTIVE"
    elif [[ $effectiveness_rate -ge 80 ]]; then
        effectiveness_status="PARTIALLY_EFFECTIVE"
    else
        effectiveness_status="INEFFECTIVE"
    fi
    
    print_status "Control Effectiveness: $effectiveness_status ($effectiveness_rate%)"
    print_status "Tests Passed: $passed_tests/$total_tests"
    
    # Update control status
    psql "$COMPLIANCE_DB_URL" -c \
        "UPDATE soc2.controls 
         SET implementation_status = '$effectiveness_status'
         WHERE control_id = '$control_id';"
    
    # Generate recommendations if needed
    if [[ $effectiveness_rate -lt 95 ]]; then
        generate_remediation_plan "$control_id" "$effectiveness_rate"
    fi
}

generate_remediation_plan() {
    local control_id=$1
    local effectiveness_rate=$2
    
    print_header "Generating Remediation Plan for Control: $control_id"
    
    local remediation_file="$EVIDENCE_STORAGE_PATH/${control_id}_remediation_$(date +%Y%m%d).json"
    
    cat > "$remediation_file" <<EOF
{
    "control_id": "$control_id",
    "current_effectiveness": $effectiveness_rate,
    "target_effectiveness": 95,
    "remediation_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "priority": "$([ $effectiveness_rate -lt 50 ] && echo "HIGH" || echo "MEDIUM")",
    "recommended_actions": [
        "Review control design and implementation",
        "Enhance monitoring and detection capabilities",
        "Provide additional training to control owners",
        "Implement automated testing where possible",
        "Review and update control documentation"
    ],
    "target_completion_date": "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)",
    "assigned_to": "$(psql "$COMPLIANCE_DB_URL" -t -c "SELECT owner FROM soc2.controls WHERE control_id = '$control_id';")"
}
EOF
    
    print_status "Remediation plan generated: $remediation_file"
    
    collect_evidence "$control_id" "remediation_plan" "Control remediation plan - Effectiveness: $effectiveness_rate%" "$remediation_file"
}

# Generate SOC 2 compliance reports
generate_soc2_report() {
    local report_type=$1
    local start_date=$2
    local end_date=$3
    
    print_header "Generating SOC 2 Report: $report_type"
    
    local report_file="/tmp/soc2_report_$(date +%Y%m%d_%H%M%S).json"
    
    case $report_type in
        "control_status")
            generate_control_status_report "$report_file" "$start_date" "$end_date"
            ;;
        "testing_summary")
            generate_testing_summary_report "$report_file" "$start_date" "$end_date"
            ;;
        "compliance_posture")
            generate_compliance_posture_report "$report_file" "$start_date" "$end_date"
            ;;
        "audit_readiness")
            generate_audit_readiness_report "$report_file" "$start_date" "$end_date"
            ;;
        *)
            print_error "Unknown report type: $report_type"
            return 1
            ;;
    esac
    
    print_status "Report generated: $report_file"
}

generate_control_status_report() {
    local report_file=$1
    local start_date=$2
    local end_date=$3
    
    local report_data=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT json_agg(
            json_build_object(
                'control_id', control_id,
                'title', title,
                'category', category,
                'implementation_status', implementation_status,
                'testing_status', testing_status,
                'last_tested', last_tested,
                'next_test_due', next_test_due,
                'owner', owner,
                'risk_level', risk_level
            )
         ) FROM soc2.controls;")
    
    cat > "$report_file" <<EOF
{
    "report_type": "control_status",
    "generated_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "period": {
        "start_date": "$start_date",
        "end_date": "$end_date"
    },
    "controls": $report_data
}
EOF
}

# Main function
main() {
    case $1 in
        "init")
            initialize_soc2_controls
            ;;
        "test")
            test_control "$2" "$3" "$4"
            ;;
        "evidence")
            collect_evidence "$2" "$3" "$4" "$5"
            ;;
        "assess")
            assess_control_effectiveness "$2"
            ;;
        "report")
            generate_soc2_report "$2" "$3" "$4"
            ;;
        *)
            echo "SOC 2 Control Manager"
            echo ""
            echo "Usage:"
            echo "  $0 init                                    - Initialize SOC 2 controls"
            echo "  $0 test <control_id> <type> <tester>      - Test control"
            echo "  $0 evidence <control_id> <type> <desc> [file] - Collect evidence"
            echo "  $0 assess <control_id>                    - Assess control effectiveness"
            echo "  $0 report <type> <start_date> <end_date>  - Generate compliance report"
            echo ""
            echo "Examples:"
            echo "  $0 init"
            echo "  $0 test CC1.1 design 'Security Team'"
            echo "  $0 evidence CC1.1 policy 'Security policy document' /path/to/policy.pdf"
            echo "  $0 assess CC1.1"
            echo "  $0 report control_status 2024-01-01 2024-03-31"
            ;;
    esac
}

main "$@"
