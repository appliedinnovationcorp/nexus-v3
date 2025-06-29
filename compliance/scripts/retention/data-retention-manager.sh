#!/bin/bash

set -e

# Data Retention Manager
# Automated data lifecycle management with compliance and legal hold integration

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[RETENTION]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DATA RETENTION MANAGER]${NC} $1"
}

# Configuration
COMPLIANCE_DB_URL=${DATABASE_URL:-"postgresql://compliance_admin:compliance_secure_pass@localhost:5432/compliance_db"}
ANONYMIZATION_SERVICE_URL=${ANONYMIZATION_SERVICE_URL:-"http://localhost:3021"}
AIRFLOW_URL=${AIRFLOW_URL:-"http://localhost:8081"}
RETENTION_REPORTS_PATH=${RETENTION_REPORTS_PATH:-"/tmp/retention-reports"}

# Initialize data retention framework
initialize_retention_framework() {
    print_header "Initializing Data Retention Framework"
    
    # Create retention reports directory
    mkdir -p "$RETENTION_REPORTS_PATH"
    
    # Setup default retention policies
    setup_default_retention_policies
    
    # Initialize retention monitoring
    setup_retention_monitoring
    
    # Create retention workflow templates
    create_retention_workflows
    
    print_status "Data retention framework initialized successfully"
}

setup_default_retention_policies() {
    print_status "Setting up default retention policies..."
    
    local policies_sql="/tmp/default_retention_policies.sql"
    
    cat > "$policies_sql" <<'EOF'
-- Default Data Retention Policies

-- User data retention
INSERT INTO compliance.data_retention_policies (table_name, retention_period_days, policy_reason, legal_basis, anonymization_required, created_by, effective_date, status) VALUES
('users', 2555, 'GDPR Article 5(1)(e) - Storage limitation', 'Legal compliance', true, 'system', CURRENT_DATE, 'ACTIVE'),
('user_profiles', 2555, 'GDPR Article 5(1)(e) - Storage limitation', 'Legal compliance', true, 'system', CURRENT_DATE, 'ACTIVE'),
('user_preferences', 1095, 'Business requirement - User preferences', 'Legitimate interest', true, 'system', CURRENT_DATE, 'ACTIVE');

-- Transaction data retention
INSERT INTO compliance.data_retention_policies (table_name, retention_period_days, policy_reason, legal_basis, anonymization_required, created_by, effective_date, status) VALUES
('transactions', 2555, 'Financial regulations - Transaction records', 'Legal obligation', false, 'system', CURRENT_DATE, 'ACTIVE'),
('payment_methods', 1095, 'PCI DSS - Payment data retention', 'Legal obligation', true, 'system', CURRENT_DATE, 'ACTIVE'),
('invoices', 2555, 'Tax regulations - Invoice retention', 'Legal obligation', false, 'system', CURRENT_DATE, 'ACTIVE');

-- Communication data retention
INSERT INTO compliance.data_retention_policies (table_name, retention_period_days, policy_reason, legal_basis, anonymization_required, created_by, effective_date, status) VALUES
('emails', 1095, 'Business communication retention', 'Legitimate interest', true, 'system', CURRENT_DATE, 'ACTIVE'),
('chat_messages', 365, 'Customer support records', 'Legitimate interest', true, 'system', CURRENT_DATE, 'ACTIVE'),
('notifications', 180, 'Notification delivery records', 'Legitimate interest', false, 'system', CURRENT_DATE, 'ACTIVE');

-- Analytics and logging data retention
INSERT INTO compliance.data_retention_policies (table_name, retention_period_days, policy_reason, legal_basis, anonymization_required, created_by, effective_date, status) VALUES
('user_analytics', 730, 'Business analytics and insights', 'Legitimate interest', true, 'system', CURRENT_DATE, 'ACTIVE'),
('access_logs', 2555, 'Security and audit requirements', 'Legal obligation', false, 'system', CURRENT_DATE, 'ACTIVE'),
('error_logs', 365, 'System maintenance and debugging', 'Legitimate interest', true, 'system', CURRENT_DATE, 'ACTIVE');

-- Session and temporary data retention
INSERT INTO compliance.data_retention_policies (table_name, retention_period_days, policy_reason, legal_basis, anonymization_required, created_by, effective_date, status) VALUES
('user_sessions', 30, 'Session management', 'Technical necessity', false, 'system', CURRENT_DATE, 'ACTIVE'),
('temporary_uploads', 7, 'Temporary file cleanup', 'Technical necessity', false, 'system', CURRENT_DATE, 'ACTIVE'),
('cache_data', 1, 'Performance optimization', 'Technical necessity', false, 'system', CURRENT_DATE, 'ACTIVE');
EOF

    psql "$COMPLIANCE_DB_URL" -f "$policies_sql"
    
    if [[ $? -eq 0 ]]; then
        print_status "Default retention policies created successfully"
    else
        print_error "Failed to create default retention policies"
        return 1
    fi
    
    rm -f "$policies_sql"
}

