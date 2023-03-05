locals {

    # Read project name from a file, shared with scripts.
    project_name    = chomp(file("../project-name.txt"))

    ssm_path_prefix = "/${local.project_name}"

    tags = {
        Project     = local.project_name
        Owner       = "user"
        Environment = "dev"
        Terraform   = "true"
    }
}


################################################################################
# VPC
################################################################################


resource "aws_default_vpc" "default" {
    force_destroy = false

    tags = {
        Name = "Default VPC"
    }
}


# Security Group
resource "aws_security_group" "main" {
    description = "Security group for ${local.project_name}"
    name        = local.project_name

    vpc_id      = aws_default_vpc.default.id

    tags = merge(
        {Name = local.project_name},
        local.tags
    )
}


resource "aws_security_group_rule" "allow_inbound_ssh" {
    description       = "SSH from client to instance"
    security_group_id = aws_security_group.main.id

    type        = "ingress"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = var.allowed_cidr_blocks
}


resource "aws_security_group_rule" "allow_outbound_all" {
    description       = "Allow all traffic out"
    security_group_id = aws_security_group.main.id

    type        = "egress"
    protocol    = "all"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
}


################################################################################
# SSM
################################################################################

data "aws_kms_alias" "ssm" {
    name = "alias/aws/ssm"
}


resource "aws_ssm_parameter" "smoke_test" {
    description = "Test parameter"

    name = "${local.ssm_path_prefix}/smoke_test"
    value = "smoke-test-value-from-ssm"
    type = "SecureString"
    # key_id = aws_kms_alias.ssm.id

    tags = local.tags
}


################################################################################
# IAM
################################################################################

# Use an instance profile to apply a role to the EC2 instance.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
# https://austindewey.com/2020/10/16/configure-ec2-the-cloud-native-way-using-aws-parameter-store/

resource "aws_iam_role" "main" {
    description = "Role with permissions for EC2 cronbox"
    name        = local.project_name

    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

    tags = local.tags
}


resource "aws_iam_role_policy" "main" {
    name = local.project_name
    role = aws_iam_role.main.name
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameters",
                "ssm:DescribeParameters"
            ],
            "Resource": [
                "*",
                "${aws_ssm_parameter.smoke_test.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": [
                "${data.aws_kms_alias.ssm.arn}"
            ]
        }
    ]
}
EOF
}


resource "aws_iam_instance_profile" "main" {
    name = local.project_name
    role = aws_iam_role.main.name

    tags = local.tags
}


################################################################################
# EC2
################################################################################

data "aws_ami" "ubuntu" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
    }

    filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }

    owners = ["099720109477"] # Canonical
}


resource "aws_instance" "main" {
    ami           = data.aws_ami.ubuntu.id
    instance_type = "t1.micro"

    iam_instance_profile = aws_iam_instance_profile.main.name

    key_name               = "id_rsa_aws"
    vpc_security_group_ids = [
        aws_security_group.main.id
    ]

    user_data                   = "${file("../scripts/user-data.sh")}"
    user_data_replace_on_change = true

    tags = merge(
        {Name = local.project_name},
        local.tags
    )
}
