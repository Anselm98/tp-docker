#!/bin/bash

# Initialize the database
mysql -u root -pmichel <<EOF
CREATE DATABASE IF NOT EXISTS webserverdb;

# Add any additional initialization commands here
EOF

# Exit the script
exit 0