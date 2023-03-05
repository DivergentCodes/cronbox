#!/bin/bash
#
# Git push via SSH to the EC2 instance using Instance Connect.
#
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html#ec2-instance-connect-connecting-aws-cli
#

script_dir=$(dirname "$0")
PROJECT_NAME="$(cat $script_dir/../project-name.txt)"

echo "Deploying repository to cronbox instance \"$PROJECT_NAME\" (git+ssh)"

EC2_INSTANCE_USER="git"

EC2_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters \
    "Name=instance-state-name,Values=running" \
    "Name=tag:Project,Values=$PROJECT_NAME" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)
if [[ -z $EC2_INSTANCE_ID ]]; then
  echo "Error: Failed to obtain the cronbox EC2 instance's ID"
  exit 1
fi
printf "\tEC2 ID: $EC2_INSTANCE_ID\n"

EC2_INSTANCE_IP=$(aws ec2 describe-instances \
  --filters \
    "Name=instance-state-name,Values=running" \
    "Name=tag:Project,Values=$PROJECT_NAME" \
  --query 'Reservations[*].Instances[*].PublicIpAddress' \
  --output text)
if [[ -z $EC2_INSTANCE_IP ]]; then
  echo "Error: Failed to obtain the cronbox EC2 instance's IP"
  exit 1
fi
printf "\tEC2 IP: $EC2_INSTANCE_IP\n"

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


xfer_git_push() {
  git config --add --local core.sshCommand "ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_FILE";
  git remote remove ec2;
  git remote add ec2 "$EC2_INSTANCE_USER@$EC2_INSTANCE_IP:/srv/git/$PROJECT_NAME.git";
  git push ec2 "main";
}


xfer_rsync() {
  # Transfer cron folders over rsync+ssh.
  rsync \
    -avz \
    -e "ssh -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $KEY_FILE" \
    --progress \
    "./cron" \
    "$EC2_INSTANCE_USER@$EC2_INSTANCE_IP:/home/$EC2_INSTANCE_USER/"
}


xfer_git_push;
cleanup_keys
