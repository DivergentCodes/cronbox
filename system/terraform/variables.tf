variable "aws_region" {
    description = "Region for AWS resources"
    type        = string
    default     = "us-east-1"
}


variable "allowed_cidr_blocks" {
    description = "IP ranges allowed to access the instance"
    type        = list
    default     = [
        "0.0.0.0/0"
    ]
}

