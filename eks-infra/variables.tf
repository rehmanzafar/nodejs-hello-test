variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "nodejs-eks-cluster"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "email" {
  description = "Email for alerts and Let's Encrypt"
  type        = string
  default     = "m.rehmanzafar@hotmail.com"
}

variable "github_repo" {
  description = "GitHub repository in format org/repo"
  type        = string
  default     = "rehmanzafar/nodejs-hello-test"
}

variable "github_branch" {
  description = "GitHub branch name"
  type        = string
  default     = "master"
}

variable "active_color" {
  description = "Active deployment color (blue/green)"
  type        = string
  default     = "blue"
}


/* variable "aws_region" {
  default = "us-east-2"
}

variable "cluster_name" {
  default = "nodejs-eks-cluster"
}

variable "email" {
  default = "m.rehmanzafar@hotmail.com"
} */