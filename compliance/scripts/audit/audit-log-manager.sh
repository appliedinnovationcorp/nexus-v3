#!/bin/bash

set -e

# Audit Log Manager
# Comprehensive audit logging, monitoring, and compliance reporting

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[AUDIT]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[AUDIT LOG MANAGER]${NC} $1"
}

# Configuration
ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-"http://localhost:9200"}
KIBANA_URL=${KIBANA_URL:-"http://localhost:5601"}
COMPLIANCE_DB_URL=${DATABASE_URL:-"postgresql://compliance_admin:compliance_secure_pass@localhost:5432/compliance_db"}
AUDIT_SERVICE_URL=${AUDIT_SERVICE_URL:-"http://localhost:3023"}

# Initialize audit logging infrastructure
initialize_audit_logging() {
    print_header "Initializing Audit Logging Infrastructure"
    
    # Create Elasticsearch index templates
    create_audit_index_templates
    
    # Setup Kibana dashboards
    setup_audit_dashboards
    
    # Initialize audit log retention policies
    setup_audit_retention_policies
    
    # Configure audit log monitoring
    setup_audit_monitoring
    
    print_status "Audit logging infrastructure initialized successfully"
}

create_audit_index_templates() {
    print_status "Creating Elasticsearch index templates..."
    
    # Audit events index template
    curl -X PUT "$ELASTICSEARCH_URL/_index_template/audit-logs" \
        -H "Content-Type: application/json" \
        -d '{
            "index_patterns": ["audit-logs-*"],
            "template": {
                "settings": {
                    "number_of_shards": 3,
                    "number_of_replicas": 1,
                    "index.lifecycle.name": "audit-logs-policy",
                    "index.lifecycle.rollover_alias": "audit-logs"
                },
                "mappings": {
                    "properties": {
                        "@timestamp": {"type": "date"},
                        "event_type": {"type": "keyword"},
                        "user_id": {"type": "keyword"},
                        "session_id": {"type": "keyword"},
                        "resource": {"type": "keyword"},
                        "action": {"type": "keyword"},
                        "result": {"type": "keyword"},
                        "ip_address": {"type": "ip"},
                        "user_agent": {"type": "text"},
                        "request_id": {"type": "keyword"},
                        "correlation_id": {"type": "keyword"},
                        "event_data": {"type": "object"},
                        "risk_score": {"type": "integer"},
                        "compliance_tags": {"type": "keyword"},
                        "data_classification": {"type": "keyword"},
                        "retention_period": {"type": "integer"},
                        "legal_hold": {"type": "boolean"}
                    }
                }
            }
        }' > /dev/null
    
    # Compliance events index template
    curl -X PUT "$ELASTICSEARCH_URL/_index_template/compliance-logs" \
        -H "Content-Type: application/json" \
        -d '{
            "index_patterns": ["compliance-logs-*"],
            "template": {
                "settings": {
                    "number_of_shards": 2,
                    "number_of_replicas": 1,
                    "index.lifecycle.name": "compliance-logs-policy"
                },
                "mappings": {
                    "properties": {
                        "@timestamp": {"type": "date"},
                        "compliance_type": {"type": "keyword"},
                        "regulation": {"type": "keyword"},
                        "control_id": {"type": "keyword"},
                        "event_category": {"type": "keyword"},
                        "severity": {"type": "keyword"},
                        "description": {"type": "text"},
                        "affected_records": {"type": "integer"},
                        "data_subject_id": {"type": "keyword"},
                        "remediation_required": {"type": "boolean"},
                        "notification_required": {"type": "boolean"}
                    }
                }
            }
        }' > /dev/null
    
    print_status "Index templates created successfully"
}

setup_audit_dashboards() {
    print_status "Setting up Kibana audit dashboards..."
    
    # Create audit overview dashboard
    local dashboard_config="/tmp/audit_dashboard.json"
    
    cat > "$dashboard_config" <<'EOF'
{
    "version": "8.0.0",
    "objects": [
        {
            "id": "audit-overview-dashboard",
            "type": "dashboard",
            "attributes": {
                "title": "Audit Overview Dashboard",
                "description": "Comprehensive audit logging overview",
                "panelsJSON": "[{\"version\":\"8.0.0\",\"gridData\":{\"x\":0,\"y\":0,\"w\":24,\"h\":15},\"panelIndex\":\"1\",\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"}]",
                "timeRestore": false,
                "kibanaSavedObjectMeta": {
                    "searchSourceJSON": "{\"query\":{\"match_all\":{}},\"filter\":[]}"
                }
            }
        }
    ]
}
EOF
    
    # Import dashboard (simplified - in production would use Kibana API)
    print_status "Dashboard configuration prepared: $dashboard_config"
}