setup_retention_monitoring() {
    print_status "Setting up retention monitoring..."
    
    # Create monitoring queries for data age analysis
    local monitoring_sql="/tmp/retention_monitoring.sql"
    
    cat > "$monitoring_sql" <<'EOF'
-- Create views for retention monitoring

-- Data age analysis view
CREATE OR REPLACE VIEW compliance.data_age_analysis AS
SELECT 
    table_name,
    retention_period_days,
    policy_reason,
    anonymization_required,
    CASE 
        WHEN table_name = 'users' THEN (
            SELECT COUNT(*) FROM users 
            WHERE created_at < NOW() - (retention_period_days || ' days')::INTERVAL
        )
        WHEN table_name = 'transactions' THEN (
            SELECT COUNT(*) FROM transactions 
            WHERE created_at < NOW() - (retention_period_days || ' days')::INTERVAL
        )
        ELSE 0
    END as records_due_for_retention,
    effective_date,
    status
FROM compliance.data_retention_policies
WHERE status = 'ACTIVE';

-- Legal hold impact view
CREATE OR REPLACE VIEW compliance.legal_hold_impact AS
SELECT 
    lh.table_name,
    lh.hold_reason,
    lh.case_number,
    COUNT(*) as affected_records,
    lh.status,
    lh.expiration_date
FROM compliance.legal_holds lh
WHERE lh.status = 'ACTIVE'
GROUP BY lh.table_name, lh.hold_reason, lh.case_number, lh.status, lh.expiration_date;

-- Retention compliance dashboard view
CREATE OR REPLACE VIEW compliance.retention_compliance_dashboard AS
SELECT 
    drp.table_name,
    drp.retention_period_days,
    daa.records_due_for_retention,
    COALESCE(lhi.affected_records, 0) as records_on_legal_hold,
    (daa.records_due_for_retention - COALESCE(lhi.affected_records, 0)) as records_eligible_for_retention,
    drp.anonymization_required,
    drp.policy_reason
FROM compliance.data_retention_policies drp
LEFT JOIN compliance.data_age_analysis daa ON drp.table_name = daa.table_name
LEFT JOIN compliance.legal_hold_impact lhi ON drp.table_name = lhi.table_name
WHERE drp.status = 'ACTIVE';
EOF

    psql "$COMPLIANCE_DB_URL" -f "$monitoring_sql"
    
    if [[ $? -eq 0 ]]; then
        print_status "Retention monitoring views created successfully"
    else
        print_error "Failed to create retention monitoring views"
        return 1
    fi
    
    rm -f "$monitoring_sql"
}

