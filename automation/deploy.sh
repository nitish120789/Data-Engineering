#!/bin/bash

echo "Running Terraform..."
cd infrastructure/terraform
terraform init
terraform apply -auto-approve

echo "Running Ansible..."
cd ../ansible
ansible-playbook playbook.yml
