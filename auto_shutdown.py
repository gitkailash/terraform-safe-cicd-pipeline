import json
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda function to auto-shutdown development resources during off-hours
    """
    
    logger.info("Auto-shutdown function started")
    
    # Initialize AWS clients
    ecs_client = boto3.client('ecs')
    rds_client = boto3.client('rds')
    
    try:
        # Get environment from event or default to 'dev'
        environment = event.get('environment', 'dev')
        action = event.get('action', 'shutdown')  # shutdown or startup
        
        logger.info(f"Processing {action} for environment: {environment}")
        
        if action == 'shutdown':
            shutdown_resources(ecs_client, rds_client, environment)
        elif action == 'startup':
            startup_resources(ecs_client, rds_client, environment)
        else:
            raise ValueError(f"Invalid action: {action}")
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {action} for {environment} environment',
                'environment': environment,
                'action': action
            })
        }
        
    except Exception as e:
        logger.error(f"Error in auto-shutdown function: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Auto-shutdown function failed'
            })
        }

def shutdown_resources(ecs_client, rds_client, environment):
    """Shutdown resources for the specified environment"""
    
    # Scale down ECS services
    try:
        cluster_name = f"tf-cicd-pipeline-{environment}"
        
        # List services in the cluster
        services_response = ecs_client.list_services(cluster=cluster_name)
        
        for service_arn in services_response.get('serviceArns', []):
            # Scale service to 0 tasks
            ecs_client.update_service(
                cluster=cluster_name,
                service=service_arn,
                desiredCount=0
            )
            logger.info(f"Scaled down ECS service: {service_arn}")
            
    except Exception as e:
        logger.warning(f"Error scaling down ECS services: {str(e)}")
    
    # Stop RDS instances (for dev environment only)
    if environment == 'dev':
        try:
            db_instance_id = f"tf-cicd-pipeline-{environment}-db"
            
            # Check if instance exists and is running
            response = rds_client.describe_db_instances(DBInstanceIdentifier=db_instance_id)
            db_instance = response['DBInstances'][0]
            
            if db_instance['DBInstanceStatus'] == 'available':
                rds_client.stop_db_instance(DBInstanceIdentifier=db_instance_id)
                logger.info(f"Stopped RDS instance: {db_instance_id}")
            else:
                logger.info(f"RDS instance {db_instance_id} is not in available state: {db_instance['DBInstanceStatus']}")
                
        except Exception as e:
            logger.warning(f"Error stopping RDS instance: {str(e)}")

def startup_resources(ecs_client, rds_client, environment):
    """Startup resources for the specified environment"""
    
    # Start RDS instances (for dev environment only)
    if environment == 'dev':
        try:
            db_instance_id = f"tf-cicd-pipeline-{environment}-db"
            
            # Check if instance exists and is stopped
            response = rds_client.describe_db_instances(DBInstanceIdentifier=db_instance_id)
            db_instance = response['DBInstances'][0]
            
            if db_instance['DBInstanceStatus'] == 'stopped':
                rds_client.start_db_instance(DBInstanceIdentifier=db_instance_id)
                logger.info(f"Started RDS instance: {db_instance_id}")
            else:
                logger.info(f"RDS instance {db_instance_id} is not in stopped state: {db_instance['DBInstanceStatus']}")
                
        except Exception as e:
            logger.warning(f"Error starting RDS instance: {str(e)}")
    
    # Scale up ECS services
    try:
        cluster_name = f"tf-cicd-pipeline-{environment}"
        
        # List services in the cluster
        services_response = ecs_client.list_services(cluster=cluster_name)
        
        for service_arn in services_response.get('serviceArns', []):
            # Scale service back to desired count (default 1 for dev)
            desired_count = 1 if environment == 'dev' else 2
            
            ecs_client.update_service(
                cluster=cluster_name,
                service=service_arn,
                desiredCount=desired_count
            )
            logger.info(f"Scaled up ECS service: {service_arn} to {desired_count} tasks")
            
    except Exception as e:
        logger.warning(f"Error scaling up ECS services: {str(e)}")