#!/bin/bash

# AWS CLI 
REGION_NAME=${REGION_NAME:-"us-west-2"}
INSTANCE_TYPE=${INSTANCE_TYPE:-"t2.micro"}
VPC_NAME=${VPC_NAME:-"main"}

# Mode switching
set -e
#set -x

# Checing the number of arguments parsed into the script
if [ $# != 1 ]
then
	printf "usage: $0 choice\n" 1>&2
       	#0-stdin 1-stout 2-stderr 1>&2 will redirect the file descriptor 1 to STDERR
	exit 1
fi

# Functions
function list_amis() {
	local region=$1
	local name=$2
	aws ec2 describe-images \
		--region "${region}" \
		--filters \
			Name=owner-alias,Values=amazon \
			Name=name,Values="$name" \
			Name=architecture,Values=x86_64 \
			Name=virtualization-type,Values=hvm \
			Name=root-device-type,Values=ebs \
			Name=block-device-mapping.volume-type,Values=gp2 \
		--query "Images[*].['$region',ImageId,Name,Description]" \
		--output text
}
# - Note: dont put a blank space after backslash
function find_vpc() {
	aws ec2 describe-vpcs \
		--filters \
			Name=tag:Name,Values=${VPC_NAME} \
		--query "Vpcs[].VpcId" \
		--output text	
			
}

# helper function
function find_subnet() {
	local subnet_name=$1
	aws ec2 describe-subnets \
		--filters \
			Name=vpc-id,Values=$(find_vpc) \
			Name=tag:Name,Values=${subnet_name} \
		--query "Subnets[].SubnetId" \
		--output text
}

function get_security_group() {
	local group_name=$1
	aws ec2 describe-security-groups \
		--region "$REGION_NAME" \
		--filters \
			Name=group-name,Values=${group_name} \
			Name=vpc-id,Values=$(find_vpc) \
		--query SecurityGroups[].GroupId \
		--output text
}

function get_keypair() {
	aws ec2 describe-key-pairs \
		--query KeyPairs[].KeyName \
		--output text
}

function find_hostname() {
	local instance_ids=$1
	aws ec2 describe-instances \
		--instance_ids "$instance_id" \
		--output text \
		--query Reservations[].Instances[0].PublicDnsName
}

function launch_instance() {
	local image_id=$(list_amis $REGION_NAME amzn-ami-hvm-* | sort -rk 3,3 | grep -v rc | head -n 1 | cut -f 2)
	local subnet_id=$(find_subnet public)
	local security_groups=$(get_security_group default)
	local instance_id=$(aws ec2 run-instances \
		--associate-public-ip-address \
		--image-id "$image_id" \
		--key-name "$(get_keypair)" \
		--subnet-id "${subnet_id}" \
		--security-group-ids "$security_groups" \
		--instance-type "$INSTANCE_TYPE" \
		--output text \
		--query "Instances[0].InstanceId"
	)

	aws ec2 create-tags \
		--resources "$instance_id" \
		--tags Key=enviroment,Value=demo
	printf "Wait %s: %s until running..\n" $INSTANCE_TYPE $instance_id
	aws ec2 wait instance-running --instance-ids "$instance_id"

	local instance_hostname=$(aws ec2 describe-instances \
		--instance-ids "$instance_id" \
		--output text \
		--query Reservations[].Instances[0].PublicDnsName
	)

	printf "Wait for SSH ready to connect..\n"
	local retry=5
	while [ $retry -gt 0 ]; do
		ssh -o StrictHostKeyChecking=no $instance_hostname
		# Use $? check the last return value of ssh, to see if the connection has been established
		if [ $? -eq 0 ]; then
			echo "SSH succeed."
			break
		fi
		echo "Retrying..\n"
		((retry-=1))
	done
}

function terminate_instances() {
	local instance_ids=$(aws ec2 describe-instances \
		--filters Name="instance-state-name",Values="running" \
		--query "Reservations[].Instances[0].InstanceId" \
		--output text
	)
	aws ec2 terminate-instances --instance-ids ${instance_ids}
}
# Run selected example
CHOICE=$1
CMD=''
[ 1 = $CHOICE ] && CMD="aws ec2 describe-regions"

[ 2 = $CHOICE ] && CMD="aws ec2 describe-regions --output text"

[ 3 = $CHOICE ] && CMD="aws ec2 describe-regions --output table"

[ 4 = $CHOICE ] && CMD="aws ec2 describe-regions --query Regions[].RegionName"

[ 5 = $CHOICE ] && CMD="aws ec2 describe-regions --query Regions[0].RegionName"

[ 6 = $CHOICE ] && CMD="list_amis $REGION_NAME amzn-ami-hvm-*"

[ 7 = $CHOICE ] && CMD="find_vpc"

[ 8 = $CHOICE ] && CMD="get_security_group default"

[ 9 = $CHOICE ] && CMD="launch_instance"

[ 10 = $CHOICE ] && CMD="terminate_instances"
# - Unrecognized CMD
if [ -z "$CMD" ]
then
	printf "Error: no such choice : %s\n" "$CHOICE" 1>&2
	exit 1
fi

# For testing purpose
printf "%02d> %s\n" "$CHOICE" "$CMD" 1>&2
eval $CMD