create_retention_workflows() {
    print_status "Creating retention workflow templates..."
    
    # Create Airflow DAG template for data retention
    local dag_template="/tmp/data_retention_dag_template.py"
    
    cat > "$dag_template" <<'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.operators.bash_operator import BashOperator
import psycopg2
import requests
import json

default_args = {
    'owner': 'compliance-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'data_retention_workflow',
    default_args=default_args,
    description='Automated data retention and lifecycle management',
    schedule_interval='@daily',
    catchup=False,
    tags=['compliance', 'retention', 'gdpr'],
)

def check_retention_eligibility(**context):
    """Check which records are eligible for retention processing"""
    conn = psycopg2.connect(
        host='postgres-compliance',
        database='compliance_db',
        user='compliance_admin',
        password='compliance_secure_pass'
    )
    
    cursor = conn.cursor()
    cursor.execute("""
        SELECT table_name, records_eligible_for_retention, anonymization_required
        FROM compliance.retention_compliance_dashboard
        WHERE records_eligible_for_retention > 0
    """)
    
    eligible_tables = cursor.fetchall()
    conn.close()
    
    # Store results for downstream tasks
    context['task_instance'].xcom_push(key='eligible_tables', value=eligible_tables)
    
    return f"Found {len(eligible_tables)} tables with records eligible for retention"

def process_table_retention(table_name, anonymization_required, **context):
    """Process retention for a specific table"""
    if anonymization_required:
        # Call anonymization service
        response = requests.post(
            'http://anonymization-service:3000/api/anonymize/table',
            json={
                'table_name': table_name,
                'method': 'k_anonymity',
                'k': 5,
                'retention_mode': True
            }
        )
        
        if response.status_code == 200:
            return f"Anonymized records in {table_name}"
        else:
            raise Exception(f"Anonymization failed for {table_name}")
    else:
        # Direct deletion for non-sensitive data
        conn = psycopg2.connect(
            host='postgres-compliance',
            database='compliance_db',
            user='compliance_admin',
            password='compliance_secure_pass'
        )
        
        cursor = conn.cursor()
        
        # Get retention period
        cursor.execute("""
            SELECT retention_period_days FROM compliance.data_retention_policies
            WHERE table_name = %s AND status = 'ACTIVE'
        """, (table_name,))
        
        retention_period = cursor.fetchone()[0]
        
        # Delete old records (simplified - actual implementation would be table-specific)
        cursor.execute(f"""
            DELETE FROM {table_name}
            WHERE created_at < NOW() - INTERVAL '{retention_period} days'
            AND id NOT IN (
                SELECT DISTINCT record_id FROM compliance.legal_holds
                WHERE table_name = %s AND status = 'ACTIVE'
            )
        """, (table_name,))
        
        deleted_count = cursor.rowcount
        conn.commit()
        conn.close()
        
        return f"Deleted {deleted_count} records from {table_name}"

def generate_retention_report(**context):
    """Generate retention processing report"""
    eligible_tables = context['task_instance'].xcom_pull(key='eligible_tables')
    
    report = {
        'date': datetime.now().isoformat(),
        'processed_tables': len(eligible_tables),
        'tables': eligible_tables,
        'status': 'completed'
    }
    
    # Save report
    with open(f'/tmp/retention-reports/retention_report_{datetime.now().strftime("%Y%m%d")}.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    return "Retention report generated"

# Define tasks
check_eligibility_task = PythonOperator(
    task_id='check_retention_eligibility',
    python_callable=check_retention_eligibility,
    dag=dag,
)

generate_report_task = PythonOperator(
    task_id='generate_retention_report',
    python_callable=generate_retention_report,
    dag=dag,
)

# Set task dependencies
check_eligibility_task >> generate_report_task
EOF

    print_status "Retention workflow template created: $dag_template"
}

# Data retention execution
execute_retention_policy() {
    local table_name=$1
    local dry_run=${2:-false}
    
    print_header "Executing Retention Policy for: $table_name"
    
    # Get retention policy details
    local policy_info=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT retention_period_days, anonymization_required, policy_reason 
         FROM compliance.data_retention_policies 
         WHERE table_name = '$table_name' AND status = 'ACTIVE';")
    
    if [[ -z "$policy_info" ]]; then
        print_error "No active retention policy found for table: $table_name"
        return 1
    fi
    
    local retention_period=$(echo "$policy_info" | awk '{print $1}')
    local anonymization_required=$(echo "$policy_info" | awk '{print $2}')
    local policy_reason=$(echo "$policy_info" | awk '{print $3}')
    
    print_status "Retention Period: $retention_period days"
    print_status "Anonymization Required: $anonymization_required"
    print_status "Policy Reason: $policy_reason"
    
    # Check for legal holds
    local legal_holds=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT COUNT(*) FROM compliance.legal_holds 
         WHERE table_name = '$table_name' AND status = 'ACTIVE';")
    
    if [[ $legal_holds -gt 0 ]]; then
        print_warning "Legal holds active for $table_name - checking individual records"
    fi
    
    # Get eligible records count
    local eligible_records=$(get_eligible_records_count "$table_name" "$retention_period")
    
    print_status "Records eligible for retention: $eligible_records"
    
    if [[ $eligible_records -eq 0 ]]; then
        print_status "No records eligible for retention processing"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        print_status "DRY RUN: Would process $eligible_records records"
        return 0
    fi
    
    # Execute retention based on policy
    if [[ "$anonymization_required" == "t" ]]; then
        execute_anonymization_retention "$table_name" "$retention_period"
    else
        execute_deletion_retention "$table_name" "$retention_period"
    fi
    
    # Log retention activity
    log_retention_activity "$table_name" "$eligible_records" "$anonymization_required"
}

get_eligible_records_count() {
    local table_name=$1
    local retention_period=$2
    
    # This is a simplified implementation - in production, each table would have specific logic
    case $table_name in
        "users")
            psql "$COMPLIANCE_DB_URL" -t -c \
                "SELECT COUNT(*) FROM users 
                 WHERE created_at < NOW() - INTERVAL '$retention_period days'
                 AND id NOT IN (
                     SELECT DISTINCT record_id FROM compliance.legal_holds 
                     WHERE table_name = '$table_name' AND status = 'ACTIVE'
                 );"
            ;;
        "transactions")
            psql "$COMPLIANCE_DB_URL" -t -c \
                "SELECT COUNT(*) FROM transactions 
                 WHERE created_at < NOW() - INTERVAL '$retention_period days'
                 AND id NOT IN (
                     SELECT DISTINCT record_id FROM compliance.legal_holds 
                     WHERE table_name = '$table_name' AND status = 'ACTIVE'
                 );"
            ;;
        *)
            echo "0"
            ;;
    esac
}