setup_audit_retention_policies() {
    print_status "Setting up audit log retention policies..."
    
    # Create ILM policy for audit logs
    curl -X PUT "$ELASTICSEARCH_URL/_ilm/policy/audit-logs-policy" \
        -H "Content-Type: application/json" \
        -d '{
            "policy": {
                "phases": {
                    "hot": {
                        "actions": {
                            "rollover": {
                                "max_size": "10GB",
                                "max_age": "7d"
                            }
                        }
                    },
                    "warm": {
                        "min_age": "7d",
                        "actions": {
                            "allocate": {
                                "number_of_replicas": 0
                            }
                        }
                    },
                    "cold": {
                        "min_age": "30d",
                        "actions": {
                            "allocate": {
                                "number_of_replicas": 0
                            }
                        }
                    },
                    "delete": {
                        "min_age": "2555d"
                    }
                }
            }
        }' > /dev/null
    
    # Create compliance logs retention policy
    curl -X PUT "$ELASTICSEARCH_URL/_ilm/policy/compliance-logs-policy" \
        -H "Content-Type: application/json" \
        -d '{
            "policy": {
                "phases": {
                    "hot": {
                        "actions": {
                            "rollover": {
                                "max_size": "5GB",
                                "max_age": "30d"
                            }
                        }
                    },
                    "warm": {
                        "min_age": "30d",
                        "actions": {
                            "allocate": {
                                "number_of_replicas": 0
                            }
                        }
                    },
                    "delete": {
                        "min_age": "3650d"
                    }
                }
            }
        }' > /dev/null
    
    print_status "Retention policies configured successfully"
}

setup_audit_monitoring() {
    print_status "Setting up audit log monitoring..."
    
    # Create audit log monitoring rules
    local monitoring_rules="/tmp/audit_monitoring_rules.json"
    
    cat > "$monitoring_rules" <<'EOF'
{
    "rules": [
        {
            "name": "High Risk Authentication Events",
            "query": "event_type:authentication AND result:failure AND risk_score:>80",
            "threshold": 5,
            "timeframe": "5m",
            "action": "alert",
            "severity": "high"
        },
        {
            "name": "Privileged Access Monitoring",
            "query": "action:admin_access OR resource:admin_panel",
            "threshold": 1,
            "timeframe": "1m",
            "action": "log",
            "severity": "medium"
        },
        {
            "name": "Data Export Activities",
            "query": "action:data_export OR action:bulk_download",
            "threshold": 1,
            "timeframe": "1m",
            "action": "alert",
            "severity": "medium"
        },
        {
            "name": "Compliance Violations",
            "query": "compliance_tags:violation",
            "threshold": 1,
            "timeframe": "1m",
            "action": "alert",
            "severity": "high"
        }
    ]
}
EOF
    
    print_status "Monitoring rules configured: $monitoring_rules"
}

# Audit log ingestion and processing
ingest_audit_event() {
    local event_type=$1
    local user_id=$2
    local resource=$3
    local action=$4
    local result=$5
    local additional_data=$6
    
    print_status "Ingesting audit event: $event_type"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local event_id=$(uuidgen)
    local correlation_id=${CORRELATION_ID:-$(uuidgen)}
    
    # Calculate risk score
    local risk_score=$(calculate_risk_score "$event_type" "$action" "$result")
    
    # Determine compliance tags
    local compliance_tags=$(determine_compliance_tags "$event_type" "$resource" "$action")
    
    # Create audit event
    local audit_event=$(cat <<EOF
{
    "@timestamp": "$timestamp",
    "event_id": "$event_id",
    "event_type": "$event_type",
    "user_id": "$user_id",
    "session_id": "${SESSION_ID:-unknown}",
    "resource": "$resource",
    "action": "$action",
    "result": "$result",
    "ip_address": "${CLIENT_IP:-unknown}",
    "user_agent": "${USER_AGENT:-unknown}",
    "request_id": "${REQUEST_ID:-unknown}",
    "correlation_id": "$correlation_id",
    "event_data": $additional_data,
    "risk_score": $risk_score,
    "compliance_tags": $compliance_tags,
    "data_classification": "$(classify_data_sensitivity "$resource")",
    "retention_period": $(get_retention_period "$event_type"),
    "legal_hold": $(check_legal_hold "$user_id" "$resource")
}
EOF
    )
    
    # Send to Elasticsearch
    curl -X POST "$ELASTICSEARCH_URL/audit-logs-$(date +%Y.%m.%d)/_doc" \
        -H "Content-Type: application/json" \
        -d "$audit_event" > /dev/null
    
    # Store in compliance database for long-term retention
    store_audit_event_db "$audit_event"
    
    # Check for real-time alerts
    check_audit_alerts "$audit_event"
    
    print_status "Audit event ingested successfully - ID: $event_id"
}

