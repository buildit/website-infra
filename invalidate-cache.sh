#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions

loadConfig $1

STACK_NAME=$( infraStackName $ENV_NAME )

# Invalidate Distribution
echo "Invalidate CloudFront Distribution cache"
DISTRIBUTION_ID=$( getStackExport $STACK_NAME $RESOURCES_REGION 'DistributionID' )
INVALIDATION_ID=$( createCloudfrontInvalidation $DISTRIBUTION_ID )
waitForInvalidationCompleted $DISTRIBUTION_ID $INVALIDATION_ID
