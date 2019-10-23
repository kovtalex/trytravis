#!/bin/bash
cd ../terraform/stage
terraform state pull | python ../../ansible/inventory.py
cd ../../ansible
