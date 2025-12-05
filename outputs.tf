output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.flask_alb.dns_name
}

// FIX START: Add a data source and update the output block

data "aws_instances" "app_instances" {
  # Filter instances that belong to the ASG's launch template configuration
  filter {
    name   = "tag:Name"
    values = ["flask-docker-instance"]
  }

  # Ensure we look up the IDs for the instances that are actually running
  instance_tags = {
    Name = "flask-docker-instance"
  }
}


output "instance_public_ips" {
  description = "Public IPs of all EC2 instances (for debugging via SSH)"
  # Reference the data source to get the list of public IPs
  value       = data.aws_instances.app_instances.public_ips
}

// FIX END: End of changes

output "ssh_command_prefix" {
  description = "SSH connection command prefix (use with the IPs above)"
  value       = "ssh -i ec2_id_rsa ubuntu@"
}
