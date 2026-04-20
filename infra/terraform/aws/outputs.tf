output "control_plane_public_ip" {
  value = aws_instance.k8s_nodes["control-plane"].public_ip
}

output "worker_public_ips" {
  value = [for key, node in aws_instance.k8s_nodes : node.public_ip if key != "control-plane"]
}

output "private_ips" {
  value = { for key, node in aws_instance.k8s_nodes : key => node.private_ip }
}

output "ssh_command_control_plane" {
  value = "ssh ubuntu@${aws_instance.k8s_nodes["control-plane"].public_ip}"
}
