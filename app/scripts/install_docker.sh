#!/bin/bash
apt-get update -y
apt-get install -y docker.io awscli ruby wget curl
systemctl start docker
systemctl enable docker
wget aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com
chmod +x ./install
./install auto
usermod -aG docker ubuntu 
