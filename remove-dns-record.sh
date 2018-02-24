#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions.sh

loadConfig $1

STACK_NAME=$( dnsStackName $ENV_NAME ) 

# Send stack delete requiest
aws cloudformation delete-stack --stack-name $STACK_NAME --region $RESOURCES_REGION
if [ $? -ne 0 ]; then
  echo "Failed to send delete-stack command to CloudFormation"
  exit 1
fi

# Wait until stack deletion is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION "stack-delete-complete" "it may take few minutes"
