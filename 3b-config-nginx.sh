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

# Adds site configuration files to /etc/nginx/conf.d
#######################################################################################################################

if ! [[ $(id -u) = 0 ]]; then
    echo "Please run this script as sudo or root${NC}" 1>&2
    exit 1
fi

# Below variables are automatically updated by the 1-setup.sh script with the respective values given at install (manually update if blank)
PROXY_SITE=

if [[ -z "${PROXY_SITE}" ]]; then
    echo "PROXY_SITE variable is required, setup will abort" &>>${INSTALL_LOG}
    exit 1
fi

# TODO: Change to /etc/nginx/conf.d/
# TODO: Set server_name to $PROXY_SITE
# Configure /etc/nginx/sites-available/(local dns site name)
echo "Adding site configuration to Nginx for '${PROXY_SITE}'" &>>${INSTALL_LOG}
cat <<EOF | tee /etc/nginx/conf.d/${PROXY_SITE}.conf
server {
    listen 80 default_server;
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
EOF
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Symlink new reverse proxy site config from sites-available to sites-enabled
# ln -s /etc/nginx/sites-available/${PROXY_SITE} /etc/nginx/sites-enabled/

# Done
