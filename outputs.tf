output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.flask_alb.dns_name
}

data "aws_instances" "app_instances" {
  filter {
    name   = "tag:Name"
    values = ["flask-docker-instance"]
  }

  instance_tags = {
    Name = "flask-docker-instance"
  }
}

output "instance_public_ips" {
  description = "Public IPs of all EC2 instances (for debugging via SSH)"
  value       = data.aws_instances.app_instances.public_ips
}

output "ssh_command_prefix" {
  description = "SSH connection command prefix (use with the IPs above)"
  value       = "ssh -i ec2_id_rsa ubuntu@"
}