calculate_risk_score() {
    local event_type=$1
    local action=$2
    local result=$3
    
    local base_score=10
    
    # Event type scoring
    case $event_type in
        "authentication") base_score=$((base_score + 20)) ;;
        "authorization") base_score=$((base_score + 15)) ;;
        "data_access") base_score=$((base_score + 25)) ;;
        "admin_action") base_score=$((base_score + 30)) ;;
        "system_change") base_score=$((base_score + 35)) ;;
    esac
    
    # Action scoring
    case $action in
        "login"|"logout") base_score=$((base_score + 5)) ;;
        "data_export"|"bulk_download") base_score=$((base_score + 40)) ;;
        "user_create"|"user_delete") base_score=$((base_score + 25)) ;;
        "permission_change") base_score=$((base_score + 30)) ;;
    esac
    
    # Result scoring
    case $result in
        "failure"|"error") base_score=$((base_score + 20)) ;;
        "success") base_score=$((base_score + 0)) ;;
    esac
    
    # Cap at 100
    if [[ $base_score -gt 100 ]]; then
        base_score=100
    fi
    
    echo $base_score
}

determine_compliance_tags() {
    local event_type=$1
    local resource=$2
    local action=$3
    
    local tags=()
    
    # GDPR tags
    if [[ "$resource" == *"personal_data"* || "$action" == *"data_subject"* ]]; then
        tags+=("gdpr")
    fi
    
    # SOC 2 tags
    if [[ "$event_type" == "authentication" || "$event_type" == "authorization" ]]; then
        tags+=("soc2_security")
    fi
    
    if [[ "$resource" == *"system"* || "$action" == *"admin"* ]]; then
        tags+=("soc2_availability")
    fi
    
    # PCI DSS tags
    if [[ "$resource" == *"payment"* || "$resource" == *"card"* ]]; then
        tags+=("pci_dss")
    fi
    
    # HIPAA tags
    if [[ "$resource" == *"health"* || "$resource" == *"medical"* ]]; then
        tags+=("hipaa")
    fi
    
    # Convert array to JSON format
    local json_tags=$(printf '%s\n' "${tags[@]}" | jq -R . | jq -s .)
    echo "$json_tags"
}

store_audit_event_db() {
    local audit_event=$1
    
    # Extract key fields for database storage
    local event_type=$(echo "$audit_event" | jq -r '.event_type')
    local user_id=$(echo "$audit_event" | jq -r '.user_id')
    local resource=$(echo "$audit_event" | jq -r '.resource')
    local action=$(echo "$audit_event" | jq -r '.action')
    local result=$(echo "$audit_event" | jq -r '.result')
    local timestamp=$(echo "$audit_event" | jq -r '."@timestamp"')
    local risk_score=$(echo "$audit_event" | jq -r '.risk_score')
    local compliance_tags=$(echo "$audit_event" | jq -r '.compliance_tags')
    
    # Insert into database
    psql "$COMPLIANCE_DB_URL" -c \
        "INSERT INTO audit.events (event_type, user_id, resource, action, result, risk_score, compliance_tags, event_data, created_at)
         VALUES ('$event_type', '$user_id', '$resource', '$action', '$result', $risk_score, '$compliance_tags', '$audit_event', '$timestamp');" > /dev/null
}

# Audit log analysis and reporting
analyze_audit_patterns() {
    local analysis_type=$1
    local time_range=$2
    
    print_header "Analyzing Audit Patterns: $analysis_type"
    
    case $analysis_type in
        "failed_logins")
            analyze_failed_logins "$time_range"
            ;;
        "privilege_escalation")
            analyze_privilege_escalation "$time_range"
            ;;
        "data_access_patterns")
            analyze_data_access_patterns "$time_range"
            ;;
        "anomalous_behavior")
            analyze_anomalous_behavior "$time_range"
            ;;
        *)
            print_error "Unknown analysis type: $analysis_type"
            return 1
            ;;
    esac
}

