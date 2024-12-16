#!/bin/bash
#######################################################################################################################
# Guacamole main build script
# For Ubuntu / Debian / Raspbian
# David Harrop
# April 2023
#######################################################################################################################

# Update everything but don't do the annoying prompts during apt installs
echo "}Updating base Linux OS..." &>>${INSTALL_LOG}
export DEBIAN_FRONTEND=noninteractive
# We already ran apt-get update from the 1st setup script, now we begin to upgrade packages
apt-get upgrade -qq -y &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Pre-seed MySQL root password values for Linux Distro default packages only
if [[ "${INSTALL_MYSQL}" = true ]] && [[ -z "${MYSQL_VERSION}" ]]; then
    debconf-set-selections <<<"mysql-server mysql-server/root_password password ${MYSQL_ROOT_PWD}"
    debconf-set-selections <<<"mysql-server mysql-server/root_password_again password ${MYSQL_ROOT_PWD}"
fi

# Install official MariaDB repo and MariaDB version if a specific version number was provided.
if [[ -n "${MYSQL_VERSION}" ]]; then
    echo "Adding the official MariaDB repository and installing version ${MYSQL_VERSION}..." &>>${INSTALL_LOG}
    # Add the Official MariaDB repo.
    apt-get -qq -y install curl gnupg2 &>>${INSTALL_LOG}
    curl -LsS -O ${MARIADB_SOURCE_LINK} &>>${INSTALL_LOG}
    bash mariadb_repo_setup --mariadb-server-version=$MYSQL_VERSION &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Select the appropriate MySQL client or server packages, and don't clobber any pre-existing database installation accidentally
if [[ "${INSTALL_MYSQL}" = true ]]; then
    MYSQLPKG="${MYSQLSRV}"
elif [ -x "$(command -v ${DB_CMD})" ]; then
     MYSQLPKG=""
else
    MYSQLPKG="${MYSQLCLIENT}"
fi

# Install Guacamole build dependencies (pwgen needed for duo config only, expect is auto removed after install)
echo "Installing dependencies required for building Guacamole, this might take a few minutes..."
apt-get -qq -y install ${MYSQLPKG} ${TOMCAT_VERSION} ${JPEGTURBO} ${LIBPNG} ufw pwgen expect \
    build-essential libcairo2-dev libtool-bin uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libwebsockets-dev \
    libpulse-dev libssl-dev libvorbis-dev libwebp-dev ghostscript &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

if [[ ${SETUP_EMAIL} = "true" ]]; then
    # Install Postfix with default settings for smtp email relay
    echo "Installing Postfix MTA for backup email notifications and alerts, see separate SMTP relay configuration script..." &>>${INSTALL_LOG}
    DEBIAN_FRONTEND="noninteractive" apt-get install postfix mailutils -qq -y &>>${INSTALL_LOG} &
    command_pid=$!
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        systemctl restart postfix
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Download Guacamole Server
echo "Downloading Guacamole source files..."
wget -q -O guacamole-server-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/source/guacamole-server-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed to download guacamole-server-${GUAC_VERSION}.tar.gz" 1>&2
    echo "${GUAC_SOURCE_LINK}/source/guacamole-server-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    exit 1
else
    tar -xzf guacamole-server-${GUAC_VERSION}.tar.gz
    echo "Downloaded guacamole-server-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
fi

# Download Guacamole Client
wget -q -O guacamole-${GUAC_VERSION}.war ${GUAC_SOURCE_LINK}/binary/guacamole-${GUAC_VERSION}.war &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed to download guacamole-${GUAC_VERSION}.war" 1>&2
    echo "${GUAC_SOURCE_LINK}/binary/guacamole-${GUAC_VERSION}.war" &>>${INSTALL_LOG}
    exit 1
else
    echo "Downloaded guacamole-${GUAC_VERSION}.war" &>>${INSTALL_LOG}
fi

