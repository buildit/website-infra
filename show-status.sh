#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/includes/functions

loadConfig $1

function show {
    local STACK=$1
    local REGION=$2
    echo ""
    echo "Stack: $STACK"
    echo "Status: $( getStackStatus $STACK $REGION )"
    showStackOutputs $STACK $REGION
}


show $( infraStackName $ENV_NAME ) $RESOURCES_REGION
show $( dnsStackName $ENV_NAME ) $RESOURCES_REGION
show $( abTestingLambdaStackName $ENV_NAME ) 'us-east-1'
