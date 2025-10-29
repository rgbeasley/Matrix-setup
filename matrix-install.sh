#!/bin/bash

# Exit on error
set -e

# Error handling: record stage and report on failure
STAGE="startup"
on_error() {
  local rc=$?
  echo -e "\n[ERROR] Script failed at stage: ${STAGE} (exit code ${rc})" >&2
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
echo -e "${MAGENTA}║${NC}          Matrix Synapse Server Installation Script${NC}          ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                                                             ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}              Created by Garrett Beasley${NC}                  ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                        October 2025${NC}                         ${MAGENTA}║${NC}"
echo -e "${MAGENTA}║${NC}                                                             ${MAGENTA}║${NC}"
echo -e "${MAGENTA}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}This script will install and configure:${NC}"
echo -e "  ${GREEN}✓${NC} Matrix-Synapse homeserver"
echo -e "  ${GREEN}✓${NC} System updates and security (UFW firewall)"
echo -e "  ${GREEN}✓${NC} PostgreSQL database server"
echo -e "  ${GREEN}✓${NC} User creation script"
echo ""
echo -e "${YELLOW}Requirements:${NC}"
echo -e "  • Root/sudo access"
echo -e "  • Active internet connection"
echo ""
echo -e "${YELLOW}You will be prompted for:${NC}"
echo -e "  1. New system user creation"
echo -e "  2. PostgreSQL database password (for 'synapse' user)"
echo -e "  3. Matrix server name (must match your domain/subdomain)"
echo ""
echo -e "${CYAN}Estimated installation time: 5-10 minutes${NC}"
echo ""
read -p "Press Enter to begin installation or Ctrl+C to cancel..."
echo ""

# Check if running as root
# Ensure the script is run as root for required permissions
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

STAGE="update_upgrade"
# Update and upgrade system packages for security and stability
print_header "Updating and upgrading system..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -qq -y > /dev/null 2>&1
print_success "System updated"

STAGE="configure_firewall"
# Enable UFW firewall and allow SSH for secure remote access
print_header "Configuring firewall..."
ufw --force enable > /dev/null 2>&1 && ufw allow ssh > /dev/null 2>&1
print_success "Firewall configured"

STAGE="create_user"
# Prompt for and create a new system user with sudo privileges
print_header "Creating new user and adding to sudo group..."
# Prompt for username
while true; do
  read -p "Enter new username: " USERNAME
  if [[ -z "$USERNAME" ]]; then
    print_warning "Username cannot be empty"
    continue
  fi
  if [[ "$USERNAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    # Check if user already exists
    if id "$USERNAME" &>/dev/null; then
      print_warning "User '$USERNAME' already exists"
      read -p "Continue with existing user? (y/n): " response
      if [[ "$response" =~ ^[Yy]$ ]]; then
        USER_EXISTS=true
        break
      fi
      continue
    fi
    break
  fi
  print_warning "Invalid username: '$USERNAME' - please enter a valid username."
done

if [[ "$USER_EXISTS" != true ]]; then
    adduser --gecos "" $USERNAME
    usermod -aG sudo $USERNAME
    print_success "User '$USERNAME' has been created with sudo privileges."
else
    print_info "Using existing user '$USERNAME'"
    usermod -aG sudo $USERNAME 2>/dev/null || true
fi
print_success "User setup complete"

STAGE="install_postgresql"
# Install PostgreSQL server and client packages
print_header "Installing PostgreSQL..."
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y postgresql postgresql-client > /dev/null 2>&1
print_success "PostgreSQL installed"

STAGE="postgres_status"
# Display and verify PostgreSQL service status
print_header "PostgreSQL Status:"
systemctl status postgresql --no-pager

# Wait for PostgreSQL to be ready
print_info "Waiting for PostgreSQL to be ready..."
sleep 3
for i in {1..10}; do
    if sudo -u postgres psql -c '\q' 2>/dev/null; then
        break
    fi
    if [[ $i -eq 10 ]]; then
        print_error "PostgreSQL did not start properly"
        exit 1
    fi
    sleep 2
done
print_success "PostgreSQL is ready"

STAGE="setup_postgres_db"
# Create or update the 'synapse' user and database for Matrix
cd /tmp
print_header "Setting up PostgreSQL user and database for Synapse..."

# Check if user already exists
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='synapse'" | grep -q 1; then
    print_warning "PostgreSQL user 'synapse' already exists"
    read -p "Drop and recreate? (y/n): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS synapse;" 2>/dev/null || true
        sudo -u postgres psql -c "DROP USER IF EXISTS synapse;" 2>/dev/null || true
    else
        print_info "Keeping existing database, updating password"
        sudo -u postgres psql -c "ALTER USER synapse WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || true
        SKIP_DB_CREATE=true
    fi
fi

# Prompt for database password with validation
echo ""
while true; do
  read -sp "Enter password for Synapse database user: " DB_PASSWORD
  echo
  if [[ -z "$DB_PASSWORD" ]]; then
    print_warning "Password cannot be empty"
    continue
  fi
  read -sp "Confirm password: " DB_PASSWORD_CONFIRM
  echo
  if [[ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]]; then
    print_warning "Passwords do not match"
    continue
  fi
  break
done

echo ""

if [[ "$SKIP_DB_CREATE" != true ]]; then
# Create user and database
    sudo -u postgres psql << EOF
CREATE USER synapse WITH PASSWORD '$DB_PASSWORD';
CREATE DATABASE synapse
  ENCODING 'UTF8'
  LC_COLLATE 'C'
  LC_CTYPE 'C'
  TEMPLATE template0
  OWNER synapse;
\l
EOF
    print_success "Database and user created"
fi

cd ..

STAGE="matrix_deps"
# Install required packages for Matrix Synapse installation
print_header "Installing Matrix Synapse dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y lsb-release wget apt-transport-https > /dev/null 2>&1
print_success "Dependencies installed"

STAGE="download_matrix_key"
# Download and install the official Matrix.org package signing key
print_header "Downloading Matrix.org GPG key..."
wget -q -O /usr/share/keyrings/matrix-org-archive-keyring.gpg https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg
print_success "GPG key downloaded"

STAGE="add_matrix_repo"
# Add the Matrix.org APT repository for Synapse packages
print_header "Adding Matrix.org repository..."
echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] https://packages.matrix.org/debian/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/matrix-org.list > /dev/null
print_success "Repository added"

STAGE="apt_update_with_matrix"
# Refresh APT package list to include Matrix.org repository
print_header "Updating package list with Matrix repository..."
apt-get update -qq > /dev/null 2>&1
print_success "Package list updated"

STAGE="prompt_server_name"
# Prompt for and validate the Matrix server name (domain)
echo ""
print_header "Matrix Server Name Configuration"
echo "================================="
echo "Enter your server name in the format: subdomain.domain.com"
echo "This should match the domain you will use with your reverse proxy."
echo "Example: matrix.example.com"
echo ""
while true; do
  read -p "Enter your Matrix server name: " SERVER_NAME
  if [[ -z "$SERVER_NAME" ]]; then
    print_warning "Server name cannot be empty"
    continue
  fi
  if ! [[ "$SERVER_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    print_warning "Invalid server name format. Use subdomain.domain.com format"
    continue
  fi
  break
done
print_success "Server name set to: $SERVER_NAME"

STAGE="prompt_matrix_config"
# Confirm server name and prompt user before proceeding
print_header "Please complete the Matrix Synapse installation configuration."
echo -e "Set server name to: ${GREEN}$SERVER_NAME${NC}"
print_info "Press Enter when ready to proceed..."
read -p ""

STAGE="install_matrix"
# Install the Matrix Synapse server and password generator
print_header "Installing Matrix Synapse..."
apt-get install -qq -y matrix-synapse-py3 pwgen
print_success "Matrix Synapse installed"

STAGE="ufw_allow_8008"
# Open port 8008 for Matrix Synapse client/federation traffic
print_header "Opening port 8008 in firewall..."
ufw allow 8008 > /dev/null 2>&1
print_success "Port 8008 opened"

STAGE="get_lan_ip"
# Detect the server's LAN IP address for configuration and summary
LAN_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
if [[ -z "$LAN_IP" ]]; then
    LAN_IP="127.0.0.1"  
fi

# Generate random secrets for Synapse configuration
STAGE="generate_randoms"
print_header "Generating random secrets..."
RANDOM_STRING1=$(pwgen -s 32 1)
RANDOM_STRING2=$(pwgen -s 32 1)
RANDOM_STRING3=$(pwgen -s 32 1)
print_success "Secrets generated"

STAGE="configure_homeserver"
# Backup and write the main Synapse configuration file
print_header "Configuring homeserver.yaml..."
if [[ -f /etc/matrix-synapse/homeserver.yaml ]]; then
    cp /etc/matrix-synapse/homeserver.yaml /etc/matrix-synapse/homeserver.yaml.backup.$(date +%Y%m%d_%H%M%S)
    print_info "Existing config backed up"
fi

cat > /etc/matrix-synapse/homeserver.yaml << EOF
#
# [1] https://docs.ansible.com/ansible/latest/reference_appendices/YAMLSyntax.html
#
# For more information on how to configure Synapse, including a complete accounting of
# each option, go to docs/usage/configuration/config_documentation.md or
# https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html
#
server_name: "$SERVER_NAME"
pid_file: "/var/run/matrix-synapse.pid"
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['127.0.0.1', '$LAN_IP']
    resources:
      - names: [client, federation]
        compress: false
database:
  name: psycopg2
  args:
    user: synapse
    password: $DB_PASSWORD
    dbname: synapse
    host: localhost
    port: 5432
    cp_min: 5
    cp_max: 10
log_config: "/etc/matrix-synapse/log.yaml"
media_store_path: /var/lib/matrix-synapse/media
signing_key_path: "/etc/matrix-synapse/homeserver.signing.key"
trusted_key_servers:
  - server_name: "matrix.org"

macaroon_secret_key: $RANDOM_STRING1
form_secret: $RANDOM_STRING2

enable_registration: false
enable_registration_without_verification: false
registration_shared_secret: $RANDOM_STRING3
EOF
print_success "Homeserver configured"

STAGE="restart_matrix"
# Restart the Synapse service and verify it is running
print_header "Restarting Matrix Synapse service..."
systemctl restart matrix-synapse
sleep 3

# Verify service is running
if systemctl is-active --quiet matrix-synapse; then
    print_success "Matrix Synapse is running"
else
    print_error "Matrix Synapse failed to start"
    systemctl status matrix-synapse --no-pager
    exit 1
fi

STAGE="install_python_tools"
# Install Python dependencies and download user registration script
print_header "Installing Python dependencies and user registration script..."
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y python3 python3-requests python3-yaml python3-pip curl > /dev/null 2>&1
pip install --quiet typing_extensions 2>/dev/null
curl -sS -o register_new_matrix_user.py "https://raw.githubusercontent.com/element-hq/synapse/refs/heads/develop/synapse/_scripts/register_new_matrix_user.py"
chmod +x register_new_matrix_user.py
print_success "Python tools and registration script installed"

STAGE="summary"
print_header "Installation Summary"
echo -e "==============================================================="
echo ""
echo -e "${BLUE}1. System Configuration:${NC}"
echo -e "   - Created new sudo user: ${GREEN}$USERNAME${NC}"
echo -e "   - Updated system packages"
echo -e "   - Configured UFW firewall (SSH and 8008 ports open)"
echo ""
echo -e "${BLUE}2. PostgreSQL Setup:${NC}"
echo -e "   - Installed PostgreSQL"
echo -e "   - Created database"
echo -e "   - Username: ${GREEN}synapse${NC} (password set during setup)"
echo ""
echo -e "${BLUE}3. Matrix Synapse:${NC}"
echo -e "   - Installed Matrix Synapse"
echo -e "   - Configured homeserver.yaml"
echo -e "   - Server name: ${CYAN}$SERVER_NAME${NC}"
echo -e "   - LAN IP: ${CYAN}$LAN_IP${NC}"
echo -e "   - Service started and running"
echo ""
echo -e "${BLUE}4. Additional Tools:${NC}"
echo -e "   - Installed Python dependencies"
echo -e "   - Downloaded user registration script: ${GREEN}register_new_matrix_user.py${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. To create new users, use:"
echo -e "     - ${CYAN}sudo python3 register_new_matrix_user.py -c "/etc/matrix-synapse/homeserver.yaml"${NC}"
echo -e "  2. Access your server using Matrix client via: ${CYAN}http://$LAN_IP:8008${NC}"
echo -e "  3. Configure reverse proxy:"
echo -e "     - Proxy ${CYAN}$SERVER_NAME${NC} to ${CYAN}http://$LAN_IP:8008${NC} and secure with SSL/TLS"
echo ""
echo -e "${YELLOW}PostpreSQL administration:${NC}"
echo -e "   - Access PostgreSQL shell: ${CYAN}sudo -u postgres psql${NC}"
echo -e "   - Alternatively, connect using a PostgreSQL client"
echo ""
print_success "Installation process completed!"
