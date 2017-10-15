#!/bin/bash

# Example usage:
# curl -s https://<gistURL> | sudo bash /dev/stdin <zabbix.server.com> <agentname.client.com>

if [ "$EUID" -ne 0 ]
  then echo "Scipt must be run as root!"
  exit
fi

if [ -z "$1" ] || [ -z "$2" ]; then
    echo 'Zabbix server ($1) and agent name ($2) required'
    exit
else
    zabbix_server=$1
    zabbix_agent=$2
fi

# Check that Xcode CLTs installed
if ! xcode-select -p >/dev/null; then 
    echo "Xcode Command Line Tools required for Homebrew"
    echo "Run: sudo xcode-select --install"
    exit
fi

# Accept Xcode license (just in case)
xcodebuild -license accept

# Current user. Used for installing Homebrew and Zabbix
current_user=$(printf '%s' "${SUDO_USER:-$USER}")

# Install Homebrew if not already installed
if ! which brew 2> /dev/null; then
    echo "Installing Homebrew"
    sudo -u $current_user ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

# Install Zabbix agent
echo "Installing Zabbix-Agent"
sudo -u $current_user brew install zabbix --without-server-proxy

# Create Zabbix user group
echo "Creating Zabbix group"
dscl /Local/Default -create /Groups/zabbix
dscl /Local/Default -create /Groups/zabbix PrimaryGroupID 113
dscl /Local/Default -create /Groups/zabbix Password \*

# Create Zabbix user
echo "Creating Zabbix user"
dscl /Local/Default -create /Users/zabbix
dscl /Local/Default -create /Users/zabbix UniqueID 113
dscl /Local/Default -create /Users/zabbix UserShell /usr/bin/false
dscl /Local/Default -create /Users/zabbix RealName 'Zabbix user'
dscl /Local/Default -create /Users/zabbix NFSHomeDirectory /var/empty 
dscl /Local/Default -create /Users/zabbix PrimaryGroupID 113
dscl /Local/Default -create /Users/zabbix Password \*

# Make directories if needed and set permissions
echo "Creating directories and setting permissions"
mkdir -p /var/log/zabbix /usr/local/var/run/zabbix
chown -Rf zabbix:zabbix /var/log/zabbix
chown -Rf zabbix:zabbix /usr/local/var/run/zabbix

# Write Zabbix config
echo "Writing Zabbix config file"
echo "PidFile=/usr/local/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
Server=$zabbix_server
ServerActive=$zabbix_agent
Hostname=$zabbix_server
Include=/usr/local/etc/zabbix/zabbix_agentd.conf.d/
" > /usr/local/etc/zabbix/zabbix_agentd.conf

# Create LaunchDaemon
echo "Creating LaunchDaemon"
> /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist
tee -a /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.zabbix.zabbix_agentd</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>zabbix</string>
    <key>GroupName</key>
    <string>zabbix</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/sbin/zabbix_agentd</string>
        <string>-c</string>
        <string>/usr/local/etc/zabbix/zabbix_agentd.conf</string>
    </array>
</dict>
</plist>
EOF

# Set permissions for LaunchDaemon
echo "Setting LaunchDaemon permissions"
chown root:wheel /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist
chmod 644 /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist

# Load LaunchDaemon, unloading first if already loaded
echo "Loading Zabbix agent daemon"
if launchctl list | grep com.zabbix.zabbix_agentd.plist; then
    launchctl unload /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist
fi
launchctl load /Library/LaunchDaemons/com.zabbix.zabbix_agentd.plist