# Download MySQL connector/j
wget -q -O mysql-connector-j-${MYSQLJCON}.tar.gz ${MYSQLJCON_SOURCE_LINK} &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed to download mysql-connector-j-${MYSQLJCON}.tar.gz" 1>&2
    echo "${MYSQLJCON_SOURCE_LINK}" &>>${INSTALL_LOG}
    exit 1
else
    tar -xzf mysql-connector-j-${MYSQLJCON}.tar.gz
    echo "Downloaded mysql-connector-j-${MYSQLJCON}.tar.gz" &>>${INSTALL_LOG}
fi

# Download Guacamole database auth extension
wget -q -O guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed to download guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" 1>&2
    echo "${GUAC_SOURCE_LINK}/binary/guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    exit 1
else
    tar -xzf guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz
    echo "Downloaded guacamole-auth-jdbc-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
fi

# Download TOTP auth extension
if [[ "${INSTALL_TOTP}" = true ]]; then
    wget -q -O guacamole-auth-totp-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-auth-totp-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed to download guacamole-auth-totp-${GUAC_VERSION}.tar.gz" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/guacamole-auth-totp-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf guacamole-auth-totp-${GUAC_VERSION}.tar.gz
        echo "Downloaded guacamole-auth-totp-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    fi
fi

# Download DUO auth extension
if [[ "${INSTALL_DUO}" = true ]]; then
    wget -q -O guacamole-auth-duo-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-auth-duo-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed to download guacamole-auth-duo-${GUAC_VERSION}.tar.gz" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/guacamole-auth-duo-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf guacamole-auth-duo-${GUAC_VERSION}.tar.gz
        echo "Downloaded guacamole-auth-duo-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    fi
fi

# Download LDAP auth extension
if [[ "${INSTALL_LDAP}" = true ]]; then
    wget -q -O guacamole-auth-ldap-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-auth-ldap-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed to download guacamole-auth-ldap-${GUAC_VERSION}.tar.gz" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/guacamole-auth-ldap-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf guacamole-auth-ldap-${GUAC_VERSION}.tar.gz
        echo "Downloaded guacamole-auth-ldap-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    fi
fi

# Download OpenID Connect auth extension
if [[ "${INSTALL_OPENID}" = true ]]; then
    SSO_TAR_NAME="guacamole-auth-sso-${GUAC_VERSION}"
    SSO_TAR="${SSO_TAR_NAME}.tar.gz"
    wget -q -O ${SSO_TAR} ${GUAC_SOURCE_LINK}/binary/${SSO_TAR} &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed to download ${SSO_TAR}" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/${SSO_TAR}" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf ${SSO_TAR}
        echo "Downloaded ${SSO_TAR}" &>>${INSTALL_LOG}
    fi
fi

# Download Guacamole quick-connect extension
if [[ "${INSTALL_QCONNECT}" = true ]]; then
    wget -q -O guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed to download guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz
        echo "Downloaded guacamole-auth-quickconnect-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    fi
fi

# Download Guacamole history recording storage extension
if [[ "${INSTALL_HISTREC}" = true ]]; then
    wget -q -O guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz ${GUAC_SOURCE_LINK}/binary/guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz &>>${INSTALL_LOG}

    if [[ $? -ne 0 ]]; then
        echo "Failed to download guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz" 1>&2
        echo "${GUAC_SOURCE_LINK}/binary/guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
        exit 1
    else
        tar -xzf guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz
        echo "Downloaded guacamole-history-recording-storage-${GUAC_VERSION}.tar.gz" &>>${INSTALL_LOG}
    fi
fi
echo "Source download complete."

# Place a pause in script here if you wish to make final tweaks to source code before compiling
#read -p $'Script paused for editing source before building. Enter to begin the build...\n'

