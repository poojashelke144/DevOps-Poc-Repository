terraform {
  required_providers {
    aws = { source = "hashicorp/aws"
    version = "~> 5.0" 
    }
    tls = { 
    source = "hashicorp/tls"
    version = "~> 4.0"
    } 
    local = {
         source = "hashicorp/local"
         version = "~> 2.0" 
    }
  }
}

locals {
  codebuild_env_vars = {
    ECR_REPO_URI       = aws_ecr_repository.flask_repo.repository_url
    REPO_NAME          = aws_ecr_repository.flask_repo.name
    AWS_DEFAULT_REGION = var.aws_region
  }
}

provider "aws" {
  region = var.aws_region
}

# --- 2. Networking (VPC, Subnets, ALB) ---

resource "aws_vpc" "main" { 
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true 
    }
data "aws_availability_zones" "available" {
     state = "available" 
     }
resource "aws_subnet" "public" {
  count = 2
  cidr_block = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id = aws_vpc.main.id
   map_public_ip_on_launch = true
}
resource "aws_internet_gateway" "gw" { 
    vpc_id = aws_vpc.main.id 
    }
resource "aws_route_table" "public" { 
    vpc_id = aws_vpc.main.id
 route {
     cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.gw.id 
 } 
 }
resource "aws_route_table_association" "public" { 
    count = 2 
    subnet_id = aws_subnet.public[count.index].id
     route_table_id = aws_route_table.public.id
      }

resource "aws_security_group" "web_sg" {
  name = "web_sg"
  vpc_id = aws_vpc.main.id
  ingress { 
    from_port = 80 
    to_port = 80 
    protocol = "tcp" 
    cidr_blocks = ["0.0.0.0/0"] 
    }
  ingress {
     from_port = 5000
      to_port = 5000 
      protocol = "tcp" 
      self = true 
      }
  ingress {
     from_port = 22 
     to_port = 22 
     protocol = "tcp" 
     cidr_blocks = ["0.0.0.0/0"] 
     } # WARNING: Restrict this CIDR to your IP
  egress { 
    from_port = 0 
    to_port = 0
     protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
     }
}

resource "aws_lb" "flask_alb" {
  name = "flask-docker-alb" 
  load_balancer_type = "application"
  security_groups = [aws_security_group.web_sg.id]
  subnets = aws_subnet.public[*].id
}
resource "aws_lb_target_group" "app_tg" {
  name = "flask-docker-tg"
  port = 5000
   protocol = "HTTP"
  vpc_id = aws_vpc.main.id
  health_check { 
    path = "/"
    protocol = "HTTP" 
    }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.flask_alb.arn
  port = 80
   protocol = "HTTP"
    default_action { 
        target_group_arn = aws_lb_target_group.app_tg.arn
     type = "forward"
     }
}

# --- 3. ECR Repository ---
resource "aws_ecr_repository" "flask_repo" {
  name = "flask-app-repo"
  force_delete = true 
}

# --- 4. EC2 Instance Setup (ASG, Launch Template) ---

resource "aws_iam_role" "ec2_role" {
  name = "ec2-docker-codedeploy-role" # Renamed to generic EC2 role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

# Policy needed for EC2 instances to pull from ECR and use the metadata service
resource "aws_iam_role_policy_attachment" "ecr_readonly_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# IMPORTANT: You must attach this role to EC2 instances via an Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-docker-codedeploy-profile"
  role = aws_iam_role.ec2_role.name
}


data "aws_ami" "ubuntu" { 
    most_recent = true
     filter { 
        name = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] 
        }
         owners = ["099720109477"] 
    }

resource "aws_launch_template" "flask_lt" {
  name_prefix   = "flask-docker-lt"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Free tier instance type
  key_name      = "eks-keypair"
  iam_instance_profile { arn = aws_iam_instance_profile.ec2_profile.arn }
    # Use HCL Heredoc to embed the script content directly.
  # We use standard Terraform interpolation for the ECR URL only.
  user_data     = base64encode(<<EOF
#!/bin/bash
# Stop and disable codedeploy-agent if it tries to run
systemctl stop codedeploy-agent || true
systemctl disable codedeploy-agent || true
apt-get update -y
apt-get install -y docker.io awscli ruby wget curl
systemctl start docker
systemctl enable docker

REGION="${var.aws_region}"
AZ_NAME="unknown-az" 

# Logic to fetch AZ using IMDSv2 and robust curl commands (using $$ for Terraform escape)
TOKEN=$(curl -X PUT "169.254.169.254" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
if [ $? -eq 0 ]; then
    NEW_AZ_NAME=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" 169.254.169.254)
    if [ -n "$${NEW_AZ_NAME}" ]; then
        AZ_NAME=$${NEW_AZ_NAME}
    fi
fi

ECR_REPO_URI="${aws_ecr_repository.flask_repo.repository_url}" 

# The following commands use ECR_REPO_URI correctly for the pull/run
# Note: These commands are initially run at launch time
aws ecr get-login-password --region $${REGION} | docker login --username AWS --password-stdin $${ECR_REPO_URI}
docker stop flask_app_container || true
docker rm flask_app_container || true
docker pull $${ECR_REPO_URI}:latest
# This line sets the environment variable for the container
docker run -d --name flask_app_container -p 5000:5000 -e AVAILABILITY_ZONE=$${AZ_NAME} $${ECR_REPO_URI}:latest

usermod -aG docker ubuntu
EOF
  )
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}


resource "aws_autoscaling_group" "flask_asg" { 
  min_size = 2
  max_size = 2
  desired_capacity = 2
  target_group_arns = [aws_lb_target_group.app_tg.arn]
  vpc_zone_identifier = aws_subnet.public[*].id
  launch_template {
  id = aws_launch_template.flask_lt.id
  version = "$Latest" 
  }
  tag { 
    key = "Name"
    value = "flask-docker-instance"
    propagate_at_launch = true 
    }
}

# --- 5. CI/CD Pipeline Resources (S3, CodeBuild, CodePipeline) ---

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "flask-app-docker-artifacts-${aws_vpc.main.id}" 
  force_destroy = true 
}

