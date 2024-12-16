#!/bin/bash
#######################################################################################################################
# Add Nginx reverse proxy front end to default Guacamole install
# For Ubuntu / Debian / Raspbian
# 3 of 4
# David Harrop
# August 2023
#######################################################################################################################

# If run as standalone and not from the main installer script, check the below variables are correct.
# To run standalone: sudo -E ./3-install-nginx.sh

if ! [[ $(id -u) = 0 ]]; then
    echo "Please run this script as sudo or root${NC}" 1>&2
    exit 1
fi

echo "Installing Nginx..." &>>${INSTALL_LOG}
TOMCAT_VERSION=$(ls /etc/ | grep tomcat)
# Below variables are automatically updated by the 1-setup.sh script with the respective values given at install (manually update if blank)
PROXY_SITE=
INSTALL_LOG=
GUAC_URL=

# Install Nginx
apt-get update -qq &> /dev/null && apt-get install nginx -qq -y &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

echo "Configuring Nginx as a reverse proxy for Guacamole's Apache Tomcat front end..." &>>${INSTALL_LOG}
# TODO: Change to /etc/nginx/conf.d/
# TODO: Set server_name to $PROXY_SITE
# Configure /etc/nginx/sites-available/(local dns site name)
cat <<EOF | tee /etc/nginx/sites-available/$PROXY_SITE
server {
    listen 80 default_server;
    server_name $GUAC_URL;
    location / {
        proxy_pass $GUAC_URL;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        access_log off;
    }
}
EOF
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Force nginx to require tls1.2 and above
sed -i -e '/ssl_protocols/s/^/#/' /etc/nginx/nginx.conf
sed -i "/SSL Settings/a \        ssl_protocols TLSv1.2 TLSv1.3;" /etc/nginx/nginx.conf

# Symlink new reverse proxy site config from sites-available to sites-enabled
ln -s /etc/nginx/sites-available/$PROXY_SITE /etc/nginx/sites-enabled/

# Make sure the default Nginx site is unlinked
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

# Reload everything
echo "Restaring Guacamole & Ngnix..." &>>${INSTALL_LOG}
systemctl restart $TOMCAT_VERSION
systemctl restart guacd
systemctl restart nginx
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Done
