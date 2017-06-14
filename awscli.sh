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

# Run selected example
CHOICE=$1
CMD=''
[ 1 = $CHOICE ] && CMD="aws ec2 describe-regions"

[ 2 = $CHOICE ] && CMD="aws ec2 describe-regions --output text"

[ 3 = $CHOICE ] && CMD="aws ec2 describe-regions --output table"

[ 4 = $CHOICE ] && CMD="aws ec2 describe-regions --query Regions[].RegionName"


# - Unrecognized CMD
if [ -z "$CMD" ]
then
	printf "Error: no such choice : %s\n" "$CHOICE" 1>&2
	exit 1
fi

# For testing purpose
printf "%02d> %s\n" "$CHOICE" "$CMD" 1>&2
eval $CMD

