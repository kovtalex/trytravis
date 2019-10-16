#!/bin/bash
rm -f terraform.status
cd ../terraform/stage
terraform state pull > ../../ansible/terraform.status
cd ../../ansible
python  jsons.py
rm -f terraform.status
