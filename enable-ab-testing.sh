#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions.sh

loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-infra.yml
STACK_NAME="${ENV_NAME}-infra"
AB_TESTING_LAMBDA_STACK=$( abTestingLambdaStackName $ENV_NAME ) 
echo "Lambda Stack: $AB_TESTING_LAMBDA_STACK"

# Infra stack must exist
failIfStackDoesNotExist $STACK_NAME $RESOURCES_REGION

# Check whether making A/B testing available
if [ -z "$AB_EXPERIMENT_BUCKET" ]; then
  echo "No A/B testing abailable"
  exit 1
else
  # Generate data file for generating lambda code
  # This creates/update the lambda stack (on us-east-1)

  # Build and deploy lambda functions for A/B testing
  cd $DIR/ab-testing
  npm install

  # Generate data file for generating lambda code
  echo "Generating Lambda function code"
  echo "{ \"experimentBucket\" : \"${AB_EXPERIMENT_BUCKET}\" }" > $DIR/ab-testing/build/data.json
  npm run build

  echo "Deploy Lambda functions"
  sls deploy --stage $ENV_NAME
  cd -
fi


# Lambda stack must now exist, in us-east-1
failIfStackDoesNotExist $AB_TESTING_LAMBDA_STACK "us-east-1"


# Retrieve Lambda ARNs from the Lambda stack
AB_TESTING_VIEWER_REQUEST_FUNCTION=$( getABtestingLambdaFunctionArn $AB_TESTING_LAMBDA_STACK 'ViewerRequest' )
echo "Viewer Request: $AB_TESTING_VIEWER_REQUEST_FUNCTION"
AB_TESTING_ORIGIN_REQUEST_FUNCTION=$( getABtestingLambdaFunctionArn $AB_TESTING_LAMBDA_STACK 'OriginRequest' )
echo "Origin Request: $AB_TESTING_ORIGIN_REQUEST_FUNCTION"
AB_TESTING_ORIGIN_RESPONSE_FUNCTION=$( getABtestingLambdaFunctionArn $AB_TESTING_LAMBDA_STACK 'OriginResponse' )
echo "Origin Response: $AB_TESTING_ORIGIN_RESPONSE_FUNCTION"


# Check whether enabling CloudFront logging
if [ -z "$LOGS_BUCKET" ]; then
  PARAM_LOGS=""
  echo "No CloudFormation logging"
else
  PARAM_LOGS="ParameterKey=LogBucketName,ParameterValue=${LOGS_BUCKET}"
  echo "CloudFormatiomn logging enabled"
fi


# Update infra stack
# INCLUDING A/B TESTING LAMBDA FUNCTIONS
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
        ParameterKey=CdnPriceClass,ParameterValue=$CDN_PRICE_CLASS \
        ParameterKey=ABtestingViewerRequestFunctionArn,ParameterValue=$AB_TESTING_VIEWER_REQUEST_FUNCTION \
        ParameterKey=ABtestingOriginRequestFunctionArn,ParameterValue=$AB_TESTING_ORIGIN_REQUEST_FUNCTION \
        ParameterKey=ABtestingOriginResponseFunctionArn,ParameterValue=$AB_TESTING_ORIGIN_RESPONSE_FUNCTION
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
