#!/bin/bash
cd ../terraform/stage
terraform state pull | python ../../ansible/jsons.py
cd ../../ansible