execute_anonymization_retention() {
    local table_name=$1
    local retention_period=$2
    
    print_status "Executing anonymization retention for $table_name..."
    
    # Call anonymization service
    local anonymization_request=$(cat <<EOF
{
    "table_name": "$table_name",
    "method": "k_anonymity",
    "k": 5,
    "retention_mode": true,
    "retention_period_days": $retention_period,
    "respect_legal_holds": true
}
EOF
    )
    
    local response=$(curl -s -X POST "$ANONYMIZATION_SERVICE_URL/api/anonymize/table" \
        -H "Content-Type: application/json" \
        -d "$anonymization_request")
    
    local status=$(echo "$response" | jq -r '.status // "error"')
    
    if [[ "$status" == "success" ]]; then
        local processed_records=$(echo "$response" | jq -r '.processed_records // 0')
        print_status "Anonymization completed - Processed $processed_records records"
    else
        local error_message=$(echo "$response" | jq -r '.error // "Unknown error"')
        print_error "Anonymization failed: $error_message"
        return 1
    fi
}

execute_deletion_retention() {
    local table_name=$1
    local retention_period=$2
    
    print_status "Executing deletion retention for $table_name..."
    
    # This is a simplified implementation - production would have table-specific deletion logic
    local deletion_query
    case $table_name in
        "access_logs")
            deletion_query="DELETE FROM access_logs 
                          WHERE created_at < NOW() - INTERVAL '$retention_period days'
                          AND id NOT IN (
                              SELECT DISTINCT record_id FROM compliance.legal_holds 
                              WHERE table_name = '$table_name' AND status = 'ACTIVE'
                          );"
            ;;
        "temporary_uploads")
            deletion_query="DELETE FROM temporary_uploads 
                          WHERE created_at < NOW() - INTERVAL '$retention_period days';"
            ;;
        *)
            print_error "Deletion logic not implemented for table: $table_name"
            return 1
            ;;
    esac
    
    local deleted_count=$(psql "$COMPLIANCE_DB_URL" -t -c "$deletion_query")
    print_status "Deletion completed - Removed $deleted_count records"
}

