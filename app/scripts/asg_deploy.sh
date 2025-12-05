#!/bin/bash
echo "Starting Auto Scaling Group instance refresh..."
# This command forces the ASG to terminate old instances and launch new ones
aws autoscaling start-instance-refresh --auto-scaling-group-name ${ASG_NAME}
echo "Instance refresh command issued to ASG: ${ASG_NAME}"
