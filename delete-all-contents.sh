#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/includes/functions

loadConfig $1

# Empty
echo "Emptying Main site bucket..."
aws s3 rm s3://$SITE_BUCKET --recursive --region $RESOURCES_REGION

# Empty experiment bucket, if any
if [ ! -z "$AB_EXPERIMENT_BUCKET" ]; then
  echo "Emptying A/B testing Experiment site bucket..."
  aws s3 rm s3://$AB_EXPERIMENT_BUCKET --recursive --region $RESOURCES_REGION  
fi

# Empty logging bucket, if any
if [ ! -z "$LOGS_BUCKET" ]; then
  echo "Emptying Logs bucket bucket..."
  aws s3 rm s3://$LOGS_BUCKET --recursive --region $RESOURCES_REGION  
fi
