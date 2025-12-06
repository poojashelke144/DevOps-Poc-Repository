#!/bin/bash
apt-get update -y
apt-get install -y docker.io awscli ruby wget curl
systemctl start docker
systemctl enable docker

# Fetch metadata for region and AZ using the correct, full paths
REGION=$(curl -s 169.254.169.254 | grep region | cut -d\" -f4)
AZ_NAME=$(curl -s 169.254.169.254)

# ECR_REPO_URI is injected by Terraform templatefile()
ECR_REPO_URI="${ecr_repo_url_var}" 

# Login to ECR using the fetched region and expected repo URI from User Data env var
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_REPO_URI}

# Pull and run the *latest* image tag
docker stop flask_app_container || true
docker rm flask_app_container || true
docker pull ${ECR_REPO_URI}:latest
docker run -d --name flask_app_container -p 5000:5000 -e AVAILABILITY_ZONE=${AZ_NAME} ${ECR_REPO_URI}:latest

# Add ubuntu user to docker group (requires new login session to take effect interactively)
usermod -aG docker ubuntu
