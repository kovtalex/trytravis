#!/bin/bash
set -e

#Install uby
apt update
apt install -y ruby-full ruby-bundler build-essential
