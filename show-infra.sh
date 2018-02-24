#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions.sh

loadConfig $1

STACK_NAME=$( infraStackName $ENV_NAME ) 

# Show stack outputs
getStackOutput $STACK_NAME $RESOURCES_REGION