# Add customised RDP share names and printer labels, remove Guacamole default labelling
sed -i -e 's/IDX_CLIENT_NAME, "Guacamole RDP"/IDX_CLIENT_NAME, "'"${RDP_SHARE_HOST}"'"/' ${DOWNLOAD_DIR}/guacamole-server-${GUAC_VERSION}/src/protocols/rdp/settings.c
sed -i -e 's/IDX_DRIVE_NAME, "Guacamole Filesystem"/IDX_DRIVE_NAME, "'"${RDP_SHARE_LABEL}"'"/' ${DOWNLOAD_DIR}/guacamole-server-${GUAC_VERSION}/src/protocols/rdp/settings.c
sed -i -e 's/IDX_PRINTER_NAME, "Guacamole Printer"/IDX_PRINTER_NAME, "'"${RDP_PRINTER_LABEL}"'"/' ${DOWNLOAD_DIR}/guacamole-server-${GUAC_VERSION}/src/protocols/rdp/settings.c

# Make Guacamole directories
rm -rf /etc/guacamole/lib/
rm -rf /etc/guacamole/extensions/
mkdir -p /etc/guacamole/lib/
mkdir -p /etc/guacamole/extensions/

# Create a custom guacd service account and heavily lock it down
adduser "${GUACD_ACCOUNT}" --disabled-password --disabled-login --gecos "" > /dev/null 2>&1
gpasswd -d "${GUACD_ACCOUNT}" users > /dev/null 2>&1
echo "\nMatch User ${GUACD_ACCOUNT}\n    X11Forwarding no\n    AllowTcpForwarding no\n    PermitTTY no\n    ForceCommand cvs server" | tee -a /etc/ssh/sshd_config > /dev/null 2>&1
systemctl restart ssh
touch "${CRON_DENY_FILE}"
chmod 644 "${CRON_DENY_FILE}"
chown root:root "${CRON_DENY_FILE}"
if ! grep -q "^${GUACD_ACCOUNT}$" "${CRON_DENY_FILE}"; then
   echo "$GUACD_ACCOUNT" | tee -a "$CRON_DENY_FILE" > /dev/null 2>&1
fi

# Setup freerdp profile permissions for storing certificates
mkdir -p /home/"${GUACD_ACCOUNT}"/.config/freerdp
chown ${GUACD_ACCOUNT}:${GUACD_ACCOUNT} /home/"${GUACD_ACCOUNT}"/.config/freerdp

# Setup guacamole permissions
mkdir -p /var/guacamole
chown "${GUACD_ACCOUNT}":"${GUACD_ACCOUNT}" /var/guacamole

# Make and install guacd (Guacamole-Server)
echo
echo "Compiling Guacamole-Server from source with with GCC $(gcc --version | head -n1 | grep -oP '\)\K.*' | awk '{print $1}'), this might take a few minutes..."

cd guacamole-server-${GUAC_VERSION}/
# Skip any deprecated software warnings various distros may throw during build
export CFLAGS="-Wno-error"

# Configure Guacamole Server source
./configure --with-systemd-dir=/etc/systemd/system &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed to configure guacamole-server" &>>${INSTALL_LOG}
    echo "Trying again with --enable-allow-freerdp-snapshots" &>>${INSTALL_LOG}
    ./configure --with-systemd-dir=/etc/systemd/system --enable-allow-freerdp-snapshots
    if [[ $? -ne 0 ]]; then
        echo "Failed to configure guacamole-server - again" 1>&2
        exit 1
    fi
else
    echo "OK" &>>${INSTALL_LOG}
fi

echo "Running make and building the Guacamole-Server application..."
make &>>${INSTALL_LOG} &
command_pid=$!
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

echo "Installing Guacamole-Server..."
make install &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Update the shared library cache
ldconfig

# Move Guacamole client and authentication extensions to their correct install locations
cd ..
echo "Moving guacamole-${GUAC_VERSION}.war (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
mv -f guacamole-${GUAC_VERSION}.war /etc/guacamole/guacamole.war
chmod 664 /etc/guacamole/guacamole.war
# Create a symbolic link for Tomcat
ln -sf /etc/guacamole/guacamole.war /var/lib/${TOMCAT_VERSION}/webapps/ &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

