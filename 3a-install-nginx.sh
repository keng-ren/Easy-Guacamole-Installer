#!/bin/bash
#######################################################################################################################
# Add Nginx reverse proxy front end to default Guacamole install
# For Ubuntu / Debian / Raspbian
# 3 of 4
# David Harrop
# August 2023
#######################################################################################################################
# Unattended version
# It is not intended to run standalone, but as part of a single deployment

# Installs Nginx and sets some global configuration options
#######################################################################################################################

if ! [[ $(id -u) = 0 ]]; then
    echo "Please run this script as sudo or root${NC}" 1>&2
    exit 1
fi

echo "Installing Nginx..." &>>${INSTALL_LOG}

# Install Nginx
apt-get update -qq &> /dev/null && apt-get install nginx -qq -y &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Force nginx to require tls1.2 and above
sed -i -e '/ssl_protocols/s/^/#/' /etc/nginx/nginx.conf
sed -i "/SSL Settings/a \        ssl_protocols TLSv1.2 TLSv1.3;" /etc/nginx/nginx.conf

# Make sure the default Nginx site is unlinked
# TODO: Is there a default site in /etc/nginx/conf.d?
unlink /etc/nginx/sites-enabled/default

# Do mandatory Nginx tweaks for logging actual client IPs through a proxy IP of 127.0.0.1 - DO NOT CHANGE COMMAND FORMATTING!
echo "Configuring Apache Tomcat valve for pass through of client IPs to Guacamole logs..." &>>${INSTALL_LOG}
sed -i '/pattern="%h %l %u %t &quot;%r&quot; %s %b"/a        \        <!-- Allow host IP to pass through to guacamole.-->\n        <Valve className="org.apache.catalina.valves.RemoteIpValve"\n               internalProxies="127\.0\.0\.1|0:0:0:0:0:0:0:1"\n               remoteIpHeader="x-forwarded-for"\n               remoteIpProxiesHeader="x-forwarded-by"\n               protocolHeader="x-forwarded-proto" />' /etc/$TOMCAT_VERSION/server.xml
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Allow large file transfers through Nginx
sed -i '/client_max_body_size/d' /etc/nginx/nginx.conf  # remove this line if it already exists to prevent duplicates
sed -i "/Basic Settings/a \        client_max_body_size 1000000000M;" /etc/nginx/nginx.conf # Add larger file transfer size, should be enough!
echo "Boosting Nginx's 'maximum body size' parameter to allow large file transfers..." &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Update general ufw rules so force traffic via reverse proxy. Only Nginx and SSH will be available over the network.
echo "Updating firewall rules to allow only SSH and tcp 80/443..." &>>${INSTALL_LOG}
ufw default allow outgoing >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw delete allow 8080/tcp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Installation Done
