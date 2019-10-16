#!/bin/bash
cd ../terraform/stage
terraform state pull | python  jsons.py
cd ../../ansible
