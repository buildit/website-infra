#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/includes/functions

loadConfig $1

CF_TEMPLATE=file://$DIR/cloudformation/website-infra.yml
STACK_NAME=$( infraStackName $ENV_NAME )
AB_TESTING_LAMBDA_STACK=$( abTestingLambdaStackName $ENV_NAME ) 
echo "Lambda Stack: $AB_TESTING_LAMBDA_STACK"

# Infra stack must exist
failIfStackDoesNotExist $STACK_NAME $RESOURCES_REGION

# Static Website Hosting endpoint for the Experiment bucket
# (Used for Custom origin only, but always available)
AB_EXPERIMENT_BUCKET_STATIC_ENDPOINT=$( getStackOutput $STACK_NAME $RESOURCES_REGION 'WebsiteExperimentBucketStaticHostingEndpoint' )

# S3 endpoing for the Experiment bucket
# (Used for S3 Origin only, but always available)
AB_EXPERIMENT_BUCKET_ENDPOINT=$( getStackOutput $STACK_NAME $RESOURCES_REGION 'WebsiteExperimentBucketDomainName' )

# Check whether making A/B testing available
if [ -z "$AB_EXPERIMENT_BUCKET" ]; then
  echo "No A/B testing abailable!"
  exit 1
else
  source $DIR/includes/deployABtestingLambda
fi


# Lambda stack must now exist, in us-east-1
failIfStackDoesNotExist $AB_TESTING_LAMBDA_STACK "us-east-1"


# Retrieve OriginRequest Lambda function ARN from the Lambda stack
    # No way of directly referencing Outputs from this stack from the website-infra stack unless the website is deployed in us-east-1. 
    # CloudFormation does not support ImportValue from different Regions
AB_TESTING_ORIGIN_REQUEST_FUNCTION=$( getStackOutput $AB_TESTING_LAMBDA_STACK 'us-east-1' 'OriginRequestLambdaFunctionQualifiedArn' )
echo "Origin Request: $AB_TESTING_ORIGIN_REQUEST_FUNCTION"


# Check whether enabling CloudFront logging
if [ -z "$LOGS_BUCKET" ]; then
  PARAM_LOGS=""
  echo "- No CloudFormation logging"
else
  PARAM_LOGS="ParameterKey=LogBucketName,ParameterValue=${LOGS_BUCKET}"
  echo "- CloudFormatiomn logging enabled"
fi


# Update infra stack, with A/B testing lambda function
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
        ParameterKey=ABtestingOriginRequestFunctionArn,ParameterValue=$AB_TESTING_ORIGIN_REQUEST_FUNCTION
    # Passing ABtestingOriginRequestFunctionArn attaches A/B testing lambda function
    # SiteExperimentBucketName is not optional
if [ $? -ne 0 ]; then
    showCloudformationFailureMessage 'update-stack' $STACK_NAME
    exit 1
fi

# Wait until stack create/update is complete
waitCloudFormation $STACK_NAME $RESOURCES_REGION stack-update-complete "it may take tenths of minutes"

STACK_STATUS=$( getStackStatus $STACK_NAME $RESOURCES_REGION )
echo "Stack Status: $STACK_STATUS"

# Invalidate Distribution
echo "Invalidate CloudFront Distribution cache"
DISTRIBUTION_ID=$( getStackOutput $STACK_NAME $RESOURCES_REGION 'DistributionID' )
INVALIDATION_ID=$( createCloudfrontInvalidation $DISTRIBUTION_ID )
waitForInvalidationCompleted $DISTRIBUTION_ID $INVALIDATION_ID

# Show stack outputs
showStackOutputs $STACK_NAME $RESOURCES_REGION
