"""
Data Retention and Lifecycle Management DAG
Implements automated data retention policies and compliance workflows
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.providers.http.operators.http import SimpleHttpOperator
from airflow.models import Variable
import logging
import json

# Default arguments
default_args = {
    'owner': 'compliance-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'email': ['compliance@company.com']
}

# DAG definition
dag = DAG(
    'data_retention_lifecycle',
    default_args=default_args,
    description='Automated data retention and lifecycle management',
    schedule_interval='@daily',
    catchup=False,
    max_active_runs=1,
    tags=['compliance', 'gdpr', 'data-retention']
)

def identify_expired_data(**context):
    """Identify data that has exceeded retention periods"""
    
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    
    # Define retention policies
    retention_policies = {
        'user_activity_logs': 90,      # 90 days
        'session_data': 30,            # 30 days
        'audit_logs': 2555,            # 7 years
        'user_profiles': 1095,         # 3 years after account deletion
        'transaction_logs': 2555,      # 7 years
        'marketing_data': 365,         # 1 year
        'support_tickets': 1095,       # 3 years
        'backup_data': 365,            # 1 year
        'temp_files': 7,               # 7 days
        'cache_data': 1                # 1 day
    }
    
    expired_data = {}
    
    for table_name, retention_days in retention_policies.items():
        try:
            # Query to find expired records
            sql = f"""
            SELECT COUNT(*) as expired_count,
                   MIN(created_at) as oldest_record,
                   MAX(created_at) as newest_expired
            FROM {table_name}
            WHERE created_at < NOW() - INTERVAL '{retention_days} days'
            """
            
            result = postgres_hook.get_first(sql)
            
            if result and result[0] > 0:
                expired_data[table_name] = {
                    'count': result[0],
                    'oldest_record': result[1].isoformat() if result[1] else None,
                    'newest_expired': result[2].isoformat() if result[2] else None,
                    'retention_days': retention_days
                }
                
                logging.info(f"Found {result[0]} expired records in {table_name}")
            
        except Exception as e:
            logging.error(f"Error checking {table_name}: {str(e)}")
    
    # Store results for downstream tasks
    context['task_instance'].xcom_push(key='expired_data', value=expired_data)
    
    return expired_data

def check_legal_holds(**context):
    """Check for legal holds that prevent data deletion"""
    
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    expired_data = context['task_instance'].xcom_pull(key='expired_data')
    
    legal_holds = {}
    
    # Query active legal holds
    sql = """
    SELECT table_name, record_id, hold_reason, created_by, created_at
    FROM legal_holds
    WHERE status = 'ACTIVE'
    AND (expiration_date IS NULL OR expiration_date > NOW())
    """
    
    holds = postgres_hook.get_records(sql)
    
    for hold in holds:
        table_name, record_id, reason, created_by, created_at = hold
        
        if table_name not in legal_holds:
            legal_holds[table_name] = []
        
        legal_holds[table_name].append({
            'record_id': record_id,
            'reason': reason,
            'created_by': created_by,
            'created_at': created_at.isoformat()
        })
    
    # Filter expired data to exclude records under legal hold
    filtered_expired_data = {}
    
    for table_name, data in expired_data.items():
        if table_name in legal_holds:
            logging.warning(f"Legal hold exists for {table_name}, skipping deletion")
            continue
        
        filtered_expired_data[table_name] = data
    
    context['task_instance'].xcom_push(key='filtered_expired_data', value=filtered_expired_data)
    context['task_instance'].xcom_push(key='legal_holds', value=legal_holds)
    
    return filtered_expired_data

def anonymize_before_deletion(**context):
    """Anonymize data before deletion for compliance"""
    
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    filtered_data = context['task_instance'].xcom_pull(key='filtered_expired_data')
    
    anonymization_results = {}
    
    # Define fields that need anonymization before deletion
    anonymization_config = {
        'user_profiles': ['email', 'first_name', 'last_name', 'phone', 'address'],
        'user_activity_logs': ['user_id', 'ip_address', 'user_agent'],
        'transaction_logs': ['user_id', 'payment_method', 'billing_address'],
        'support_tickets': ['user_id', 'email', 'phone', 'description']
    }
    
    for table_name, data in filtered_data.items():
        if table_name in anonymization_config:
            fields_to_anonymize = anonymization_config[table_name]
            
            try:
                # Create anonymization SQL
                set_clauses = []
                for field in fields_to_anonymize:
                    if field in ['email']:
                        set_clauses.append(f"{field} = 'anonymized_' || generate_random_uuid() || '@deleted.local'")
                    elif field in ['first_name', 'last_name']:
                        set_clauses.append(f"{field} = 'DELETED'")
                    elif field in ['phone']:
                        set_clauses.append(f"{field} = '000-000-0000'")
                    elif field in ['ip_address']:
                        set_clauses.append(f"{field} = '0.0.0.0'")
                    else:
                        set_clauses.append(f"{field} = 'ANONYMIZED'")
                
                if set_clauses:
                    retention_days = data['retention_days']
                    sql = f"""
                    UPDATE {table_name}
                    SET {', '.join(set_clauses)},
                        anonymized_at = NOW(),
                        anonymization_reason = 'DATA_RETENTION_POLICY'
                    WHERE created_at < NOW() - INTERVAL '{retention_days} days'
                    AND anonymized_at IS NULL
                    """
                    
                    result = postgres_hook.run(sql)
                    
                    anonymization_results[table_name] = {
                        'anonymized': True,
                        'fields': fields_to_anonymize,
                        'sql_executed': sql
                    }
                    
                    logging.info(f"Anonymized expired records in {table_name}")
                
            except Exception as e:
                logging.error(f"Error anonymizing {table_name}: {str(e)}")
                anonymization_results[table_name] = {
                    'anonymized': False,
                    'error': str(e)
                }
    
    context['task_instance'].xcom_push(key='anonymization_results', value=anonymization_results)
    
    return anonymization_results

def create_deletion_manifest(**context):
    """Create manifest of data to be deleted for audit purposes"""
    
    filtered_data = context['task_instance'].xcom_pull(key='filtered_expired_data')
    anonymization_results = context['task_instance'].xcom_pull(key='anonymization_results')
    
    manifest = {
        'deletion_date': datetime.now().isoformat(),
        'deletion_reason': 'DATA_RETENTION_POLICY',
        'tables_affected': [],
        'total_records_to_delete': 0,
        'anonymization_performed': bool(anonymization_results),
        'legal_holds_checked': True
    }
    
    for table_name, data in filtered_data.items():
        table_info = {
            'table_name': table_name,
            'records_to_delete': data['count'],
            'retention_period_days': data['retention_days'],
            'oldest_record': data['oldest_record'],
            'newest_expired': data['newest_expired'],
            'anonymized_before_deletion': table_name in anonymization_results
        }
        
        manifest['tables_affected'].append(table_info)
        manifest['total_records_to_delete'] += data['count']
    
    # Store manifest in database for audit trail
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    
    insert_sql = """
    INSERT INTO data_deletion_manifests (
        deletion_date, manifest_data, total_records, status
    ) VALUES (%s, %s, %s, %s)
    RETURNING id
    """
    
    manifest_id = postgres_hook.get_first(
        insert_sql,
        parameters=[
            datetime.now(),
            json.dumps(manifest),
            manifest['total_records_to_delete'],
            'PENDING'
        ]
    )[0]
    
    manifest['manifest_id'] = manifest_id
    
    context['task_instance'].xcom_push(key='deletion_manifest', value=manifest)
    
    return manifest

def execute_data_deletion(**context):
    """Execute the actual data deletion"""
    
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    filtered_data = context['task_instance'].xcom_pull(key='filtered_expired_data')
    manifest = context['task_instance'].xcom_pull(key='deletion_manifest')
    
    deletion_results = {}
    total_deleted = 0
    
    for table_name, data in filtered_data.items():
        try:
            retention_days = data['retention_days']
            
            # Execute deletion
            delete_sql = f"""
            DELETE FROM {table_name}
            WHERE created_at < NOW() - INTERVAL '{retention_days} days'
            """
            
            # Get count before deletion for verification
            count_sql = f"""
            SELECT COUNT(*) FROM {table_name}
            WHERE created_at < NOW() - INTERVAL '{retention_days} days'
            """
            
            records_to_delete = postgres_hook.get_first(count_sql)[0]
            
            if records_to_delete > 0:
                postgres_hook.run(delete_sql)
                
                # Verify deletion
                remaining_count = postgres_hook.get_first(count_sql)[0]
                actual_deleted = records_to_delete - remaining_count
                
                deletion_results[table_name] = {
                    'expected_deletions': records_to_delete,
                    'actual_deletions': actual_deleted,
                    'success': remaining_count == 0,
                    'remaining_records': remaining_count
                }
                
                total_deleted += actual_deleted
                
                logging.info(f"Deleted {actual_deleted} records from {table_name}")
            else:
                deletion_results[table_name] = {
                    'expected_deletions': 0,
                    'actual_deletions': 0,
                    'success': True,
                    'remaining_records': 0
                }
        
        except Exception as e:
            logging.error(f"Error deleting from {table_name}: {str(e)}")
            deletion_results[table_name] = {
                'success': False,
                'error': str(e)
            }
    
    # Update manifest with results
    update_sql = """
    UPDATE data_deletion_manifests
    SET status = %s, deletion_results = %s, actual_deletions = %s, completed_at = NOW()
    WHERE id = %s
    """
    
    status = 'COMPLETED' if all(r.get('success', False) for r in deletion_results.values()) else 'PARTIAL'
    
    postgres_hook.run(
        update_sql,
        parameters=[
            status,
            json.dumps(deletion_results),
            total_deleted,
            manifest['manifest_id']
        ]
    )
    
    context['task_instance'].xcom_push(key='deletion_results', value=deletion_results)
    
    return deletion_results

def generate_compliance_report(**context):
    """Generate compliance report for the retention process"""
    
    manifest = context['task_instance'].xcom_pull(key='deletion_manifest')
    deletion_results = context['task_instance'].xcom_pull(key='deletion_results')
    legal_holds = context['task_instance'].xcom_pull(key='legal_holds')
    
    report = {
        'report_date': datetime.now().isoformat(),
        'process_summary': {
            'total_tables_processed': len(deletion_results),
            'total_records_deleted': sum(r.get('actual_deletions', 0) for r in deletion_results.values()),
            'successful_deletions': sum(1 for r in deletion_results.values() if r.get('success', False)),
            'failed_deletions': sum(1 for r in deletion_results.values() if not r.get('success', True))
        },
        'legal_holds_summary': {
            'tables_with_holds': len(legal_holds),
            'total_holds': sum(len(holds) for holds in legal_holds.values())
        },
        'compliance_status': 'COMPLIANT' if all(r.get('success', False) for r in deletion_results.values()) else 'NEEDS_ATTENTION',
        'manifest_id': manifest['manifest_id'],
        'detailed_results': deletion_results
    }
    
    # Store report
    postgres_hook = PostgresHook(postgres_conn_id='compliance_db')
    
    insert_sql = """
    INSERT INTO compliance_reports (
        report_type, report_date, report_data, status
    ) VALUES (%s, %s, %s, %s)
    """
    
    postgres_hook.run(
        insert_sql,
        parameters=[
            'DATA_RETENTION',
            datetime.now(),
            json.dumps(report),
            report['compliance_status']
        ]
    )
    
    logging.info(f"Generated compliance report: {report['compliance_status']}")
    
    return report

def send_compliance_notification(**context):
    """Send notification about retention process completion"""
    
    report = context['task_instance'].xcom_pull(task_ids='generate_compliance_report')
    
    # Prepare notification payload
    notification_data = {
        'subject': f"Data Retention Process Completed - {report['compliance_status']}",
        'summary': report['process_summary'],
        'compliance_status': report['compliance_status'],
        'report_date': report['report_date'],
        'manifest_id': report['manifest_id']
    }
    
    # This would typically send to your notification service
    logging.info(f"Compliance notification: {notification_data}")
    
    return notification_data

# Task definitions
identify_expired_task = PythonOperator(
    task_id='identify_expired_data',
    python_callable=identify_expired_data,
    dag=dag
)

check_legal_holds_task = PythonOperator(
    task_id='check_legal_holds',
    python_callable=check_legal_holds,
    dag=dag
)

anonymize_data_task = PythonOperator(
    task_id='anonymize_before_deletion',
    python_callable=anonymize_before_deletion,
    dag=dag
)

create_manifest_task = PythonOperator(
    task_id='create_deletion_manifest',
    python_callable=create_deletion_manifest,
    dag=dag
)

execute_deletion_task = PythonOperator(
    task_id='execute_data_deletion',
    python_callable=execute_data_deletion,
    dag=dag
)

generate_report_task = PythonOperator(
    task_id='generate_compliance_report',
    python_callable=generate_compliance_report,
    dag=dag
)

send_notification_task = PythonOperator(
    task_id='send_compliance_notification',
    python_callable=send_compliance_notification,
    dag=dag
)

# Cleanup task for temporary files
cleanup_temp_files = BashOperator(
    task_id='cleanup_temp_files',
    bash_command="""
    find /tmp -name "*.tmp" -mtime +7 -delete
    find /var/log/app -name "*.log" -mtime +30 -delete
    docker system prune -f --volumes --filter "until=24h"
    """,
    dag=dag
)

# Database maintenance
vacuum_databases = PostgresOperator(
    task_id='vacuum_databases',
    postgres_conn_id='compliance_db',
    sql="""
    VACUUM ANALYZE;
    REINDEX DATABASE compliance_db;
    """,
    dag=dag
)

# Task dependencies
identify_expired_task >> check_legal_holds_task >> anonymize_data_task
anonymize_data_task >> create_manifest_task >> execute_deletion_task
execute_deletion_task >> generate_report_task >> send_notification_task
execute_deletion_task >> cleanup_temp_files >> vacuum_databases
