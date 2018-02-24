#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions.sh

loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-infra.yml
STACK_NAME="${ENV_NAME}-infra"

# Infra stack must exist
failIfStackDoesNotExist $STACK_NAME $RESOURCES_REGION

# Check whether making A/B testing available
if [ -z "$AB_EXPERIMENT_BUCKET" ]; then
  echo "No A/B testing abailable"
  exit 1
fi

# Check whether enabling CloudFront logging
if [ -z "$LOGS_BUCKET" ]; then
  PARAM_LOGS=""
  echo "No CloudFormation logging"
else
  PARAM_LOGS="ParameterKey=LogBucketName,ParameterValue=${LOGS_BUCKET}"
  echo "CloudFormatiomn logging enabled"
fi

# Update infra stack
# WITHOUT A/B TESTING LAMBDA FUNCTIONS
aws cloudformation update-stack --output text \
    --stack-name $STACK_NAME  \
    --template-body $CF_TEMPLATE \
    --region $RESOURCES_REGION \
    --parameters \
        ParameterKey=SiteBucketName,ParameterValue=$SITE_BUCKET \
        ParameterKey=SiteExperimentBucketName,ParameterValue=${AB_EXPERIMENT_BUCKET} \
        $PARAM_LOGS \
        ParameterKey=WebsiteDnsName,ParameterValue=$WEBISTE_DNS_NAME \
        ParameterKey=DnsZoneName,ParameterValue=$WEBSITE_DOMAIN \
        ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN \
        ParameterKey=CdnPriceClass,ParameterValue=$CDN_PRICE_CLASS
if [ $? -ne 0 ]; then
    echo "Failed update-stack of $STACK_NAME stack"
    exit 1
fi

# Wait until stack create/update is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION stack-update-complete "it may take tenths of minutes"

STACK_STATUS=$( getStackStatus $STACK_NAME $RESOURCES_REGION )
echo "Stack Status: $STACK_STATUS"

# Show stack outputs
getStackOutput $STACK_NAME $RESOURCES_REGION

# Note: Lambda stack cannot be removed immediately after being detached from CloudFront: the replica takes a while to be removed
