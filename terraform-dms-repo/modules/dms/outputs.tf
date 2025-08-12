output "replication_instance_arn" {
  description = "ARN of the DMS replication instance"
  value       = aws_dms_replication_instance.this.replication_instance_arn
}

output "replication_subnet_group_id" {
  description = "Replication subnet group ID"
  value       = aws_dms_replication_subnet_group.this.replication_subnet_group_id
}

output "source_endpoint_arn" {
  description = "Source DMS endpoint ARN"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "Target DMS endpoint ARN"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "replication_task_arn" {
  description = "Replication task ARN"
  value       = aws_dms_replication_task.this.replication_task_arn
}
