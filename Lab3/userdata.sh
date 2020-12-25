#!/bin/bash
sudo apt-get update -y
sudo install apache2 -y
sleep 2
sudo service restart apache2
