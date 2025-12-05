output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.flask_alb.dns_name

}

output "instance_public_ips" {
  description = "Public IPs of all EC2 instances (for debugging via SSH)"
  # This output requires you to add a data source to fetch instance IPs if ASG doesn't expose them directly
  value       = aws_autoscaling_group.flask_asg.instances[*].public_ips 
}

output "ssh_command_prefix" {
  description = "SSH connection command prefix (use with the IPs above)"
  value       = "ssh -i ec2_id_rsa ubuntu@"
}
