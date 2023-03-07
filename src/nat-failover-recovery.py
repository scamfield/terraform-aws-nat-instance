"""
Author: Stephen Camfield
Copyright: Copyright 2023, Stephen Camfield
Description: This Lambda handles the routing table failover and recovery via SNS and ASG Notifications.
"""
import boto3
import json
import os

global zone
global region
lambda_region = os.environ['REGION']

ec2client = boto3.client('ec2', region_name=lambda_region)

def lambda_handler(event, context):
    #print("Received event: " + json.dumps(event, indent=2))
    zone = None
    region = None
    payload = event
    if 'source' in payload:
        zone = event['detail']['Details']['Availability Zone']
        region = event['region']
        if 'Terminate' in event['detail-type']:
            zone = event['detail']['Details']['Availability Zone']
            region = event['region']
            print("Failover Notification Received via ASG")
            failover(zone, region)
        else:
            print("Recovery Notification Received via ASG")
            recovery(zone, region)
    elif 'Records' in payload:
        zone = event['Records'][0]['Sns']['Message'].split()[4]
        region = (event['Records'][0]['Sns']['Message'].split()[11])
        if 'RECOVERY' in event['Records'][0]['Sns']['Message']:
            print("Recovery Notification Received via SNS")
            recovery(zone, region)
        else:
            print("Failover Notification Received via SNS")
            failover(zone, region)
    else:
        print("Lambda Error: Failure to work out notification type")
        exit()

def failover(primary_zone, region):
    print("Failover in progress...")

    if primary_zone.endswith('a'):
        failover_zone = primary_zone[:-1] + 'b'
    elif primary_zone.endswith('b'):
        failover_zone = primary_zone[:-1] + 'a'
    else:
        raise ValueError("Invalid availability zone format")

    print("failover zone: {}".format(failover_zone))

    eni_filters = [{'Name': 'availability-zone', 'Values': [primary_zone]}, {'Name': 'tag:Name', 'Values': ['*-nat-*']}]
    try:
        primary_eni = [interface for interface in ec2client.describe_network_interfaces(Filters=eni_filters).get('NetworkInterfaces')][0]
    except IndexError:
        raise RuntimeError("No ENIs found")

    subnet_id = primary_eni['SubnetId']

    # Get the private subnets in the same availability zone
    private_subnet_filters = [{'Name': 'vpc-id', 'Values': [primary_eni['VpcId']]}, {'Name': 'tag:Name', 'Values': ['*-private-*']}, {'Name': 'availability-zone', 'Values': [primary_zone]}]
    private_subnets = ec2client.describe_subnets(Filters=private_subnet_filters).get('Subnets')

    if not private_subnets:
        print("No private subnets found in the same availability zone as ENI {}.".format(primary_eni.get('NetworkInterfaceId')))
        return

    # Find the routing table associated with the private subnet in the same availability zone as the ENI
    private_subnet = next((s for s in private_subnets if s['AvailabilityZone'] == primary_zone), None)
    if not private_subnet:
        print("No private subnet found in the same availability zone as ENI {}.".format(primary_eni.get('NetworkInterfaceId')))
        return
    private_subnet_associations = ec2client.describe_route_tables(Filters=[{'Name': 'association.subnet-id', 'Values': [private_subnet['SubnetId']]}]).get('RouteTables')[0].get('Associations')
    private_association = next((a for a in private_subnet_associations if a['SubnetId'] == private_subnet['SubnetId']), None)
    if not private_association:
        print("No route table association found for private subnet {}.".format(private_subnet['SubnetId']))
        return
    private_route_table_id = private_association.get('RouteTableId')

    eni_failover_filters = [{'Name': 'availability-zone', 'Values': [failover_zone]}, {'Name': 'tag:Name', 'Values': ['*-nat-*']}]
    eni_failover = ec2client.describe_network_interfaces(Filters=eni_failover_filters).get('NetworkInterfaces')[0]

    # Replace the route table entry with the failover ENI
    route_failover(private_route_table_id, eni_failover)

def recovery(zone, region):
    print("Recovery in progress...")

    eni_filters = [{'Name': 'availability-zone', 'Values': [zone]}, {'Name': 'tag:Name', 'Values': ['*-nat-*']}]
    eni = ec2client.describe_network_interfaces(Filters=eni_filters).get('NetworkInterfaces')[0]
    subnet_id = eni.get('SubnetId')
    if not subnet_id:
        print("No subnet found for ENI {}.".format(eni.get('NetworkInterfaceId')))
        return

    # Get the private subnets in the same availability zone
    private_subnet_filters = [{'Name': 'vpc-id', 'Values': [eni['VpcId']]}, {'Name': 'tag:Name', 'Values': ['*-private-*']}, {'Name': 'availability-zone', 'Values': [zone]}]
    private_subnets = ec2client.describe_subnets(Filters=private_subnet_filters).get('Subnets')

    if not private_subnets:
        print("No private subnets found in the same availability zone as ENI {}.".format(eni.get('NetworkInterfaceId')))
        return

    # Find the route table associated with the current ENI's subnet
    subnet_associations = ec2client.describe_route_tables(Filters=[{'Name': 'association.subnet-id', 'Values': [subnet_id]}]).get('RouteTables')[0].get('Associations')
    current_association = next((a for a in subnet_associations if a['SubnetId'] == subnet_id), None)
    if not current_association:
        print("No route table association found for ENI {}.".format(eni.get('NetworkInterfaceId')))
        return
    route_table_id = current_association.get('RouteTableId')

    # Find the routing table associated with the private subnet in the same availability zone as the ENI
    private_subnet = next((s for s in private_subnets if s['AvailabilityZone'] == zone), None)
    if not private_subnet:
        print("No private subnet found in the same availability zone as ENI {}.".format(eni.get('NetworkInterfaceId')))
        return
    private_subnet_associations = ec2client.describe_route_tables(Filters=[{'Name': 'association.subnet-id', 'Values': [private_subnet['SubnetId']]}]).get('RouteTables')[0].get('Associations')
    private_association = next((a for a in private_subnet_associations if a['SubnetId'] == private_subnet['SubnetId']), None)
    if not private_association:
        print("No route table association found for private subnet {}.".format(private_subnet['SubnetId']))
        return
    private_route_table_id = private_association.get('RouteTableId')

    # Restore the routes
    route_restore(private_route_table_id, eni)

def route_failover(routetable, eni_failover):
    ec2client.replace_route(RouteTableId=routetable, DestinationCidrBlock='0.0.0.0/0', NetworkInterfaceId=eni_failover.get('NetworkInterfaceId'))
    print("Failed over to zone with " + eni_failover.get('NetworkInterfaceId'))

def route_restore(routetable, eni):
    if (eni.get('Status') != 'in-use'):
        print ("eni status: " + eni.get('Status'))
    else:
        ec2client.replace_route(RouteTableId=routetable, DestinationCidrBlock='0.0.0.0/0', NetworkInterfaceId=eni.get('NetworkInterfaceId'))
        print("Recovered in own zone with " + eni.get('NetworkInterfaceId'))
