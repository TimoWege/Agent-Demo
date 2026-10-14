output "instance_1_public_ip" {
  value = aws_instance.instance1.public_ip
}

output "instance_2_public_ip" {
  value = aws_instance.instance2.public_ip
}

output "get_admin_password_1" {
  description = "Run this once the instance has finished booting (password generation can take a few minutes)"
  value       = "aws ec2 get-password-data --region ${var.aws_region} --instance-id ${aws_instance.instance1.id} --priv-launch-key ${local_file.private_key.filename} --query PasswordData --output text"
}

output "get_admin_password_2" {
  description = "Run this once the instance has finished booting (password generation can take a few minutes)"
  value       = "aws ec2 get-password-data --region ${var.aws_region} --instance-id ${aws_instance.instance2.id} --priv-launch-key ${local_file.private_key.filename} --query PasswordData --output text"
}

output "rdp_instance_1" {
  description = "Opens a windowed RDP session to the first instance; password is fetched live, no prompt."
  value       = local_file.connect_instance1.filename
}

output "rdp_instance_2" {
  description = "Opens a windowed RDP session to the second instance; password is fetched live, no prompt."
  value       = local_file.connect_instance2.filename
}

output "ssh_instance_1" {
  description = "SSH to the first instance as Administrator (password auth, same password as RDP)."
  value       = "ssh Administrator@${aws_instance.instance1.public_ip}"
}

output "ssh_instance_2" {
  description = "SSH to the second instance as Administrator (password auth, same password as RDP)."
  value       = "ssh Administrator@${aws_instance.instance2.public_ip}"
}
