#!/bin/bash

STACK_NAME=XeMirrorBuild

aws cloudformation create-stack --stack-name $STACK_NAME --template-body file://xe_mirror_cf_template.yaml --capabilities CAPABILITY_IAM
echo "Waiting for the stack to come up..."
aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
