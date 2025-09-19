output "replication_instance_arn" {
  value = module.dms.replication_instance_arn
}

output "source_endpoint_arns" {
  value = module.dms.source_endpoint_arns
}

output "target_endpoint_arns" {
  value = module.dms.target_endpoint_arns
}

output "replication_task_arns" {
  value = module.dms.replication_task_arns
}

output "premigration_assessment_task_arns" {
  value = module.dms.premigration_assessment_task_arns
}
