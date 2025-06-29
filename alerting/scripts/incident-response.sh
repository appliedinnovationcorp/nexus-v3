#!/bin/bash

set -e

# Incident Response Automation Script
# Automated incident detection, classification, and response coordination

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INCIDENT]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[INCIDENT RESPONSE]${NC} $1"
}

# Configuration
ONCALL_URL=${ONCALL_URL:-"http://localhost:8081"}
SLACK_WEBHOOK=${SLACK_WEBHOOK:-""}
ALERTMANAGER_URL=${ALERTMANAGER_URL:-"http://localhost:9093"}
GRAFANA_URL=${GRAFANA_URL:-"http://localhost:3000"}

# Incident classification and response
classify_incident() {
    local alert_name=$1
    local severity=$2
    local service=$3
    local description=$4
    
    print_header "Classifying incident: $alert_name"
    
    local priority="P2"  # Default priority
    local response_time="30m"
    local escalation_required=false
    
    # P0 Classification - Immediate response required
    if [[ "$severity" == "critical" ]] && [[ "$service" =~ (database|payment|auth|core) ]]; then
        priority="P0"
        response_time="0m"
        escalation_required=true
        print_status "Classified as P0 - IMMEDIATE RESPONSE REQUIRED"
    
    # P1 Classification - Urgent response required
    elif [[ "$severity" == "critical" ]] || [[ "$alert_name" =~ (ServiceDown|DatabaseDown|HighErrorRate) ]]; then
        priority="P1"
        response_time="5m"
        escalation_required=true
        print_status "Classified as P1 - URGENT RESPONSE REQUIRED"
    
    # P2 Classification - Standard response
    elif [[ "$severity" == "high" ]] || [[ "$alert_name" =~ (HighLatency|ResourceExhaustion) ]]; then
        priority="P2"
        response_time="30m"
        print_status "Classified as P2 - STANDARD RESPONSE"
    
    # P3 Classification - Low priority
    else
        priority="P3"
        response_time="2h"
        print_status "Classified as P3 - LOW PRIORITY"
    fi
    
    # Create incident record
    create_incident "$alert_name" "$priority" "$service" "$description" "$response_time" "$escalation_required"
}

create_incident() {
    local alert_name=$1
    local priority=$2
    local service=$3
    local description=$4
    local response_time=$5
    local escalation_required=$6
    
    print_header "Creating incident record"
    
    local incident_id=$(date +%Y%m%d-%H%M%S)-$(echo $alert_name | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Create incident data
    local incident_data=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "alert_name": "$alert_name",
    "priority": "$priority",
    "service": "$service",
    "description": "$description",
    "status": "open",
    "created_at": "$timestamp",
    "response_time_sla": "$response_time",
    "escalation_required": $escalation_required,
    "assigned_team": "$(determine_team "$service")",
    "war_room_channel": "#incident-$incident_id",
    "runbook_url": "https://runbooks.nexus-v3.local/$(echo $alert_name | tr '[:upper:]' '[:lower:]' | tr ' ' '-')",
    "dashboard_url": "$GRAFANA_URL/d/$service-dashboard",
    "logs_url": "http://localhost:5601/app/logs"
}
EOF
    )
    
    # Store incident record
    echo "$incident_data" > "/tmp/incident-$incident_id.json"
    
    print_status "Incident created: $incident_id"
    
    # Trigger incident response workflow
    trigger_incident_response "$incident_id" "$priority" "$escalation_required"
}

determine_team() {
    local service=$1
    
    case $service in
        *api*|*gateway*|*backend*)
            echo "backend"
            ;;
        *web*|*frontend*|*ui*)
            echo "frontend"
            ;;
        *database*|*postgres*|*mysql*|*redis*)
            echo "platform"
            ;;
        *auth*|*security*)
            echo "security"
            ;;
        *monitoring*|*prometheus*|*grafana*)
            echo "sre"
            ;;
        *)
            echo "platform"
            ;;
    esac
}

trigger_incident_response() {
    local incident_id=$1
    local priority=$2
    local escalation_required=$3
    
    print_header "Triggering incident response for $incident_id"
    
    case $priority in
        "P0")
            trigger_p0_response "$incident_id"
            ;;
        "P1")
            trigger_p1_response "$incident_id"
            ;;
        "P2")
            trigger_p2_response "$incident_id"
            ;;
        "P3")
            trigger_p3_response "$incident_id"
            ;;
    esac
    
    # Create war room if escalation required
    if [[ "$escalation_required" == "true" ]]; then
        create_war_room "$incident_id"
    fi
    
    # Start incident timeline
    start_incident_timeline "$incident_id"
}

trigger_p0_response() {
    local incident_id=$1
    
    print_status "🔥 TRIGGERING P0 INCIDENT RESPONSE"
    
    # Immediate notifications
    send_slack_notification "critical" "🚨 P0 INCIDENT - IMMEDIATE ATTENTION REQUIRED" "$incident_id" "@channel"
    
    # Page on-call engineer
    page_oncall_engineer "$incident_id" "P0"
    
    # Create war room immediately
    create_war_room "$incident_id"
    
    # Notify incident commander
    notify_incident_commander "$incident_id"
    
    # Start incident bridge
    start_incident_bridge "$incident_id"
    
    print_status "P0 response initiated for $incident_id"
}

