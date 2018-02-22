#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source $DIR/scripts/functions
loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-dns-record.yml
STACK_NAME="${ENV_NAME}-dns"
INFRA_STACK_NAME="${ENV_NAME}-infra"


# Check if the infra stack exists
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

exitOnFailure "sending $CF_CMD command"

# Wait before stack exists
waitStackExists $STACK_NAME $RESOURCES_REGION

# Wait until stack create/update is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION $WAIT_CMD "may take few minutes"

# TODO Show stack outputs
