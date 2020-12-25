#!/usr/bin/env bash

REGION=us-east-1
TAG_NAME=LAB-3
KEY_NAME=aws-dev
AMI=ami-00ddb0e5626798373
PROC_TYPE=t2.micro
COUNT=1

# Set region
export AWS_DEFAULT_REGION=$REGION
echo -e "Set region to: $REGION \nCreating vpc with necessary components"

# Create a vpc and tag it
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --output json | grep "VpcId" | cut -f4 -d \" )
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="$TAG_NAME"
aws ec2 wait vpc-available --vpc-id $VPC_ID
# aws ec2 describe-vpcs --vpc-id $VPC_ID

# Create an internet gateway and attach it to the vpc
IGW_ID=$(aws ec2 create-internet-gateway | grep "igw-" | cut -f4 -d \" )
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="$TAG_NAME"
# aws ec2 describe-internet-gateways --internet-gateway-id $IGW_ID

# Create a subnet within the vpc and modify it so that new instances within it will be public on launch
SUBNET_ID=$(aws ec2 create-subnet --cidr-block 10.0.1.0/24 --vpc-id $VPC_ID | grep SubnetId | cut -f4 -d \" )
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value="$TAG_NAME"
# aws ec2 describe-subnets --subnet-id $SUBNET_ID

# Create a route table in the vpc
RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID | grep "rtb-" | cut -f4 -d \" )
aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value="$TAG_NAME"
# aws ec2 describe-route-tables --route-table-id $RT_ID

# Create a route to the internet gateway and attach table to subnet
aws ec2 create-route --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --route-table-id $RT_ID
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_ID

echo "Please wait a moment..."
aws ec2 wait vpc-available --vpc-ids $VPC_ID
echo -e "$VPC_ID\n$IGW_ID\n$SUBNET_ID and\n$RT_ID are ready\nCreating new key pair..."


if [ ! -f "$KEY_NAME" ]; then
  # echo 'Creating new key pair'
  aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME
  chmod 400 $KEY_NAME
  aws ec2 wait key-pair-exists --key-names $KEY_NAME
  KEYPAIR_ID=$(aws ec2 describe-key-pairs  --key-names $KEY_NAME | grep KeyPairId | cut -f4 -d \" )
  echo "$KEY_NAME created"
else
  echo "WebServer already exists"
  KEYPAIR_ID=$(aws ec2 describe-key-pairs  --key-names $KEY_NAME | grep KeyPairId | cut -f4 -d \" )
fi

# Create a security group and allow SSH and HTTP access from anywhere. NOTE: not advisable in production!
aws ec2 create-security-group --group-name Step1-Access --description "Step-1 security group for SSH access" --vpc-id $VPC_ID
SGROUP_ID=$(aws ec2 describe-security-groups --filters Name=description,Values="Step-1 security group for SSH access" | grep GroupId | cut -f4 -d \" )
aws ec2 authorize-security-group-ingress --group-id $SGROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SGROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SGROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0

aws ec2 wait security-group-exists --group-ids $SGROUP_ID
echo "Security group: $SGROUP_ID created"
# Create an ec2 instance running Ubuntu 18 AMI on t2.micro
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI --count $COUNT --instance-type $PROC_TYPE --key-name $KEY_NAME --user-data file://userdata.sh --security-group-ids $SGROUP_ID --subnet-id $SUBNET_ID  | grep InstanceId | cut -f4 -d \" )
aws ec2 create-tags --resources $INSTANCE_ID --tags Key=Role,Value="Web-Server"
echo "Creating instance"
echo "This could take a few moments..."
aws ec2 wait instance-exists --instance-ids $INSTANCE_ID
PUB_IPADDRESS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep PublicIpAddress | cut -f4 -d \" )
echo -e "\nSuccess!"
echo "Instance $INSTANCE_ID created with public IP address: $PUB_IPADDRESS"

#CREATE AMI
#aws ec2 create-image --instance-id $INSTANCE_ID --name "My server" --description "An AMI for my server"
