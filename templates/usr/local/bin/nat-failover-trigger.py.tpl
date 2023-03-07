#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Author: Stephen Camfield
Copyright: Copyright 2023, Stephen Camfield
Description: This scripts handles the notifications via SNS.
"""
import boto3
import requests
import json
import argparse

region = json.loads(requests.get("http://169.254.169.254/latest/dynamic/instance-identity/document").text)['region']
az = requests.get("http://169.254.169.254/latest/meta-data/placement/availability-zone").text
ec2id = requests.get("http://169.254.169.254/latest/meta-data/instance-id").text
sns_topic_arn = '${sns_arn}'

def notify_sns(message, sns_topic_arn):
    client = boto3.client("sns", region_name=region)
    response = client.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps({'default': message}),
            MessageStructure='json'
            )
    return response

if __name__ == '__main__':
    message = None
    parser = argparse.ArgumentParser('nat-instance-failover')
    parser.add_argument(
    "-t", "--task",
    choices=['failover','recover'],
    help="choose what message, you need me to send."
    )
    args = parser.parse_args()

    if args.task == 'failover':
        #print("top bread")
        message = "FAILOVER: " + ec2id + " in zone " + az + " is going down for maintenance in " + region
    elif args.task == 'recover':
        #print("bacon")
        message = "RECOVERY: " + ec2id + " in zone " + az + " is online again after maintenance in " + region
    else:
        #print("bottom bread")
        print("Hey! I need you to tell me, what sns message to send?!")
        exit()


    print(notify_sns(message, sns_topic_arn))