analyze_failed_logins() {
    local time_range=$1
    
    print_status "Analyzing failed login patterns..."
    
    local query='{
        "query": {
            "bool": {
                "must": [
                    {"term": {"event_type": "authentication"}},
                    {"term": {"result": "failure"}},
                    {"range": {"@timestamp": {"gte": "now-'$time_range'"}}}
                ]
            }
        },
        "aggs": {
            "failed_by_user": {
                "terms": {"field": "user_id", "size": 10}
            },
            "failed_by_ip": {
                "terms": {"field": "ip_address", "size": 10}
            }
        }
    }'
    
    local results=$(curl -s -X POST "$ELASTICSEARCH_URL/audit-logs-*/_search" \
        -H "Content-Type: application/json" \
        -d "$query")
    
    local total_failures=$(echo "$results" | jq -r '.hits.total.value')
    print_status "Total failed logins in $time_range: $total_failures"
    
    # Generate alert if threshold exceeded
    if [[ $total_failures -gt 100 ]]; then
        generate_security_alert "high_failed_login_volume" "$total_failures failed logins in $time_range"
    fi
}

analyze_privilege_escalation() {
    local time_range=$1
    
    print_status "Analyzing privilege escalation patterns..."
    
    local query='{
        "query": {
            "bool": {
                "must": [
                    {"terms": {"action": ["permission_change", "role_assignment", "admin_access"]}},
                    {"range": {"@timestamp": {"gte": "now-'$time_range'"}}}
                ]
            }
        },
        "aggs": {
            "escalation_by_user": {
                "terms": {"field": "user_id", "size": 10}
            }
        }
    }'
    
    local results=$(curl -s -X POST "$ELASTICSEARCH_URL/audit-logs-*/_search" \
        -H "Content-Type: application/json" \
        -d "$query")
    
    local total_escalations=$(echo "$results" | jq -r '.hits.total.value')
    print_status "Total privilege escalation events in $time_range: $total_escalations"
}

# Compliance reporting
generate_audit_compliance_report() {
    local report_type=$1
    local start_date=$2
    local end_date=$3
    local output_format=${4:-"json"}
    
    print_header "Generating Audit Compliance Report: $report_type"
    
    local report_file="/tmp/audit_compliance_report_$(date +%Y%m%d_%H%M%S).$output_format"
    
    case $report_type in
        "gdpr_audit_trail")
            generate_gdpr_audit_report "$report_file" "$start_date" "$end_date"
            ;;
        "soc2_audit_evidence")
            generate_soc2_audit_report "$report_file" "$start_date" "$end_date"
            ;;
        "security_incidents")
            generate_security_incident_report "$report_file" "$start_date" "$end_date"
            ;;
        "access_review")
            generate_access_review_report "$report_file" "$start_date" "$end_date"
            ;;
        *)
            print_error "Unknown report type: $report_type"
            return 1
            ;;
    esac
    
    print_status "Report generated: $report_file"
}

generate_gdpr_audit_report() {
    local report_file=$1
    local start_date=$2
    local end_date=$3
    
    local query='{
        "query": {
            "bool": {
                "must": [
                    {"terms": {"compliance_tags": ["gdpr"]}},
                    {"range": {"@timestamp": {"gte": "'$start_date'", "lte": "'$end_date'"}}}
                ]
            }
        },
        "aggs": {
            "events_by_type": {
                "terms": {"field": "event_type"}
            },
            "data_subject_requests": {
                "filter": {"term": {"action": "data_subject_request"}},
                "aggs": {
                    "request_types": {
                        "terms": {"field": "event_data.request_type"}
                    }
                }
            }
        }
    }'
    
    local results=$(curl -s -X POST "$ELASTICSEARCH_URL/audit-logs-*/_search" \
        -H "Content-Type: application/json" \
        -d "$query")
    
    # Format report
    cat > "$report_file" <<EOF
{
    "report_type": "gdpr_audit_trail",
    "period": {
        "start_date": "$start_date",
        "end_date": "$end_date"
    },
    "generated_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "summary": {
        "total_gdpr_events": $(echo "$results" | jq -r '.hits.total.value'),
        "events_by_type": $(echo "$results" | jq -r '.aggregations.events_by_type.buckets'),
        "data_subject_requests": $(echo "$results" | jq -r '.aggregations.data_subject_requests.request_types.buckets')
    },
    "events": $(echo "$results" | jq -r '.hits.hits')
}
EOF
}

