#!/bin/bash
docker stop flask_app_container || true
docker rm flask_app_container || true
AZ_NAME=$(curl -s 169.254.169.254)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ECR_REPO_URI}
docker pull ${ECR_REPO_URI}:${IMAGE_TAG}
# Pass the retrieved AZ_NAME into the container environment
docker run -d --name flask_app_container -p 5000:5000 -e AVAILABILITY_ZONE=${AZ_NAME} ${ECR_REPO_URI}:${IMAGE_TAG}