echo "Moving guacamole-auth-jdbc-mysql-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..."
mv -f guacamole-auth-jdbc-${GUAC_VERSION}/mysql/guacamole-auth-jdbc-mysql-${GUAC_VERSION}.jar /etc/guacamole/extensions/
chmod 664 /etc/guacamole/extensions/guacamole-auth-jdbc-mysql-${GUAC_VERSION}.jar
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Move MySQL connector/j files
echo "Moving mysql-connector-j-${MYSQLJCON}.jar (/etc/guacamole/lib/mysql-connector-java.jar)..." &>>${INSTALL_LOG}
mv -f mysql-connector-j-${MYSQLJCON}/mysql-connector-j-${MYSQLJCON}.jar /etc/guacamole/lib/mysql-connector-java.jar
chmod 664 /etc/guacamole/lib/mysql-connector-java.jar
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Configure guacamole.properties file
rm -f /etc/guacamole/guacamole.properties
touch /etc/guacamole/guacamole.properties
echo "mysql-hostname: ${MYSQL_HOST}" >>/etc/guacamole/guacamole.properties
echo "mysql-port: ${MYSQL_PORT}" >>/etc/guacamole/guacamole.properties
echo "mysql-database: ${GUAC_DB}" >>/etc/guacamole/guacamole.properties
echo "mysql-username: ${GUAC_USER}" >>/etc/guacamole/guacamole.properties
echo "mysql-password: ${GUAC_PWD}" >>/etc/guacamole/guacamole.properties

# Move TOTP files
if [[ "${INSTALL_TOTP}" = true ]]; then
    echo "Moving guacamole-auth-totp-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f guacamole-auth-totp-${GUAC_VERSION}/guacamole-auth-totp-${GUAC_VERSION}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-totp-${GUAC_VERSION}.jar
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Move Duo files
if [[ "${INSTALL_DUO}" = true ]]; then
    echo "Moving guacamole-auth-duo-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f guacamole-auth-duo-${GUAC_VERSION}/guacamole-auth-duo-${GUAC_VERSION}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-duo-${GUAC_VERSION}.jar
    echo "#duo-api-hostname: " >>/etc/guacamole/guacamole.properties
    echo "#duo-integration-key: " >>/etc/guacamole/guacamole.properties
    echo "#duo-secret-key: " >>/etc/guacamole/guacamole.properties
    echo "#duo-application-key: " >>/etc/guacamole/guacamole.properties
    echo "Duo auth is installed, it will need to be configured via guacamole.properties"
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Move LDAP files
if [[ "${INSTALL_LDAP}" = true ]]; then
    echo "Moving guacamole-auth-ldap-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f guacamole-auth-ldap-${GUAC_VERSION}/guacamole-auth-ldap-${GUAC_VERSION}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-ldap-${GUAC_VERSION}.jar
    echo "#If you have issues with LDAP, check the formatting is exactly as below or you will despair!" >>/etc/guacamole/guacamole.properties
    echo "#Be extra careful with spaces at line ends or with windows line feeds." >>/etc/guacamole/guacamole.properties
    echo "#ldap-hostname: dc1.yourdomain.com dc2.yourdomain.com" >>/etc/guacamole/guacamole.properties
    echo "#ldap-port: 389" >>/etc/guacamole/guacamole.properties
    echo "#ldap-username-attribute: sAMAccountName" >>/etc/guacamole/guacamole.properties
    echo "#ldap-encryption-method: none" >>/etc/guacamole/guacamole.properties
    echo "#ldap-search-bind-dn: ad-account@yourdomain.com" >>/etc/guacamole/guacamole.properties
    echo "#ldap-search-bind-password: ad-account-password" >>/etc/guacamole/guacamole.properties
    echo "#ldap-config-base-dn: dc=domain,dc=com" >>/etc/guacamole/guacamole.properties
    echo "#ldap-user-base-dn: OU=SomeOU,DC=domain,DC=com" >>/etc/guacamole/guacamole.properties
    echo "#ldap-user-search-filter:(objectClass=user)(!(objectCategory=computer))" >>/etc/guacamole/guacamole.properties
    echo "#ldap-max-search-results:200" >>/etc/guacamole/guacamole.properties
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Move OpenID Connect files
if [[ "${INSTALL_OPENID}" = true ]]; then
    OPENID_JAR="openid/guacamole-auth-sso-openid-${GUAC_VERSION}"
    echo "Moving ${OPENID_JAR}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f ${OPENID_JAR}/${OPENID_JAR}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/${OPENID_JAR}.jar
    echo "#If you have issues with OpenID Connect, check the formatting is exactly as below or you will despair!" >>/etc/guacamole/guacamole.properties
    echo "#Be extra careful with spaces at line ends or with windows line feeds." >>/etc/guacamole/guacamole.properties
    echo "#openid-authorization-endpoint: ${OPENID_AUTHORIZATION_ENDPOINT}" >>/etc/guacamole/guacamole.properties
    echo "#openid-jwks-endpoint: ${OPENID_JWKS_ENDPOINT}" >>/etc/guacamole/guacamole.properties
    echo "#openid-issuer: ${OPENID_ISSUER}" >>/etc/guacamole/guacamole.properties
    echo "#openid-client-id: ${OPENID_CLIENT_ID}" >>/etc/guacamole/guacamole.properties
    echo "#openid-redirect-uri: ${OPENID_REDIRECT_URI}" >>/etc/guacamole/guacamole.properties
    if [[ -n ${OPENID_USERNAME_CLAIM_TYPE} ]]
        echo "#openid-username-claim-type: ${OPENID_USERNAME_CLAIM_TYPE}" >>/etc/guacamole/guacamole.properties
    fi
    if [[ -n ${OPENID_GROUPS_CLAIM_TYPE} ]]
        echo "#openid-groups-claim-type: groups" >>/etc/guacamole/guacamole.properties
    fi
    if [[ -n ${OPENID_SCOPE} ]]
        echo "#openid-scope: ${OPENID_SCOPE}”" >>/etc/guacamole/guacamole.properties
     fi
    if [[ -n ${OPENID_ALLOWED_CLOCK_SKEW} ]]
        echo "#openid-allowed-clock-skew: ${OPENID_ALLOWED_CLOCK_SKEW}" >>/etc/guacamole/guacamole.properties
    fi
    if [[ -n ${OPENID_MAX_TOKEN_VALIDITY} ]]
        echo "#openid-max-token-validity: ${OPENID_MAX_TOKEN_VALIDITY}" >>/etc/guacamole/guacamole.properties
    fi
    if [[ -n ${OPENID_MAX_NONCE_VALIDITY} ]]
        echo "#openid-max-nonce-validity: ${OPENID_MAX_NONCE_VALIDITY}" >>/etc/guacamole/guacamole.properties
    fi
    echo "extension-priority: *, openid" >>/etc/guacamole/guacamole.properties
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
        echo
    fi
