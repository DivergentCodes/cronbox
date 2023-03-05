#!/bin/bash

echo "Tearing down cronbox instance with Terraform"
script_dir=$(dirname "$0")
tf_dir="$script_dir/../terraform"
cd "$tf_dir"
terraform destroy
