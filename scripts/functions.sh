# Common functions

function infraStackName {
    local ENVIRONMENT_NAME=$1
    echo "${ENVIRONMENT_NAME}-infra"
}

function dnsStackName {
    local ENVIRONMENT_NAME=$1
    echo "${ENVIRONMENT_NAME}-dns"
}

function abTestingLambdaStackName {
    local ENVIRONMENT_NAME=$1
    echo "ab-testing-${ENVIRONMENT_NAME}"
}

function loadConfig {
    CFG_FILE=$1

    if [ -z "$CFG_FILE" ] || [ -f "$CFG_FILE" ] ; then
        echo "Load config from $CFG_FILE"
        source $CFG_FILE
    else
        echo "Cannot find configuration file"
        ME=`basename "$0"`
        echo "usage:"
        echo "  $ME <environment-cfg-file>"
        
        exit 1
    fi
}


function waitCloudFormation {
    local STACK_NAME=$1
    local RESOURCES_REGION=$2
    local WAIT_CMD=$3
    local HOW_LONG=$4

    echo "Waiting until CloudFormation operation completes... $HOW_LONG"
    aws cloudformation  wait $WAIT_CMD --stack-name $STACK_NAME --region $RESOURCES_REGION --no-paginate
    echo "...done"
}

function waitStackExists {
    local STACK_NAME=$1
    local RESOURCES_REGION=$2

    echo "Checking if stack $STACK_NAME exists in $RESOURCES_REGION"
    aws cloudformation  wait stack-exists --stack-name $STACK_NAME --region $RESOURCES_REGION  > /dev/null 2>&1 
    if [ $? -ne 0 ]; then
        echo "Cannot find CloudFormation stack $STACK_NAME in Region $RESOURCES_REGION" 
        exit 1
    else
        echo "CloudFormation stack $STACK_NAME found in Region $RESOURCES_REGION"
    fi    
}

function checkIfStackExists {
    local STACK=$1
    local REGION=$2
    aws cloudformation describe-stacks --stack-name $STACK --region $REGION > /dev/null 2>&1 
}

function failIfCertificateDoesNotExistInUsEast1 {
    local CERT_ARN=$1

    aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1  > /dev/null 2>&1 
    if [ $? -ne 0 ]; then
        echo "Certificate $CERT_ARN must exist Region us-east-1" 
        exit 1
    fi    
}

function failIfStackDoesNotExist {
    local STACK=$1
    local REGION=$2

    aws cloudformation describe-stacks --stack-name $STACK --region $REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "CloudFormation stack $STACK does not exist in $REGION"
        exit 1
    fi    
}

function getStackStatus {
    local STACK=$1
    local REGION=$2
    aws cloudformation describe-stacks --stack-name $STACK --region $REGION \
        --query 'Stacks[0].StackStatus' \
        --output text
}

function getStackOutput {
    local STACK=$1
    local REGION=$2
    aws cloudformation describe-stacks --stack-name $STACK --region $REGION \
        --query 'Stacks[0].Outputs[*].{Output:OutputKey,Value:OutputValue}' \
        --output table
}

function getABtestingLambdaFunctionArn {
    local LAMBDA_STACK=$1
    local FUNCTION_NAME=$2
    aws cloudformation describe-stacks --stack-name $LAMBDA_STACK \  
        --region us-east-1  \
        --query "Stacks[0].Outputs[?OutputKey=='${FUNCTION_NAME}LambdaFunctionQualifiedArn'].OutputValue" \
        --output text
}