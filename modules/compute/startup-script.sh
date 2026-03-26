#!/bin/bash
# Startup script for GCP VM instances
# This script runs on first boot and instance restarts

set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $(whoami)
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install Git
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    apt-get install -y git
fi

# Install Python 3 and pip
if ! command -v python3 &> /dev/null; then
    echo "Installing Python 3..."
    apt-get install -y python3 python3-pip
fi

# Install monitoring agent (optional)
echo "Installing Google Cloud Ops Agent..."
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Create application directory
mkdir -p /opt/grading-app
chown -R $(whoami):$(whoami) /opt/grading-app

# Set environment
echo "export ENVIRONMENT=${environment}" >> /etc/environment

echo "Startup script completed successfully"
