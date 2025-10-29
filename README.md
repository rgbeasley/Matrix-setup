# Matrix Synapse Server Installation Scripts
A set of scripts to automate the installation and configuration of a Matrix Synapse server with an optional admin panel interface.

## Overview

This repository contains two installation scripts:
1. `matrix-install.sh`: Main script to install and configure Matrix Synapse server
2. `admin-panel-install.sh`: Optional script to install Docker and the Synapse Admin web interface

## Prerequisites
- A Debian-based Linux distribution (Ubuntu recommended)
- Root/sudo access
- Active internet connection
- Domain or subdomain for your Matrix server
- Open ports 8008 (Matrix) and 8080 (Admin Panel)

## Installation Steps

### 1. Matrix Synapse Server Installation
```bash
# Make the script executable
chmod +x matrix-install.sh

# Run the installation script
sudo ./matrix-install.sh
```

The script will:
- Create a new sudo user
- Install and configure PostgreSQL
- Set up Matrix Synapse with PostgreSQL backend
- Configure UFW firewall
- Generate required security keys and secrets
- Install Python tools for user management

During installation, you'll be prompted for:
1. New system username
2. PostgreSQL database password
3. Matrix server name (e.g., matrix.example.com)

### 2. Admin Panel Installation (Optional)
```bash
# Make the script executable
chmod +x admin-panel-install.sh

# Run the installation script
sudo ./admin-panel-install.sh
```

This script will:
- Install Docker and Docker Compose
- Deploy the Synapse Admin web interface
- Configure the container to run on port 8080

## Accessing Your Services

### Matrix Synapse Server
- Local access: `http://<server-ip>:8008`
- Federation: Configure reverse proxy for `https://matrix.example.com`

### Synapse Admin Panel (if installed)
- Access the admin interface at: `http://<server-ip>:8080`
- Use your admin credentials to log in

## User Management

### Creating New Users
You can create new users in two ways:
1. Using the command-line tool:
```bash
sudo python3 register_new_matrix_user.py -c "/etc/matrix-synapse/homeserver.yaml"
```

2. Using the Synapse Admin panel (if installed):
- Navigate to `http://<server-ip>:8080`
- Log in with admin credentials
- Use the web interface to manage users

## Configuration Files
Important configuration files and their locations:
- Matrix Synapse config: `/etc/matrix-synapse/homeserver.yaml`
- PostgreSQL database: Default PostgreSQL location
- Synapse Admin: Docker container (if installed)

## Port Usage
- 8008: Matrix Synapse client/server API
- 8080: Synapse Admin web interface
- 22: SSH (required for remote access)

## Security Notes
1. The installation configures UFW firewall with:
   - SSH access (port 22)
   - Matrix Synapse (port 8008)
   - Admin Panel (port 8080, if installed)

2. Important security features:
   - User registration is disabled by default
   - Random secrets generated for security
   - PostgreSQL password protection
   - UFW firewall enabled

## Maintenance

### PostgreSQL Administration
- Access PostgreSQL shell: `sudo -u postgres psql`
- Database name: `synapse`
- Database user: `synapse`

## Troubleshooting
1. Check Matrix Synapse status:
```bash
systemctl status matrix-synapse
```

2. View Matrix Synapse logs:
```bash
journalctl -u matrix-synapse
sudo cat /etc/matrix-synapse/log.yaml
```

3. Check PostgreSQL status:
```bash
systemctl status postgresql
```

4. Docker issues (if admin panel installed):
```bash
docker ps
docker logs <container_id>
```

## Additional Resources
- [Matrix Synapse Documentation](https://element-hq.github.io/synapse/latest/)
- [Synapse Admin Documentation](https://github.com/Awesome-Technologies/synapse-admin)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