fi

# Move quick-connect extension files
if [[ "${INSTALL_QCONNECT}" = true ]]; then
    echo "Moving guacamole-auth-quickconnect-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f guacamole-auth-quickconnect-${GUAC_VERSION}/guacamole-auth-quickconnect-${GUAC_VERSION}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-auth-quickconnect-${GUAC_VERSION}.jar
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Move history recording storage extension files
if [[ "${INSTALL_HISTREC}" = true ]]; then
    echo "Moving guacamole-history-recording-storage-${GUAC_VERSION}.jar (/etc/guacamole/extensions/)..." &>>${INSTALL_LOG}
    mv -f guacamole-history-recording-storage-${GUAC_VERSION}/guacamole-history-recording-storage-${GUAC_VERSION}.jar /etc/guacamole/extensions/
    chmod 664 /etc/guacamole/extensions/guacamole-history-recording-storage-${GUAC_VERSION}.jar
    #Setup the default recording path
    mkdir -p ${HISTREC_PATH}
    chown ${GUACD_ACCOUNT}:tomcat ${HISTREC_PATH}
    chmod 2750 ${HISTREC_PATH}
    echo "recording-search-path: ${HISTREC_PATH}" >>/etc/guacamole/guacamole.properties
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Apply a branded interface and dark theme. You may delete this file and restart guacd & tomcat for the default console
echo "Setting the Guacamole console to a (customisable) dark mode themed template..." &>>${INSTALL_LOG}
mv branding.jar /etc/guacamole/extensions
chmod 664 /etc/guacamole/extensions/branding.jar
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Restart Tomcat
echo "Restarting Tomcat service & enable at boot..." &>>${INSTALL_LOG}
systemctl restart ${TOMCAT_VERSION}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Set Tomcat to start at boot
systemctl enable ${TOMCAT_VERSION}

