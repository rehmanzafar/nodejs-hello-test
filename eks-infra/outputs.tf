output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = var.aws_region
}

#output "github_oidc_provider_arn" {
#  description = "ARN of the GitHub OIDC provider"
#  value       = aws_iam_openid_connect_provider.github.arn
#}

#output "github_oidc_provider_url" {
#  description = "URL of the GitHub OIDC provider"
#  value       = aws_iam_openid_connect_provider.github.url
#}

#output "cert_manager_status" {
#  value = helm_release.cert_manager.status
#}

#output "cloudwatch_log_group" {
#  value = "/aws/containerinsights/${var.cluster_name}/application"
#}