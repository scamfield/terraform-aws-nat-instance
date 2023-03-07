#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Author: Stephen Camfield
Copyright: Copyright 2023, Stephen Camfield
Description: This script is used during first boot to add the default route if doesn't exist.
"""
import boto3
import logging
import logging.handlers
import requests
import sys

class NATInstance:
    def __init__(self):
        # Configure the logging module to write log messages to syslog
        syslog_handler = logging.handlers.SysLogHandler(address='/dev/log')
        syslog_formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(message)s')
        syslog_handler.setFormatter(syslog_formatter)
        logging.getLogger('').addHandler(syslog_handler)
        logging.getLogger('').setLevel(logging.INFO)

        self.region = self.get_instance_region()
        self.ec2 = boto3.resource('ec2', region_name=self.region)
        self.instance_id = self.get_instance_id()
        self.eni_id = self.get_eni_id()
        self.subnet_id = self.get_subnet_id()
        self.routing_table_id = self.get_routing_table_id()
        self.vpc_id = self.get_vpc_id()

    def get_instance_region(self):
        try:
            metadata_url = 'http://169.254.169.254/latest/meta-data/placement/availability-zone'
            availability_zone = requests.get(metadata_url, timeout=2).text
            return availability_zone[:-1]
        except requests.exceptions.RequestException as e:
            logging.error(f"Unable to get instance region: {e}")
            sys.exit(1)

    def get_instance_id(self):
        url = "http://169.254.169.254/latest/meta-data/instance-id"
        try:
            response = requests.get(url, timeout=0.1)
            response.raise_for_status()
            return response.text
        except requests.exceptions.RequestException as e:
            logging.error(f"Unable to get instance ID: {e}")
            sys.exit(1)

    def get_eni_id(self):
        try:
            instance = boto3.client('ec2', region_name=self.region).describe_instances(InstanceIds=[self.instance_id])['Reservations'][0]['Instances'][0]
            eni = instance['NetworkInterfaces'][0]
            return eni['NetworkInterfaceId']
        except Exception as e:
            logging.error(f"Unable to get ENI ID: {e}")
            sys.exit(1)

    def get_subnet_id(self):
        try:
            eni = boto3.client('ec2', region_name=self.region).describe_network_interfaces(NetworkInterfaceIds=[self.eni_id])['NetworkInterfaces'][0]
            return eni['SubnetId']
        except Exception as e:
            logging.error(f"Unable to get subnet ID: {e}")
            sys.exit(1)

    def get_routing_table_id(self):
        try:
            ec2_client = boto3.client('ec2', region_name=self.region)

            # Step 1: Get the VPC ID from the subnet ID
            subnet = self.ec2.Subnet(self.subnet_id)
            vpc_id = subnet.vpc_id

            # Step 2: Use the VPC ID to get all the private subnets related to that VPC
            private_subnets = self.ec2.subnets.filter(
                Filters=[
                    {'Name': 'vpc-id', 'Values': [vpc_id]},
                    {'Name': 'tag:Name', 'Values': ['*-private-*']}
                ]
            )

            # Step 3: Filter the private subnets to only include those in the same availability zone as the ENI
            eni = ec2_client.describe_network_interfaces(NetworkInterfaceIds=[self.eni_id])['NetworkInterfaces'][0]
            same_az_subnets = [subnet for subnet in private_subnets if subnet.availability_zone == eni['AvailabilityZone']]

            # Step 4: Use the filtered subnet ID(s) to get the routing table ID(s) for the private subnets
            route_table_ids = []
            for subnet in same_az_subnets:
                route_table_id = ec2_client.describe_route_tables(
                    Filters=[{'Name': 'association.subnet-id', 'Values': [subnet.id]}]
                )['RouteTables'][0]['RouteTableId']
                route_table_ids.append(route_table_id)

            # Step 5: Return the first routing table ID
            if len(route_table_ids) > 0:
                return route_table_ids[0]
            else:
                logging.error(f"No route table found for subnets in availability zone {eni['AvailabilityZone']}")
                sys.exit(1)
        except Exception as e:
            logging.error(f"Unable to get routing table ID: {e}")
            sys.exit(1)

    def get_vpc_id(self):
        try:
            ec2_client = boto3.client('ec2', region_name=self.region)
            subnet = ec2_client.describe_subnets(SubnetIds=[self.subnet_id])['Subnets'][0]
            return subnet['VpcId']
        except Exception as e:
            logging.error(f"Unable to get VPC ID: {e}")
            sys.exit(1)

    def create_route(self):
        try:
            # Check if a default route to 0.0.0.0/0 already exists in the routing table
            route_exists = False
            ec2_client = boto3.client('ec2', region_name=self.region)
            routing_table = ec2_client.describe_route_tables(RouteTableIds=[self.routing_table_id])['RouteTables'][0]
            for route in routing_table["Routes"]:
                if route['DestinationCidrBlock'] == '0.0.0.0/0':
                    route_exists = True
                    break

            # Add a default route to 0.0.0.0/0 if it doesn't already exist
            if not route_exists:
                ec2_client.create_route(
                    RouteTableId=self.routing_table_id,
                    DestinationCidrBlock='0.0.0.0/0',
                    NetworkInterfaceId=self.eni_id
                )
        except Exception as e:
            logging.error(f"Unable to create default route: {e}")
            sys.exit(1)

if __name__ == "__main__":
    nat_instance = NATInstance()
    nat_instance.create_route()