trigger_p1_response() {
    local incident_id=$1
    
    print_status "🚨 TRIGGERING P1 INCIDENT RESPONSE"
    
    # Urgent notifications
    send_slack_notification "high" "🚨 P1 INCIDENT - URGENT RESPONSE REQUIRED" "$incident_id" ""
    
    # Page on-call engineer
    page_oncall_engineer "$incident_id" "P1"
    
    # Create war room
    create_war_room "$incident_id"
    
    print_status "P1 response initiated for $incident_id"
}

trigger_p2_response() {
    local incident_id=$1
    
    print_status "⚠️ TRIGGERING P2 INCIDENT RESPONSE"
    
    # Standard notifications
    send_slack_notification "medium" "⚠️ P2 INCIDENT - STANDARD RESPONSE" "$incident_id" ""
    
    # Notify assigned team
    notify_assigned_team "$incident_id"
    
    print_status "P2 response initiated for $incident_id"
}

trigger_p3_response() {
    local incident_id=$1
    
    print_status "ℹ️ TRIGGERING P3 INCIDENT RESPONSE"
    
    # Low priority notifications
    send_slack_notification "low" "ℹ️ P3 INCIDENT - LOW PRIORITY" "$incident_id" ""
    
    # Create ticket for follow-up
    create_followup_ticket "$incident_id"
    
    print_status "P3 response initiated for $incident_id"
}

send_slack_notification() {
    local severity=$1
    local title=$2
    local incident_id=$3
    local mention=$4
    
    if [[ -z "$SLACK_WEBHOOK" ]]; then
        print_warning "Slack webhook not configured - skipping Slack notification"
        return
    fi
    
    local incident_data=$(cat "/tmp/incident-$incident_id.json")
    local service=$(echo "$incident_data" | jq -r '.service')
    local description=$(echo "$incident_data" | jq -r '.description')
    local priority=$(echo "$incident_data" | jq -r '.priority')
    local war_room=$(echo "$incident_data" | jq -r '.war_room_channel')
    local runbook=$(echo "$incident_data" | jq -r '.runbook_url')
    local dashboard=$(echo "$incident_data" | jq -r '.dashboard_url')
    
    local slack_payload=$(cat <<EOF
{
    "text": "$mention $title",
    "attachments": [
        {
            "color": "$(get_slack_color "$severity")",
            "fields": [
                {
                    "title": "Incident ID",
                    "value": "$incident_id",
                    "short": true
                },
                {
                    "title": "Priority",
                    "value": "$priority",
                    "short": true
                },
                {
                    "title": "Service",
                    "value": "$service",
                    "short": true
                },
                {
                    "title": "War Room",
                    "value": "$war_room",
                    "short": true
                },
                {
                    "title": "Description",
                    "value": "$description",
                    "short": false
                }
            ],
            "actions": [
                {
                    "type": "button",
                    "text": "Acknowledge",
                    "url": "$ONCALL_URL/incidents/$incident_id/ack"
                },
                {
                    "type": "button",
                    "text": "Dashboard",
                    "url": "$dashboard"
                },
                {
                    "type": "button",
                    "text": "Runbook",
                    "url": "$runbook"
                }
            ]
        }
    ]
}
EOF
    )
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$slack_payload" \
        "$SLACK_WEBHOOK" 2>/dev/null || print_warning "Failed to send Slack notification"
}

get_slack_color() {
    local severity=$1
    
    case $severity in
        "critical") echo "danger" ;;
        "high") echo "warning" ;;
        "medium") echo "#ffaa00" ;;
        "low") echo "good" ;;
        *) echo "#cccccc" ;;
    esac
}

create_war_room() {
    local incident_id=$1
    
    print_status "Creating war room for incident $incident_id"
    
    # In a real implementation, this would create a Slack channel or Teams room
    # For now, we'll simulate the war room creation
    
    local war_room_data=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "war_room_channel": "#incident-$incident_id",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "participants": [],
    "status": "active",
    "bridge_url": "https://meet.nexus-v3.local/incident-$incident_id"
}
EOF
    )
    
    echo "$war_room_data" > "/tmp/war-room-$incident_id.json"
    
    print_status "War room created: #incident-$incident_id"
}

page_oncall_engineer() {
    local incident_id=$1
    local priority=$2
    
    print_status "Paging on-call engineer for $priority incident: $incident_id"
    
    # Send to Grafana OnCall
    local oncall_payload=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "priority": "$priority",
    "message": "Incident $incident_id requires immediate attention",
    "escalation_policy": "primary-oncall"
}
EOF
    )
    
    curl -X POST "$ONCALL_URL/api/v1/incidents" \
        -H "Content-Type: application/json" \
        -d "$oncall_payload" 2>/dev/null || print_warning "Failed to page on-call engineer"
    
    print_status "On-call engineer paged for incident $incident_id"
}