# Begin the MySQL database config only if this is a local MYSQL install.
if [[ "${INSTALL_MYSQL}" = true ]]; then
    # Set MySQL password
    export MYSQL_PWD=${MYSQL_ROOT_PWD}

    # Set the root password without a reliance on debconf.
    echo "Setting MySQL root password..." &>>${INSTALL_LOG}
    SQLCODE="
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PWD';"
    echo ${SQLCODE} | $DB_CMD -u root
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi

   # A simple method to find the correct file containing the default MySQL timezone setting from a potential list of candidates.
   # Add to this array if your distro uses a different path to the .cnf containing the default_time_zone value.
    for x in /etc/mysql/mariadb.conf.d/50-server.cnf \
        /etc/mysql/mysql.conf.d/mysqld.cnf \
        /etc/mysql/my.cnf; do
        # Check inside each candidate to see if a [mysqld] or [mariadbd] section exists, assign $x the correct filename.
        if [[ -e "${x}" ]]; then
            if grep -qE '^\[(mysqld|mariadbd)\]$' "${x}"; then
                mysqlconfig="${x}"
                # Reduce any duplicated section names, then sanitise the [ ] special characters for sed below)
                config_section=$(grep -m 1 -E '^\[(mysqld|mariadbd)\]$' "${x}" | sed 's/\[\(.*\)\]/\1/')
                break
            fi
        fi
    done

    # Set the MySQL Timezone
    if [[ -z "${mysqlconfig}" ]]; then
        echo "Couldn't detect MySQL config file - you will need to manually configure database timezone settings" &>>${INSTALL_LOG}
    else
        # Is there already a timzeone value configured?
        if grep -q "^default_time_zone[[:space:]]=" "${mysqlconfig}"; then
            echo "MySQL database timezone defined in ${mysqlconfig}" &>>${INSTALL_LOG}
        else
            timezone=${DB_TZ}
            if [[ -z "${DB_TZ}" ]]; then
                echo "No timezone specified, using UTC" &>>${INSTALL_LOG}
                timezone="UTC"
            fi
            echo "Setting MySQL database timezone as ${timezone}" &>>${INSTALL_LOG}
            mysql_tzinfo_to_sql /usr/share/zoneinfo 2>/dev/null | ${DB_CMD} -u root -D mysql -p${MYSQL_ROOT_PWD}
            # Add the timzone value to the sanitsed server file section name.
            sed -i -e "/^\[${config_section}\]/a default_time_zone = ${timezone}" "${mysqlconfig}"
        fi
    fi
    if [[ $? -ne 0 ]]; then
        echo "Failed" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi

    # This below block should stay as "localhost" for all local MySQL install situations and it is driven by the $MYSQL_HOST setting.
    # $GUAC_USERHost determines from WHERE the new ${GUAC_USER} will be able to login to the database (either from specific remote IPs
    # or from localhost only.)
    if [[ "${MYSQL_HOST}" != "localhost" ]]; then
        GUAC_USERHost="%"
        echo "${GUAC_USER} is set to accept db logins from any host, you may wish to limit this to specific IPs." &>>${INSTALL_LOG}
    else
        GUAC_USERHost="localhost"
    fi

    # Execute SQL code to create the Guacamole database
    echo "Creating the Guacamole database..." &>>${INSTALL_LOG}
    SQLCODE="