# Legal hold management
manage_legal_hold() {
    local action=$1
    local table_name=$2
    local record_id=$3
    local hold_reason=$4
    local case_number=$5
    
    print_header "Managing Legal Hold: $action"
    
    case $action in
        "create")
            create_legal_hold "$table_name" "$record_id" "$hold_reason" "$case_number"
            ;;
        "release")
            release_legal_hold "$table_name" "$record_id" "$case_number"
            ;;
        "list")
            list_legal_holds "$table_name"
            ;;
        "check")
            check_legal_hold_status "$table_name" "$record_id"
            ;;
        *)
            print_error "Unknown legal hold action: $action"
            return 1
            ;;
    esac
}

create_legal_hold() {
    local table_name=$1
    local record_id=$2
    local hold_reason=$3
    local case_number=$4
    
    print_status "Creating legal hold for $table_name:$record_id"
    
    local hold_id=$(uuidgen)
    
    psql "$COMPLIANCE_DB_URL" -c \
        "INSERT INTO compliance.legal_holds (id, table_name, record_id, hold_reason, case_number, created_by, status)
         VALUES ('$hold_id', '$table_name', '$record_id', '$hold_reason', '$case_number', '$(whoami)', 'ACTIVE');"
    
    if [[ $? -eq 0 ]]; then
        print_status "Legal hold created - ID: $hold_id"
        
        # Log legal hold activity
        log_legal_hold_activity "create" "$table_name" "$record_id" "$case_number"
    else
        print_error "Failed to create legal hold"
        return 1
    fi
}

release_legal_hold() {
    local table_name=$1
    local record_id=$2
    local case_number=$3
    
    print_status "Releasing legal hold for $table_name:$record_id (Case: $case_number)"
    
    psql "$COMPLIANCE_DB_URL" -c \
        "UPDATE compliance.legal_holds 
         SET status = 'RELEASED', updated_at = NOW()
         WHERE table_name = '$table_name' 
         AND record_id = '$record_id' 
         AND case_number = '$case_number' 
         AND status = 'ACTIVE';"
    
    local updated_count=$(psql "$COMPLIANCE_DB_URL" -t -c "SELECT ROW_COUNT();")
    
    if [[ $updated_count -gt 0 ]]; then
        print_status "Legal hold released successfully"
        
        # Log legal hold activity
        log_legal_hold_activity "release" "$table_name" "$record_id" "$case_number"
    else
        print_warning "No active legal hold found to release"
    fi
}

# Retention reporting
generate_retention_report() {
    local report_type=$1
    local start_date=$2
    local end_date=$3
    
    print_header "Generating Retention Report: $report_type"
    
    local report_file="$RETENTION_REPORTS_PATH/retention_report_$(date +%Y%m%d_%H%M%S).json"
    
    case $report_type in
        "compliance_summary")
            generate_compliance_summary_report "$report_file" "$start_date" "$end_date"
            ;;
        "retention_activity")
            generate_retention_activity_report "$report_file" "$start_date" "$end_date"
            ;;
        "legal_hold_summary")
            generate_legal_hold_summary_report "$report_file" "$start_date" "$end_date"
            ;;
        "data_age_analysis")
            generate_data_age_analysis_report "$report_file"
            ;;
        *)
            print_error "Unknown report type: $report_type"
            return 1
            ;;
    esac
    
    print_status "Report generated: $report_file"
}

