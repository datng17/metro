variable "region" {
  description = "AWS region for the prod stack."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name prefix for prod resources."
  type        = string
  default     = "metro-prod"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the prod VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "The two availability zones used by the prod VPC."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "nat_instance_type" {
  description = "Instance type for the fck-nat NAT instance."
  type        = string
  default     = "t4g.nano"
}

variable "services" {
  description = "All metro-be services. Each one gets an ECR repository metro/<service>."
  type        = list(string)
  default = [
    "auth-service",
    "cronjob-service",
    "eureka-service",
    "gateway-service",
    "notification-service",
    "order-service",
    "station-service",
    "ticket-service",
    "user-service",
  ]
}

variable "ecr_force_delete" {
  description = "Let terraform destroy delete ECR repositories that still hold images. Set to true only before teardown."
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Deletion protection on the RDS instance. Set to false before teardown."
  type        = bool
  default     = true
}

variable "rds_skip_final_snapshot" {
  description = "Skip the final RDS snapshot on destroy. When false, metro-prod-postgres-final is created."
  type        = bool
  default     = false
}

variable "db_app_username" {
  description = "PostgreSQL login role used by the services (DB_USER). Created by db-init."
  type        = string
  default     = "metro_app"
}

variable "databases" {
  description = "Service databases created by db-init."
  type        = list(string)
  default     = ["userdb", "stationdb", "ticketdb", "orderdb", "notificationdb", "cronjobdb"]
}

variable "optional_secret_names" {
  description = "Optional third-party keys stored as SSM placeholders (value \"dummy\") until set by hand."
  type        = set(string)
  default = [
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "FACEBOOK_CLIENT_ID",
    "FACEBOOK_CLIENT_SECRET",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "OPENAI_API_KEY",
    "POCKETBASE_EMAIL",
    "POCKETBASE_PASSWORD",
    "PAYPAL_CLIENT_ID",
    "PAYPAL_CLIENT_SECRET",
    "STRIPE_SECRET_KEY",
    "STRIPE_PUBLISHABLE_KEY",
    "VNPAY_TMN_CODE",
    "VNPAY_SECRET_KEY",
  ]
}

variable "cloudmap_namespace" {
  description = "Cloud Map private DNS namespace; services resolve as <name>.<namespace>."
  type        = string
  default     = "metro.local"
}

variable "image_tags" {
  description = "Optional image tag per service (e.g. { \"eureka-service\" = \"dc2eb10\" }). Services not listed use the most recently pushed image in ECR."
  type        = map(string)
  default     = {}
}

variable "rabbitmq_username" {
  description = "RabbitMQ user created on first start (RABBITMQ_USER for the services). The password is /metro/RABBITMQ_PASSWORD."
  type        = string
  default     = "metro"
}

variable "domain_name" {
  description = "Public hostname served by the ALB (Cloudflare DNS-only CNAME to the ALB DNS name)."
  type        = string
  default     = "metro.test.name.vn"
}

variable "acm_certificate_id" {
  description = "ID of the existing ACM certificate for test.name.vn and *.test.name.vn (used when acm_certificate_arn is null)."
  type        = string
  default     = "2d8782b0-3375-4fa9-842e-d4b940c53390"
}

variable "acm_certificate_arn" {
  description = "Full ACM certificate ARN for the HTTPS listener. Null builds arn:aws:acm:<region>:<account_id>:certificate/<acm_certificate_id>."
  type        = string
  default     = null
}

variable "cors_allowed_origins" {
  description = "CORS_ALLOWED_ORIGINS of the gateway: comma-separated origins, no trailing slash."
  type        = string
  default     = "https://metro.test.name.vn,https://metro-fe.vercel.app"
}

variable "gateway_desired_count" {
  description = "Number of gateway tasks behind the ALB."
  type        = number
  default     = 1
}

variable "business_desired_count" {
  description = "Number of tasks of each business service (auth, user, station, ticket, order, notification, cronjob). 0 scales them down."
  type        = number
  default     = 1
}

variable "github_repository" {
  description = "GitHub repository (<owner>/<repo>) whose workflows may assume the CI/CD roles."
  type        = string
  default     = "datng17/metro"
}

variable "github_deploy_branch" {
  description = "Branch whose workflow runs may assume the deploy role (trust subject repo:<repo>:ref:refs/heads/<branch>)."
  type        = string
  default     = "main-deployment"
}

variable "github_create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set to false if token.actions.githubusercontent.com already exists in the account."
  type        = bool
  default     = true
}

variable "github_enable_plan_role" {
  description = "Create the read-only role used by infra-ci.yml for terraform plan on pull requests."
  type        = bool
  default     = true
}
