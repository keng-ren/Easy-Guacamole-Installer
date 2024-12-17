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

# Below variables are automatically updated by the 1-setup.sh script with the respective values given at install (manually update if blank)
PROXY_SITE=
PROXY_IP=

if [[ -z "${PROXY_SITE}" ]]; then
    echo "PROXY_SITE variable is required, setup will abort" &>>${INSTALL_LOG}
    exit 1
fi

if [[ -z "${PROXY_IP}" ]]; then
    # Valid for singlehomed systems
    echo "Installing Certbot for ${PROXY_SITE}..." &>>${INSTALL_LOG}
else
    # Required if system is multihomed
    echo "Installing Certbot for ${PROXY_SITE} on ${PROXY_IP}..." &>>${INSTALL_LOG}
    PROXY_IP="${PROXY_IP}:"
fi

apt-get update -qq &> /dev/null && apt-get install certbot python3-certbot-nginx -qq -y &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "apt-get Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "apt-get OK" &>>${INSTALL_LOG}
fi

# Backup the current Nginx config
msg="Back up previous Nginx proxy to /etc/nginx/conf.d/${PROXY_SITE}.conf.bak"
mv /etc/nginx/conf.d/${PROXY_SITE}.conf /etc/nginx/conf.d/${PROXY_SITE}-ssl.conf.bak
if [[ $? -ne 0 ]]; then
    echo "${msg}Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "${msg}OK" &>>${INSTALL_LOG}
fi

# Configure Nginx to accept the new certificates
msg="Configure Nginx proxy for Smallstep TLS and setting up automatic HTTP redirect..."
cat >/etc/nginx/conf.d/${PROXY_SITE}-ssl.conf <<EOL
server {
    listen ${PROXY_IP}443 ssl;
    ssl_certificate     ${PROXY_SITE}.crt;
    ssl_certificate_key ${PROXY_SITE}.key;
    #root /var/www/html;
    #index index.html index.htm index.nginx-debian.html;
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
    echo "${msg}Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "${msg}OK" &>>${INSTALL_LOG}
fi

# Update general ufw rules to force traffic via reverse proxy. Only Nginx and SSH will be available over the network.
msg= "Update firewall rules to allow only SSH and tcp 80/443..."
ufw default allow outgoing >/dev/null &>>${INSTALL_LOG}
ufw default deny incoming >/dev/null &>>${INSTALL_LOG}
ufw allow OpenSSH >/dev/null &>>${INSTALL_LOG}
ufw allow 80/tcp >/dev/null &>>${INSTALL_LOG}
ufw allow 443/tcp >/dev/null &>>${INSTALL_LOG}
echo "y" | ufw enable >/dev/null &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "${msg}Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "${msg}OK" &>>${INSTALL_LOG}
fi

# Reload the new Nginx config so as certbot can read the new config and update it
systemctl restart nginx

# Run certbot to create and associate certificates with current public IP (must have tcp 80 and 443 open to work!)
certbot --nginx -n -d ${PROXY_SITE}  --agree-tos --redirect --hsts --server ${STEPCA_SERVER}
echo "Smallstep successfully installed, but check for any errors above (DNS & firewall are the usual culprits)." &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Smallstep Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "Smallstep OK" &>>${INSTALL_LOG}
fi

# Select a random daily time to schedule a daily check for a Smallstep certificate due to expire in next 30 days.
# If due to expire within a 30 day window, certbot will attempt to renew automatically each day.
echo "Scheduling automatic certificate renewals for certificates with < 30 days till expiry.)" &>>${INSTALL_LOG}
#Dump out the current crontab
crontab -l > cron_1
# Remove any previosly added certbot renewal entries
sed -i '/# certbot renew/d' cron_1
# Randomly choose a daily update schedule and append this to the cron schedule
HOUR=$(shuf -i 0-23 -n 1)
MINUTE=$(shuf -i 0-59 -n 1)
echo "${MINUTE} ${HOUR} * * * /usr/bin/certbot renew --server ${STEPCA_SERVER} --quiet --pre-hook 'systemctl stop nginx' --post-hook 'systemctl start nginx'" >> cron_1
# Overwrite old cron settings and cleanup
crontab cron_1
rm cron_1
if [[ $? -ne 0 ]]; then
    echo "crontab Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "crontab OK" &>>${INSTALL_LOG}
fi

# Reload everything once again
msg="Restarting Guacamole & Nginx..."
systemctl restart ${TOMCAT_VERSION}
systemctl restart guacd
systemctl restart nginx
if [[ $? -ne 0 ]]; then
    echo "${msg}Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "${msg}OK" &>>${INSTALL_LOG}
fi

# Done
