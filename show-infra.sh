#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/scripts/functions

loadConfig $1

STACK_NAME="${ENV_NAME}-infra"

# Show stack outputs
showStackOutput $STACK_NAME $RESOURCES_REGION