DROP DATABASE IF EXISTS ${GUAC_DB};
CREATE DATABASE IF NOT EXISTS ${GUAC_DB};
CREATE USER IF NOT EXISTS '${GUAC_USER}'@'${GUAC_USERHost}' IDENTIFIED BY \"${GUAC_PWD}\";
GRANT SELECT,INSERT,UPDATE,DELETE ON ${GUAC_DB}.* TO '${GUAC_USER}'@'${GUAC_USERHost}';
FLUSH PRIVILEGES;"
    echo ${SQLCODE} | $DB_CMD -u root -D mysql -h ${MYSQL_HOST} -P ${MYSQL_PORT}
    if [[ $? -ne 0 ]]; then
        echo "Failed" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi

    # Add Guacamole schema to newly created database
    echo "Adding database tables..." &>>${INSTALL_LOG}
    cat guacamole-auth-jdbc-${GUAC_VERSION}/mysql/schema/*.sql | $DB_CMD -u root -D ${GUAC_DB} -p${MYSQL_ROOT_PWD}
    if [[ $? -ne 0 ]]; then
        echo "Failed" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Apply Secure MySQL installation settings
if [[ "${SECURE_MYSQL}" = true ]] && [[ "${INSTALL_MYSQL}" = true ]]; then
    echo "Applying mysql_secure_installation settings..." &>>${INSTALL_LOG}
    SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"$MYSQL_ROOT_PWD\r\"
expect \"Switch to unix_socket authentication\"
send \"n\r\"
expect \"Change the root password?\"
send \"n\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
    echo "$SECURE_MYSQL" &>>${INSTALL_LOG}
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Restart MySQL service
if [[ "${INSTALL_MYSQL}" = true ]]; then
    echo "Restarting MySQL service & enable at boot..." &>>${INSTALL_LOG}
    # Set MySQl to start at boot
    systemctl enable mysql
    systemctl restart mysql
    if [[ $? -ne 0 ]]; then
        echo "Failed" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Create guacd.conf and localhost IP binding.
echo "Binding guacd to 127.0.0.1 port 4822..." &>>${INSTALL_LOG}
cat >/etc/guacamole/guacd.conf <<-"EOF"
[server]
bind_host = 127.0.0.1
bind_port = 4822
EOF
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Ensure guacd is started
echo "Starting guacd service & enable at boot..." &>>${INSTALL_LOG}
# Update the systemd unit file the default daemon to the chosen service account
sed -i "s/\bdaemon\b/${GUACD_ACCOUNT}/g" /etc/systemd/system/guacd.service
systemctl daemon-reload
systemctl enable guacd
systemctl stop guacd 2>/dev/null
systemctl start guacd
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Redirect the Tomcat URL to its root to avoid typing the extra /guacamole path (if not using a reverse proxy)
if [[ "${GUAC_URL_REDIR}" = true ]] && [[ "${INSTALL_NGINX}" = false ]]; then
    echo "Redirecting the Tomcat http root url to /guacamole..." &>>${INSTALL_LOG}
    systemctl stop ${TOMCAT_VERSION}
    mv /var/lib/${TOMCAT_VERSION}/webapps/ROOT/index.html /var/lib/${TOMCAT_VERSION}/webapps/ROOT/index.html.old
    touch /var/lib/${TOMCAT_VERSION}/webapps/ROOT/index.jsp
    echo "<% response.sendRedirect(\"/guacamole\");%>" >>/var/lib/${TOMCAT_VERSION}/webapps/ROOT/index.jsp
    systemctl start ${TOMCAT_VERSION}
    if [[ $? -ne 0 ]]; then
        echo "Failed. See ${INSTALL_LOG}" 1>&2
        exit 1
    else
        echo "OK" &>>${INSTALL_LOG}
    fi
fi

# Update Linux firewall
echo "Updating firewall rules to allow only SSH and tcp 8080..." &>>${INSTALL_LOG}
ufw default allow outgoing >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
ufw allow 8080/tcp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1
ufw logging off >/dev/null 2>&1 # Reduce firewall logging noise
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Cleanup
echo "Cleaning up Guacamole source files..." &>>${INSTALL_LOG}
rm -rf guacamole-*
rm -rf mysql-connector-j-*
rm -rf mariadb_repo_setup
unset MYSQL_PWD
apt-get -y remove expect &>>${INSTALL_LOG}
apt-get -y autoremove &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Done
