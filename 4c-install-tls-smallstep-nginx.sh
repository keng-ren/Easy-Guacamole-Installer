#!/bin/bash
#######################################################################################################################
# Add Smallstep TLS Certificates to Guacamole with Nginx reverse proxy
# For Ubuntu / Debian / Raspbian
# 4c of 4
# Kenneth Glassey
# December 2024
#######################################################################################################################
# Unattended version
# It is not intended to run standalone, but as part of a single deployment
#######################################################################################################################

TOMCAT_VERSION=$(ls /etc/ | grep tomcat)
# Below variables are automatically updated by the 1-setup.sh script with the respective values given at install (manually update if blank)
PROXY_SITE=

if [[ -z "${PROXY_SITE}" ]]; then
    echo "PROXY_SITE variable is required, setup will abort" &>>${INSTALL_LOG}
    exit 1
fi

apt-get update -qq &> /dev/null && apt-get install nginx certbot python3-certbot-nginx -qq -y &>>${INSTALL_LOG} &
command_pid=$!
# spinner $command_pid
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Backup the current Nginx config
echo "Backing up previous Nginx proxy to $DO{WNLOAD_DIR/${PROXY_SITE}-nginx.bak" &>>${INSTALL_LOG}
cp /etc/nginx/sites-enabled/${PROXY_SITE} ${DOWNLOAD_DIR}/${PROXY_SITE}-nginx.bak
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Configure Nginx to accept the new certificates
echo "Configuring Nginx proxy for Smallstep TLS and setting up automatic HTTP redirect..." &>>${INSTALL_LOG}
cat >/etc/nginx/sites-available/${PROXY_SITE} <<EOL
server {
    listen 80 default_server;
    #listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    server_name ${PROXY_SITE};
    location / {
        proxy_pass ${GUAC_URL};
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        access_log off;
    }
}
EOL
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Update general ufw rules to force traffic via reverse proxy. Only Nginx and SSH will be available over the network.
echo "Updating firewall rules to allow only SSH and tcp 80/443..." &>>${INSTALL_LOG}
ufw default allow outgoing >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Reload the new Nginx config so as certbot can read the new config and update it
systemctl restart nginx

# Run certbot to create and associate certificates with current public IP (must have tcp 80 and 443 open to work!)
certbot --nginx -n -d ${PROXY_SITE}  --agree-tos --redirect --hsts --server ${STEPCA_SERVER}
echo
echo "Smallstep successfully installed, but check for any errors above (DNS & firewall are the usual culprits)." &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Select a random daily time to schedule a daily check for a Smallstep certificate due to expire in next 30 days.
# If due to expire within a 30 day window, certbot will attempt to renew automatically each day.
echo "Scheduling automatic certificate renewals for certificates with < 30 days till expiry.)" &>>${INSTALL_LOG}
#Dump out the current crontab
crontab -l >cron_1
# Remove any previosly added certbot renewal entries
sed -i '/# certbot renew/d' cron_1
# Randomly choose a daily update schedule and append this to the cron schedule
HOUR=$(shuf -i 0-23 -n 1)
MINUTE=$(shuf -i 0-59 -n 1)
echo "${MINUTE} ${HOUR} * * * /usr/bin/certbot renew --server ${STEPCA_SERVER} --quiet --pre-hook 'systemctl stop nginx' --post-hook 'systemctl start nginx'" >>cron_1
# Overwrite old cron settings and cleanup
crontab cron_1
rm cron_1
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Reload everything once again
echo "Restarting Guacamole & Nginx..." &>>${INSTALL_LOG}
systemctl restart ${TOMCAT_VERSION}
systemctl restart guacd
systemctl restart nginx
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Done
