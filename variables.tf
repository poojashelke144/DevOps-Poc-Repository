variable "aws_region" {
  description = "The AWS region to deploy in"
  default     = "us-east-1" # Set your preferred region
}

variable "source_code_repo_url" {
  description = "URL of your GitHub repository (HTTPS format)"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token for CodePipeline access"
  type        = string
  sensitive   = true
}

variable "github_branch" {
  description = "GitHub branch to track"
  default     = "main"
}
