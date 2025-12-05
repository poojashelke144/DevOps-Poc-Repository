#!/bin/bash
# Make sure this is line 1, column 1
echo "Starting Auto Scaling Group instance refresh..."
aws autoscaling start-instance-refresh --auto-scaling-group-name ${ASG_NAME}
echo "Instance refresh command issued to ASG: ${ASG_NAME}"
