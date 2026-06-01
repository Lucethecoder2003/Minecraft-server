output "instance_public_ip" {
  description = "Public IP address of the Minecraft EC2 instance"
  value       = aws_instance.minecraft.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.minecraft.id
}

output "nmap_command" {
  description = "Command to verify the Minecraft server is reachable"
  value       = "nmap -sV -Pn -p T:25565 ${aws_instance.minecraft.public_ip}"
}

output "ansible_inventory_command" {
  description = "Hint: use this IP in your Ansible inventory"
  value       = "echo '${aws_instance.minecraft.public_ip}' > ../ansible/inventory/hosts.ini"
}
