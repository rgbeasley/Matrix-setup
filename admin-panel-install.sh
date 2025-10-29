#!/bin/bash

# Docker Installation and Synapse Admin Setup Script
# Exit on any error
set -e

# Stage tracking for error handling
STAGE="startup"
on_error() {
  local rc=$?
  echo -e "\n${RED}[ERROR]${NC} Script failed at stage: ${STAGE} (exit code ${rc})" >&2
  echo "Check the terminal output above for details." >&2
  exit ${rc}
}
trap 'on_error' ERR

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${BLUE}==>${NC} $1"; }

# Display introduction
clear
echo -e "${MAGENTA}╔═════════════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║${NC}                                                             ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}          Docker & Synapse Admin Installation Script         ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                                                             ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                Created by Garrett Beasley                 ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                        October 2025                         ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                                                             ${MAGENTA}║${NC}"
echo -e "${MAGENTA}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}This script will install and configure:${NC}"
echo -e "  ${GREEN}✓${NC} Docker Engine and associated tools"
echo -e "  ${GREEN}✓${NC} Docker Compose plugin"
echo -e "  ${GREEN}✓${NC} Synapse Admin web interface"
echo ""
echo -e "${YELLOW}Requirements:${NC}"
echo -e "  • Root/sudo access"
echo -e "  • Active internet connection"
echo -e "  • Ubuntu/Debian Linux distribution"
echo ""
echo -e "${CYAN}Estimated installation time: <3 minutes${NC}"
echo ""
read -p "Press Enter to begin installation or Ctrl+C to cancel..."
echo ""


# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run with root privileges (use sudo)"
   exit 1
fi

# Get LAN IP address
LAN_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
if [[ -z "$LAN_IP" ]]; then
    LAN_IP="127.0.0.1"
fi

# Check if Docker is installed and stop Synapse container if running
STAGE="close_processes"
print_header "Closing conflicting processes..."
systemctl stop docker >/dev/null 2>&1 || true
# Remove old Docker packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -yqq $pkg >/dev/null 2>&1 || true
done
print_success "Conflicting processes closed"

# Update package list
STAGE="updating_package_list"
print_header "Updating package list..."
apt-get update -qq
print_success "Package list updated"

# Install prerequisites
STAGE="installing_prerequisites"
print_header "Installing prerequisites..."
apt-get install -y ca-certificates curl >/dev/null 2>&1
print_success "Prerequisites installed"

# Setup Docker GPG key
STAGE="setting_up_gpg_key"
print_header "Setting up Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
print_success "GPG key configured"

# Add Docker repository
STAGE="adding_docker_repository"
print_header "Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
print_success "Docker repository added"

# Update package list with Docker repository
STAGE="updating_with_docker_repo"
print_header "Updating package list with Docker repository..."
apt-get update -qq
print_success "Package list updated"

# Install Docker
STAGE="installing_docker"
print_header "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
print_success "Docker installed successfully"

# Check and start Docker
STAGE="starting_docker"
print_header "Starting Docker..."
systemctl start docker
print_success "Docker service started"

# Display Docker status
STAGE="checking_docker_status"
print_header "Checking Docker status... \n"
systemctl status docker --no-pager --lines=0
echo ""
print_success "Docker service started"

# Run Synapse Admin container
STAGE="deploying_synapse_admin"
print_header "Deploying Synapse Admin container..."
docker run -d -p 8080:80 awesometechnologies/synapse-admin >/dev/null 2>&1
print_success "Synapse Admin container deployed"

# Final summary
STAGE="summary"
print_header "Installation Summary"
echo -e "==============================================================="
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  1. Access Synapse Admin at ${CYAN}http://$LAN_IP:8080${NC}"
echo -e "  2. Login using admin user credentials"
echo -e "     - use ${CYAN}sudo python3 register_new_matrix_user.py -c "/etc/matrix-synapse/homeserver.yaml"${NC}"
echo -e "       to create an admin user if you haven't already"
echo -e "  3. Connect to your Matrix homeserver using host address:port"
echo -e "  4. Use the admin interface to manage users and settings"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo -e "  - Check Docker status: ${CYAN}sudo systemctl status docker${NC}"
echo -e "  - View containers: ${CYAN}sudo docker ps${NC}"
echo -e "  - Stop Synapse Admin: ${CYAN}sudo docker stop <container_id/container_name>${NC}"
echo ""
echo -e "==============================================================="