#!/bin/bash
#
# SSH to the EC2 instance using Instance Connect.
#
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html#ec2-instance-connect-connecting-aws-cli
#

echo "Logging into instance with EC2 Instance Connect"

script_dir=$(dirname "$0")
PROJECT_NAME="$(cat $script_dir/../project-name.txt)"

EC2_INSTANCE_USER="ubuntu"

EC2_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running Name=tag:Project,Values="$PROJECT_NAME" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

EC2_INSTANCE_IP=$(aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=running Name=tag:Project,Values="$PROJECT_NAME" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' \
  --output text)

KEY_FILE="one_time_key"


cleanup_keys() {
    if [[ -f "$KEY_FILE" ]]; then rm "$KEY_FILE"; fi
    if [[ -f "$KEY_FILE.pub" ]]; then rm "$KEY_FILE.pub"; fi
}


cleanup_keys;
ssh-keygen -t rsa -b 2048 -q -N "" -f "$KEY_FILE";


aws ec2-instance-connect send-ssh-public-key \
  --no-cli-auto-prompt \
  --no-cli-pager \
  --no-paginate \
  --instance-os-user "$EC2_INSTANCE_USER" \
  --instance-id "$EC2_INSTANCE_ID" \
  --ssh-public-key "file://$KEY_FILE.pub"


ssh \
  -o "IdentitiesOnly=yes" \
  -o "StrictHostKeyChecking=no" \
  -i "$KEY_FILE" \
  "$EC2_INSTANCE_USER@$EC2_INSTANCE_IP"


cleanup_keys