# Audit log integrity verification
verify_audit_integrity() {
    local verification_type=$1
    local time_range=$2
    
    print_header "Verifying Audit Log Integrity: $verification_type"
    
    case $verification_type in
        "hash_verification")
            verify_log_hashes "$time_range"
            ;;
        "sequence_verification")
            verify_log_sequence "$time_range"
            ;;
        "tamper_detection")
            detect_log_tampering "$time_range"
            ;;
        *)
            print_error "Unknown verification type: $verification_type"
            return 1
            ;;
    esac
}

verify_log_hashes() {
    local time_range=$1
    
    print_status "Verifying audit log hashes for $time_range..."
    
    # Get logs with hash verification
    local query='{
        "query": {
            "range": {"@timestamp": {"gte": "now-'$time_range'"}}
        },
        "sort": [{"@timestamp": {"order": "asc"}}],
        "_source": ["event_id", "@timestamp", "hash", "previous_hash"]
    }'
    
    local results=$(curl -s -X POST "$ELASTICSEARCH_URL/audit-logs-*/_search?size=1000" \
        -H "Content-Type: application/json" \
        -d "$query")
    
    local total_logs=$(echo "$results" | jq -r '.hits.total.value')
    local verified_logs=0
    local tampered_logs=0
    
    # Simplified hash verification (in production, implement proper hash chain verification)
    echo "$results" | jq -r '.hits.hits[]._source' | while read -r log_entry; do
        local event_id=$(echo "$log_entry" | jq -r '.event_id')
        local hash=$(echo "$log_entry" | jq -r '.hash // empty')
        
        if [[ -n "$hash" ]]; then
            verified_logs=$((verified_logs + 1))
        else
            tampered_logs=$((tampered_logs + 1))
            print_warning "Missing hash for event: $event_id"
        fi
    done
    
    print_status "Hash verification completed"
    print_status "Total logs: $total_logs"
    print_status "Verified logs: $verified_logs"
    print_status "Potentially tampered logs: $tampered_logs"
    
    if [[ $tampered_logs -gt 0 ]]; then
        generate_security_alert "audit_log_tampering" "$tampered_logs logs show signs of tampering"
    fi
}

generate_security_alert() {
    local alert_type=$1
    local description=$2
    
    print_warning "SECURITY ALERT: $alert_type - $description"
    
    # Send alert to security team
    local alert_data=$(cat <<EOF
{
    "alert_type": "$alert_type",
    "description": "$description",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "severity": "high",
    "source": "audit_log_manager"
}
EOF
    )
    
    # Send to alerting system
    curl -s -X POST "$AUDIT_SERVICE_URL/api/alerts" \
        -H "Content-Type: application/json" \
        -d "$alert_data" > /dev/null
}

# Main function
main() {
    case $1 in
        "init")
            initialize_audit_logging
            ;;
        "ingest")
            ingest_audit_event "$2" "$3" "$4" "$5" "$6" "$7"
            ;;
        "analyze")
            analyze_audit_patterns "$2" "$3"
            ;;
        "report")
            generate_audit_compliance_report "$2" "$3" "$4" "$5"
            ;;
        "verify")
            verify_audit_integrity "$2" "$3"
            ;;
        *)
            echo "Audit Log Manager"
            echo ""
            echo "Usage:"
            echo "  $0 init                                           - Initialize audit logging"
            echo "  $0 ingest <type> <user> <resource> <action> <result> <data> - Ingest audit event"
            echo "  $0 analyze <type> <time_range>                   - Analyze audit patterns"
            echo "  $0 report <type> <start_date> <end_date> [format] - Generate compliance report"
            echo "  $0 verify <type> <time_range>                    - Verify audit integrity"
            echo ""
            echo "Examples:"
            echo "  $0 init"
            echo "  $0 ingest authentication user123 login_page login success '{\"ip\":\"192.168.1.1\"}'"
            echo "  $0 analyze failed_logins 24h"
            echo "  $0 report gdpr_audit_trail 2024-01-01 2024-01-31 json"
            echo "  $0 verify hash_verification 7d"
            ;;
    esac
}

main "$@"