generate_compliance_summary_report() {
    local report_file=$1
    local start_date=$2
    local end_date=$3
    
    local compliance_data=$(psql "$COMPLIANCE_DB_URL" -t -c \
        "SELECT json_agg(
            json_build_object(
                'table_name', table_name,
                'retention_period_days', retention_period_days,
                'records_due_for_retention', records_due_for_retention,
                'records_on_legal_hold', records_on_legal_hold,
                'records_eligible_for_retention', records_eligible_for_retention,
                'anonymization_required', anonymization_required,
                'policy_reason', policy_reason
            )
         ) FROM compliance.retention_compliance_dashboard;")
    
    cat > "$report_file" <<EOF
{
    "report_type": "compliance_summary",
    "generated_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "period": {
        "start_date": "$start_date",
        "end_date": "$end_date"
    },
    "compliance_status": $compliance_data,
    "summary": {
        "total_tables_monitored": $(echo "$compliance_data" | jq '. | length'),
        "total_records_due": $(echo "$compliance_data" | jq '[.[] | .records_due_for_retention] | add'),
        "total_records_on_hold": $(echo "$compliance_data" | jq '[.[] | .records_on_legal_hold] | add'),
        "total_eligible_for_processing": $(echo "$compliance_data" | jq '[.[] | .records_eligible_for_retention] | add')
    }
}
EOF
}

# Utility functions
log_retention_activity() {
    local table_name=$1
    local processed_records=$2
    local anonymization_used=$3
    
    local activity_log=$(cat <<EOF
{
    "event_type": "retention_processing",
    "table_name": "$table_name",
    "processed_records": $processed_records,
    "anonymization_used": $anonymization_used,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "compliance_tags": ["retention", "data_lifecycle"]
}
EOF
    )
    
    # Send to audit logging
    curl -s -X POST "http://localhost:8080" \
        -H "Content-Type: application/json" \
        -d "$activity_log" > /dev/null
}

log_legal_hold_activity() {
    local action=$1
    local table_name=$2
    local record_id=$3
    local case_number=$4
    
    local activity_log=$(cat <<EOF
{
    "event_type": "legal_hold_$action",
    "table_name": "$table_name",
    "record_id": "$record_id",
    "case_number": "$case_number",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "compliance_tags": ["legal_hold", "litigation"]
}
EOF
    )
    
    # Send to audit logging
    curl -s -X POST "http://localhost:8080" \
        -H "Content-Type: application/json" \
        -d "$activity_log" > /dev/null
}

# Main function
main() {
    case $1 in
        "init")
            initialize_retention_framework
            ;;
        "execute")
            execute_retention_policy "$2" "$3"
            ;;
        "legal-hold")
            manage_legal_hold "$2" "$3" "$4" "$5" "$6"
            ;;
        "report")
            generate_retention_report "$2" "$3" "$4"
            ;;
        *)
            echo "Data Retention Manager"
            echo ""
            echo "Usage:"
            echo "  $0 init                                              - Initialize retention framework"
            echo "  $0 execute <table_name> [dry_run]                   - Execute retention policy"
            echo "  $0 legal-hold <action> <table> <record_id> <reason> <case> - Manage legal holds"
            echo "  $0 report <type> [start_date] [end_date]            - Generate retention report"
            echo ""
            echo "Examples:"
            echo "  $0 init"
            echo "  $0 execute users true"
            echo "  $0 legal-hold create users user123 'litigation hold' 'CASE-2024-001'"
            echo "  $0 legal-hold release users user123 'CASE-2024-001'"
            echo "  $0 report compliance_summary 2024-01-01 2024-03-31"
            ;;
    esac
}

main "$@"
