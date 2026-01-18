output "vm_names" {
  value = sort(keys(var.vms))
}
