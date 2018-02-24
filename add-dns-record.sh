#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/scripts/functions
loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-dns-record.yml
STACK_NAME=$( dnsStackName $ENV_NAME ) 
INFRA_STACK_NAME=$( infraStackName $ENV_NAME ) 

# Infra stack must exist
failIfStackDoesNotExist $INFRA_STACK_NAME $RESOURCES_REGION

# Decide whether creating or updating the stack
checkIfStackExists $STACK_NAME $RESOURCES_REGION
if [ $? -eq 0 ]; then
  CF_CMD=update-stack
    WAIT_CMD=stack-update-complete
  echo "Updating stack $STACK_NAME"
else
  CF_CMD=create-stack
  WAIT_CMD=stack-create-complete
  echo "Creating stack $STACK_NAME"
fi

# Send template to CloudFront 
aws cloudformation $CF_CMD  --output text \
    --stack-name $STACK_NAME \
    --region $RESOURCES_REGION  \
    --template-body $CF_TEMPLATE \
    --parameters \
        ParameterKey=WebsiteInfraStackName,ParameterValue=$INFRA_STACK_NAME
if [ $? -ne 0 ]; then
    showCloudformationFailureMessage $CF_CMD $STACK_NAME    
    exit 1
fi 

# Wait before stack exists
waitStackExists $STACK_NAME $RESOURCES_REGION

# Wait until stack create/update is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION $WAIT_CMD "it may take few minutes"

STACK_STATUS=$( getStackStatus $STACK_NAME $RESOURCES_REGION )
echo "Stack Status: $STACK_STATUS"

showStackOutputs $STACK_NAME $RESOURCES_REGION