# IAM Role for CodePipeline Service
resource "aws_iam_role" "codepipeline_flask_role" {
  name = "codepipeline-flask-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy" {
  role       = aws_iam_role.codepipeline_flask_role.name
  # Corrected ARN
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_s3_access_policy" {
  role       = aws_iam_role.codepipeline_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild_attachment" {
  role       = aws_iam_role.codepipeline_flask_role.name
  policy_arn = aws_iam_policy.codepipeline_codebuild_policy.arn
}

# IAM Role for BOTH CodeBuild projects (Builder and Deployer)
resource "aws_iam_role" "codebuild_docker_flask_role" {
  name = "codebuild-docker-flask-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_managed_access" {
  role       = aws_iam_role.codebuild_docker_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildDeveloperAccess" 
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.codebuild_docker_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_access" {
  role       = aws_iam_role.codebuild_docker_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_cloudwatch_access" {
  role       = aws_iam_role.codebuild_docker_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}


# Policy attachment needed for the DEPLOYER CodeBuild project to modify ASG
resource "aws_iam_role_policy_attachment" "codebuild_asg_access" {
  role       = aws_iam_role.codebuild_docker_flask_role.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

resource "aws_iam_policy" "codepipeline_codebuild_policy" {
  name        = "codepipeline-codebuild-invoke-policy"
  description = "Allows CodePipeline to start and monitor CodeBuild projects"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:BatchGetBuilds"
        ]
        Resource = [
          aws_codebuild_project.app_build.arn,
          aws_codebuild_project.app_deployer.arn
        ]
      },
    ]
  })
}


# BUILDER CodeBuild Project
resource "aws_codebuild_project" "app_build" {
  name           = "FlaskAppDockerBuild"
  service_role   = aws_iam_role.codebuild_docker_flask_role.arn # Corrected reference
  
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true 

    dynamic "environment_variable" {
      for_each = local.codebuild_env_vars
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }
  source {
    type            = "CODEPIPELINE" # Changed to CODEPIPELINE
    # Removed location/auth block
    buildspec       = "buildspec.yml"
  }
  artifacts {
    type = "CODEPIPELINE" # Changed to NO_ARTIFACTS
  }
}


# DEPLOYER CodeBuild Project (New Resource)
resource "aws_codebuild_project" "app_deployer" {
  name           = "FlaskAppASGDeployer"
  service_role   = aws_iam_role.codebuild_docker_flask_role.arn
  
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"

    environment_variable {
      name  = "ASG_NAME"
      value = aws_autoscaling_group.flask_asg.name # Pass the ASG name to the deploy script
    }
  }

  source {
    type      = "CODEPIPELINE"
    # buildspec file path must be relative to the source root
    buildspec = "app/scripts/deploy_buildspec.yml" 
  }
  
  artifacts {
    type = "CODEPIPELINE"
  }
}


# --- 6. CodePipeline Orchestrator ---

resource "aws_codepipeline" "flask_pipeline" {
  name     = "FlaskAppDockerPipeline"
  role_arn = aws_iam_role.codepipeline_flask_role.arn # Corrected reference

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "SourceFromGitHub"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["SourceArtifact"]
      configuration = {
        # Corrected string extraction using element() and split()
        Owner      = element(split("/", replace(var.source_code_repo_url, ".git", "")), 3)
        Repo       = element(split("/", replace(var.source_code_repo_url, ".git", "")), 4)
        Branch     = var.github_branch
        OAuthToken = var.github_token
        PollForSourceChanges = false 
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "CodeBuildAndPush"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = [] # No output artifacts from build stage
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.app_build.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name             = "TriggerASGRollingUpdate"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"] # Pass Source artifacts to access asg_deploy.sh
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.app_deployer.name
      }
    }
  }
}