start_incident_timeline() {
    local incident_id=$1
    
    print_status "Starting incident timeline for $incident_id"
    
    local timeline_entry=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "event": "incident_created",
    "description": "Incident created and response initiated",
    "actor": "incident-response-system"
}
EOF
    )
    
    echo "$timeline_entry" > "/tmp/timeline-$incident_id.json"
    
    print_status "Incident timeline started for $incident_id"
}

# Incident resolution and post-mortem
resolve_incident() {
    local incident_id=$1
    local resolution_summary=$2
    
    print_header "Resolving incident: $incident_id"
    
    # Update incident status
    local resolution_data=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "status": "resolved",
    "resolved_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resolution_summary": "$resolution_summary",
    "resolved_by": "$(whoami)"
}
EOF
    )
    
    echo "$resolution_data" > "/tmp/resolution-$incident_id.json"
    
    # Send resolution notification
    send_resolution_notification "$incident_id" "$resolution_summary"
    
    # Schedule post-mortem if required
    schedule_postmortem "$incident_id"
    
    print_status "Incident $incident_id resolved"
}

send_resolution_notification() {
    local incident_id=$1
    local resolution_summary=$2
    
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        local slack_payload=$(cat <<EOF
{
    "text": "✅ Incident Resolved: $incident_id",
    "attachments": [
        {
            "color": "good",
            "fields": [
                {
                    "title": "Incident ID",
                    "value": "$incident_id",
                    "short": true
                },
                {
                    "title": "Resolution Summary",
                    "value": "$resolution_summary",
                    "short": false
                }
            ]
        }
    ]
}
EOF
        )
        
        curl -X POST -H 'Content-type: application/json' \
            --data "$slack_payload" \
            "$SLACK_WEBHOOK" 2>/dev/null
    fi
}

schedule_postmortem() {
    local incident_id=$1
    
    # Check if post-mortem is required (P0/P1 incidents)
    local incident_data=$(cat "/tmp/incident-$incident_id.json")
    local priority=$(echo "$incident_data" | jq -r '.priority')
    
    if [[ "$priority" =~ ^(P0|P1)$ ]]; then
        print_status "Scheduling post-mortem for $priority incident: $incident_id"
        
        local postmortem_data=$(cat <<EOF
{
    "incident_id": "$incident_id",
    "postmortem_required": true,
    "scheduled_date": "$(date -u -d '+3 days' +%Y-%m-%d)",
    "facilitator": "sre-team",
    "participants": ["incident-commander", "on-call-engineer", "service-owner"]
}
EOF
        )
        
        echo "$postmortem_data" > "/tmp/postmortem-$incident_id.json"
        
        print_status "Post-mortem scheduled for incident $incident_id"
    fi
}

# Chaos engineering integration
handle_chaos_incident() {
    local experiment_name=$1
    local chaos_status=$2
    local target_service=$3
    
    print_header "Handling chaos engineering incident"
    
    if [[ "$chaos_status" == "failed" ]]; then
        print_status "Chaos experiment failed - creating incident"
        
        classify_incident "ChaosExperimentFailed" "high" "$target_service" \
            "Chaos experiment $experiment_name failed on $target_service"
    elif [[ "$chaos_status" == "system_degraded" ]]; then
        print_status "System degraded during chaos experiment"
        
        classify_incident "SystemNotResilientToChaos" "critical" "$target_service" \
            "System showing poor resilience during chaos experiment $experiment_name"
    fi
}

# Performance budget violation handling
handle_performance_violation() {
    local metric_name=$1
    local current_value=$2
    local budget_value=$3
    local service=$4
    
    print_header "Handling performance budget violation"
    
    local regression_percentage=$(echo "scale=2; (($current_value - $budget_value) / $budget_value) * 100" | bc)
    
    classify_incident "PerformanceBudgetViolation" "warning" "$service" \
        "Performance metric $metric_name exceeded budget by $regression_percentage%"
}

# Main function
main() {
    case $1 in
        "classify")
            classify_incident "$2" "$3" "$4" "$5"
            ;;
        "resolve")
            resolve_incident "$2" "$3"
            ;;
        "chaos")
            handle_chaos_incident "$2" "$3" "$4"
            ;;
        "performance")
            handle_performance_violation "$2" "$3" "$4" "$5"
            ;;
        *)
            echo "Incident Response Automation"
            echo ""
            echo "Usage:"
            echo "  $0 classify <alert_name> <severity> <service> <description>"
            echo "  $0 resolve <incident_id> <resolution_summary>"
            echo "  $0 chaos <experiment_name> <status> <target_service>"
            echo "  $0 performance <metric> <current> <budget> <service>"
            echo ""
            echo "Examples:"
            echo "  $0 classify 'DatabaseDown' 'critical' 'postgres' 'Database connection failed'"
            echo "  $0 resolve '20241201-143022-databasedown' 'Database restarted and connection restored'"
            echo "  $0 chaos 'pod-delete-experiment' 'failed' 'api-gateway'"
            echo "  $0 performance 'response_time' '800' '500' 'api-gateway'"
            ;;
    esac
}

main "$@"
