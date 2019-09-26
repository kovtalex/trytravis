#!/bin/bash

git clone -b monolith https://github.com/express42/reddit.git
cd reddit && bundle install
cd ..

sudo cp puma.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/puma.service
sudo systemctl daemon-reload
sudo systemctl enable puma.service
