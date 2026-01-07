import boto3
import os
import time

def lambda_handler(event, context):
    """
    Automated DR Failover Handler
    Triggered by: CloudWatch Alarm (Route53 Health Check Failed) via EventBridge
    Actions:
      1. Promote local RDS Cluster (if it is a secondary global member)
      2. Scale up EKS Node Group to prepare for traffic
    """
    print(f"Received event: {event}")
    
    global_cluster_id = os.environ['GLOBAL_CLUSTER_ID']
    eks_cluster_name = os.environ['EKS_CLUSTER_NAME']
    node_group_name = os.environ['EKS_NODE_GROUP_NAME']
    target_capacity = int(os.environ.get('TARGET_CAPACITY', 2))
    target_region = os.environ.get('TARGET_REGION', os.environ['AWS_REGION'])

    rds = boto3.client('rds', region_name=target_region)
    eks = boto3.client('eks', region_name=target_region)
    
    # 1. RDS Failover / Promote
    try:
        # Check current status
        response = rds.describe_global_clusters(GlobalClusterIdentifier=global_cluster_id)
        members = response['GlobalClusters'][0]['GlobalClusterMembers']
        
        # Find local member safely by parsing ARN
        # ARN Format: arn:aws:rds:region:account:cluster:name
        local_member = None
        for m in members:
            arn_parts = m['DBClusterArn'].split(':')
            if len(arn_parts) > 3 and arn_parts[3] == target_region:
                local_member = m
                break
        
        if local_member:
            if not local_member['IsWriter']:
                print(f"Local cluster ({local_member['DBClusterArn']}) is Secondary. Initiating Failover...")
                # Attempt standard failover first
                try:
                    rds.failover_global_cluster(
                        GlobalClusterIdentifier=global_cluster_id,
                        TargetDbClusterIdentifier=local_member['DBClusterArn']
                    )
                    print("RDS Failover initiated successfully.")
                except Exception as failover_err:
                    print(f"Standard failover failed: {failover_err}. Attempting 'Remove From Global' as fallback...")
                    # Fallback: Remove from global (Disaster Recovery Mode)
                    rds.remove_from_global_cluster(
                        GlobalClusterIdentifier=global_cluster_id,
                        DbClusterIdentifier=local_member['DBClusterArn']
                    )
                    print("Fallback: Removed from Global Cluster initiated.")

                # Best-effort: short wait for writer promotion
                for _ in range(6):
                    time.sleep(10)
                    try:
                        check = rds.describe_global_clusters(GlobalClusterIdentifier=global_cluster_id)
                        check_members = check['GlobalClusters'][0]['GlobalClusterMembers']
                        for m in check_members:
                            if m['DBClusterArn'] == local_member['DBClusterArn'] and m.get('IsWriter'):
                                print("Local cluster promoted to Writer.")
                                raise StopIteration
                    except StopIteration:
                        break
                    except Exception:
                        # Ignore transient describe errors
                        pass
            else:
                print("Local cluster is already Primary (Writer). Skipping RDS failover.")
        else:
            print(f"Error: Could not find a cluster member in the current region ({target_region}).")
            
    except Exception as e:
        print(f"Error during RDS operations: {str(e)}")
        # Continue to EKS scaling even if RDS fails (best effort)

    # 2. EKS Scaling
    try:
        print(f"Scaling up EKS Node Group: {node_group_name} in {eks_cluster_name} to size {target_capacity}...")
        
        # Scale Node Group to desired capacity
        current = eks.describe_nodegroup(clusterName=eks_cluster_name, nodegroupName=node_group_name)
        scaling = current['nodegroup'].get('scalingConfig', {})
        current_min = int(scaling.get('minSize', 0))
        current_max = int(scaling.get('maxSize', target_capacity + 2))

        eks.update_nodegroup_config(
            clusterName=eks_cluster_name,
            nodegroupName=node_group_name,
            scalingConfig={
                'minSize': max(current_min, target_capacity),
                'maxSize': max(current_max, target_capacity + 2),
                'desiredSize': target_capacity
            }
        )
        print("EKS Node Group scaling initiated.")
        
    except Exception as e:
        print(f"Error during EKS operations: {str(e)}")
        raise e

    return {
        'statusCode': 200,
        'body': 'DR Failover Sequence Executed'
    }

