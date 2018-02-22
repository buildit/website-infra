#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions

loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-infra.yml
STACK_NAME="${ENV_NAME}-infra"

# Check if the Certificate ARN exists in us-east-1 (!)
aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region us-east-1  > /dev/null 2>&1 
if [ $? -ne 0 ]; then
  echo "Certificarte $CERTIFICATE_ARN must exist Region us-east-1" 
  exit 1
fi

# Decide whether creating or updating the stack
checkIfStackExists $STACK_NAME $RESOURCES_REGION
if [ $? -eq 0 ]; then
  CF_CMD=update-stack
  WAIT_CMD=stack-update-complete
  echo "Updating stack $STACK_NAME "
else
  CF_CMD=create-stack
  WAIT_CMD=stack-create-complete
  echo "Creating stack $STACK_NAME"
fi

# Check whether making A/B testing available
if [ -z "$AB_EXPERIMENT_BUCKET" ]; then
  PARAM_EXPERIMENT=""
  echo "No A/B testing"
else
  PARAM_EXPERIMENT="ParameterKey=SiteExperimentBucketName,ParameterValue=${AB_EXPERIMENT_BUCKET}"
  echo "A/B available"  
fi

# Check whether enabling CloudFront logging
if [ -z "$LOGS_BUCKET" ]; then
  PARAM_LOGS=""
  echo "No CloudFormation logging"
else
  PARAM_LOGS="ParameterKey=LogBucketName,ParameterValue=${LOGS_BUCKET}"
  echo "CloudFormatiomn logging enabled"
fi

# Send template to CloudFront
aws cloudformation $CF_CMD --output text \
    --stack-name $STACK_NAME  \
    --template-body $CF_TEMPLATE \
    --region $RESOURCES_REGION \
    --parameters \
        ParameterKey=SiteBucketName,ParameterValue=$SITE_BUCKET \
        $PARAM_EXPERIMENT \
        $PARAM_LOGS \
        ParameterKey=WebsiteDnsName,ParameterValue=$WEBISTE_DNS_NAME \
        ParameterKey=DnsZoneName,ParameterValue=$WEBSITE_DOMAIN \
        ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN \
        ParameterKey=CdnPriceClass,ParameterValue=$CDN_PRICE_CLASS

exitOnFailure "sending $CF_CMD command"

# Wait before stack exists
waitStackExists $STACK_NAME $RESOURCES_REGION

# Wait until stack create/update is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION $WAIT_CMD "may take tenths of minutes"

# Show stack outputs
showStackOutput $STACK_NAME $RESOURCES_REGION
