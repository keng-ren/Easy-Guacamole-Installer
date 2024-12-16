#!/bin/bash
######################################################################################################################
# Guacamole appliance setup script
# For Ubuntu / Debian / Raspbian
# David Harrop
# April 2023
#######################################################################################################################

# To install the latest code snapshot:
# wget https://raw.githubusercontent.com/itiligent/Guacamole-Install/main/1-setup.sh && chmod +x 1-setup.sh && ./1-setup.sh

# 1-setup.sh is a central script that manages all inputs, options and sequences other included 'install' scripts.
# 2-install-guacamole downloads Guacamole source and exectutes all Guacamole's build instructions.
# 3-install-nginx.sh automatically installs and configures Nginx to work as an http port 80 front end to Guacamole.
# 4a-install-tls-self-signed-nginx.sh sets up the new Nginx/Guacamole front end with self signed TLS certificates.
# 4b-install-tls-letsencrypt-nginx.sh sets up Nginx with public TLS certificates from LetsEncrypt.
# Scripts with "add" in their name can be run post install to add optional features not included in the main install.

# For troubleshooting check logs or place Guacamole in debug mode:
#     tail -f /var/log/syslog /var/log/tomcat*/*.out guac-setup/guacamole_setup.log
#     sudo systemctl stop guacd && sudo /usr/local/sbin/guacd -L debug -f

#######################################################################################################################
# Unattended install instructions:

# Highly recommend building a custom Linux image and running this install from a systemd service unit.

# Setup your network configuration with systemd .network files and use systemd-resolved,
# rather than specifying the server name and/or domain via this script.

#######################################################################################################################
# Script pre-flight checks and settings ###############################################################################
#######################################################################################################################

journal_ns="easy-guac-setup"


# Check to see if any previous version of build files exist, if so stop and check to be safe.
if [[ "$(find . -maxdepth 1 \( -name 'guacamole-*' -o -name 'mysql-connector-j-*' \))" != "" ]]; then
    systemd-cat -t ${journal_ns} echo "Possible previous install files detected in current build path. Please review and remove old guacamole install files before proceeding. Setup aborting."
    exit 1
fi

# Query the OS version
source /etc/os-release

#######################################################################################################################
# Core setup variables and mandatory inputs - EDIT VARIABLE VALUES TO SUIT ############################################
#######################################################################################################################

# GitHub download branch
GITHUB="https://raw.githubusercontent.com/keng-ren/Easy-Guacamole-Installer/unattended"

# Version of Guacamole to install
GUAC_VERSION="1.5.5"
GUAC_SOURCE_LINK="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VERSION}"

# MySQL Connector/J version to install
MYSQLJCON="9.1.0"
MYSQLJCON_SOURCE_LINK="https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-${MYSQLJCON}.tar.gz"

# Provide a specific MySQL version e.g. 11.1.2 or leave blank "" to use distro default MySQL packages.
# See https://mariadb.org/mariadb/all-releases/ for available versions.
MYSQL_VERSION=""
MARIADB_SOURCE_LINK="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"

# Reverse proxy uses this URL (Guacamole default is http://localhost:8080/guacamole/):
GUAC_URL=http://localhost:8080/guacamole/

# Get the default route interface IP. May need to manually override this for multi homed systems or where cloud images may use 127.0.x.x
DEFAULT_IP=$(ip addr show $(ip route | awk '/default/ { print $11" "$5 }'  | sort -n | awk '{ print $2 }' | xargs | cut -d ' ' -f 1 -) | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)

#######################################################################################################################
# Silent setup options - true/false or specific values below will skip prompt at install. EDIT TO SUIT ################
#######################################################################################################################
GUAC_DIR=""                     # Base directory for the guacamole setup
SERVER_NAME=""                  # Server hostname (blank = use the current hostname)
LOCAL_DOMAIN=""                 # Local DNS namespace/domain suffix (blank = keep the current suffix)
INSTALL_MYSQL="true"            # Install MySQL locally (true/false)
SECURE_MYSQL="false"             # Apply mysql secure configuration tool (true/false)
MYSQL_HOST=""                   # Blank "" = localhost MySQL install, adding a specific IP address will assume a remote MySQL instance
MYSQL_PORT=""                   # If blank "" default is 3306
GUAC_DB=""                      # If blank "" default is guacamole_db
GUAC_USER=""                    # If blank "" default is guacamole_user
MYSQL_ROOT_PWD=""               # Manadatory entry here or at script prompt
MYSQL_ROOT_PWD_FILE=""          # Path to file containing MySQL root password
GUAC_PWD=""                     # Manadatory entry here or at script prompt
GUAC_PWD_FILE=""                # Path to file containing the MySQL user password
GUACD_ACCOUNT="guacd"           # Service account guacd will run under (and will be very heavily locked down)
DB_TZ=$(cat /etc/timezone)      # Blank "" defaults to UTC, for local timezone: $(cat /etc/timezone)
INSTALL_TOTP="false"            # Add TOTP MFA extension (true/false), can't be installed simultaneously with DUO)
INSTALL_DUO="false"             # Add DUO MFA extension (true/false, can't be installed simultaneously with TOTP)
INSTALL_OPENID="false"               # Add OpenID Connect extension (true/false)
INSTALL_LDAP="false"            # Add Active Directory extension (true/false)
INSTALL_QCONNECT="false"        # Add Guacamole console quick connect feature (true/false)
INSTALL_HISTREC="false"         # Add Guacamole history recording storage feature (true/false)
HISTREC_PATH=""                 # If blank "" sets the Apache's default path of /var/lib/guacamole/recordings
GUAC_URL_REDIR="false"          # Auto redirect of host root URL http://xxx:8080 to http://xxx:8080/guacamole  (true/false)
INSTALL_NGINX="true"            # Install & configure Nginx reverse proxy http:80 frontend (true/false)
PROXY_SITE=""                   # Local DNS name for reverse proxy site and/or self signed TLS certificates (blank "" defaults to $DEFAULT_FQDN)
SELF_SIGN="false"               # Add self signed TLS/https support to Nginx (true/false, Let's Encrypt not available with this option)
RSA_KEYLENGTH="2048"            # Self signed RSA TLS key length. At least 2048, must not be blank
CERT_COUNTRY="AU"               # Self signed cert setup, 2 character country code only, must not be blank
CERT_STATE="Victoria"           # Self signed cert setup, must not be blank
CERT_LOCATION="Melbourne"       # Self signed cert setup, must not be blank
CERT_ORG="Itiligent"            # Self signed cert setup, must not be blank
CERT_OU="I.T."                  # Self signed cert setup, must not be blank
CERT_DAYS="3650"                # Self signed cert setup, days until self signed TLS cert expiry, blank = default 3650
LETS_ENCRYPT="false"            # Add Lets Encrypt public TLS cert for Nginx (true/false, self signed TLS not available with this option)
LE_DNS_NAME=""                  # Public DNS name for use with Lets Encrypt certificates, must match public DNS
LE_EMAIL=""                     # Webmaster email for Lets Encrypt notifications
BACKUP_EMAIL=""                 # Email address to send MySQL backup notifications to
BACKUP_RETENTION="30"           # Days to keep SQL backups locally
RDP_SHARE_HOST=""               # Custom RDP host name shown in Windows Explorer (eg. "RDP_SHARE_LABEL on RDP_SHARE_HOST"). Blank "" = $SERVER_NAME
RDP_SHARE_LABEL="RDP Share"     # Custom RDP shared drive name in Windows Explorer (eg. "RDP_SHARE_LABEL on RDP_SHARE_HOST" eg. "your RDP share name on server01"
RDP_PRINTER_LABEL="RDP Printer" # Custom RDP printer name shown in Windows
CRON_DENY_FILE="/etc/cron.deny" # Distro's cron deny file
SETUP_EMAIL="false"             # Install postfix for email notifications (true/false)

# OpenID Connect extension configuration
OPENID_AUTHORIZATION_ENDPOINT=""
OPENID_JWKS_ENDPOINT=""
OPENID_ISSUER=""
OPENID_CLIENT_ID=""
OPENID_REDIRECT_URI=""
OPENID_USERNAME_CLAIM_TYPE=""
OPENID_GROUPS_CLAIM_TYPE=""
OPENID_SCOPE=""
OPENID_ALLOWED_CLOCK_SKEW=""
OPENID_MAX_TOKEN_VALIDITY=""
OPENID_MAX_NONCE_VALIDITY=""

# Pull in variables from dotenv file
if [[ -f ".env" ]]; then
    set -a; source .env; set +a
fi

# Setup download and temp directory paths
if [[ -d "${GUAC_DIR}" ]]; then
    INSTALL_LOG="${GUAC_DIR}/guacamole_install.log"
    DOWNLOAD_DIR=${GUAC_DIR}/guac-setup
    DB_BACKUP_DIR=${GUAC_DIR}/mysqlbackups
    mkdir -p ${DOWNLOAD_DIR}
    mkdir -p ${DB_BACKUP_DIR}
else
    systemd-cat -t ${journal_ns} echo "GUAC_DIR must be defined, exiting..."
    exit 1
fi

#######################################################################################################################
# Download GitHub setup scripts. BEFORE RUNNING SETUP, COMMENT OUT DOWNLOAD LINES OF ANY SCRIPTS YOU HAVE EDITED ! ####
#######################################################################################################################

# Script branding header
echo "Guacamole ${GUAC_VERSION} Auto Installer - Powered by Itiligent - Unattended edition by KenG" &>>${INSTALL_LOG}

# Download the suite of install scripts from GitHub
cd $DOWNLOAD_DIR
echo "Downloading the Guacamole build suite..." &>>${INSTALL_LOG}
wget -q ${GITHUB}/2-install-guacamole.sh -O 2-install-guacamole.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/3-install-nginx.sh -O 3-install-nginx.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/4a-install-tls-self-signed-nginx.sh -O 4a-install-tls-self-signed-nginx.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/4b-install-tls-letsencrypt-nginx.sh -O 4b-install-tls-letsencrypt-nginx.sh &>>${INSTALL_LOG}

# Download the suite of optional feature adding scripts
wget -q ${GITHUB}/guac-optional-features/add-auth-duo.sh -O add-auth-duo.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-auth-ldap.sh -O add-auth-ldap.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-auth-totp.sh -O add-auth-totp.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-auth-openid.sh -O add-auth-openid.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-xtra-quickconnect.sh -O add-xtra-quickconnect.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-xtra-histrecstor.sh -O add-xtra-histrecstor.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-smtp-relay-o365.sh -O add-smtp-relay-o365.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-tls-guac-daemon.sh -O add-tls-guac-daemon.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-optional-features/add-fail2ban.sh -O add-fail2ban.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/guac-management/backup-guacamole.sh -O backup-guacamole.sh &>>${INSTALL_LOG}
wget -q ${GITHUB}/upgrade-guacamole.sh -O upgrade-guacamole.sh &>>${INSTALL_LOG}

# Download the dark theme & branding template
wget -q ${GITHUB}/branding.jar -O branding.jar &>>${INSTALL_LOG}
chmod +x *.sh

apt-get update -qq &> /dev/null

#######################################################################################################################
# Package dependency handling and workarounds for various distros, MODIFY ONLY IF NEEDED ##############################
#######################################################################################################################

# Standardise on a lexicon for the different MySQL package options
if [[ -z "${MYSQL_VERSION}" ]]; then
    # Use Linux distro default version.
    MYSQLSRV="default-mysql-server default-mysql-client mysql-common" # Server
    MYSQLCLIENT="default-mysql-client" # Client
    DB_CMD="mysql" # The mysql -v command is depricated on some versions.
else
    # Use official mariadb.org repo
    MYSQLSRV="mariadb-server mariadb-client mariadb-common" # Server
    MYSQLCLIENT="mariadb-client" # Client
    DB_CMD="mariadb" # The mysql -v command is depricated on some versions.
fi

# Standardise on a lexicon for the differing dependency package names between distros
# Current package names for various distros are referenced at https://guacamole.apache.org/doc/gug/installing-guacamole.html
JPEGTURBO=""
LIBPNG=""
if [[ ${ID,,} = "ubuntu" ]] || [[ ${ID,,} = *"ubuntu"* ]] || [[ ${ID,,} = *"linuxmint"* ]]; then
    JPEGTURBO="libjpeg-turbo8-dev"
    LIBPNG="libpng-dev"
    # Just in case this repo is not present in the distro
    add-apt-repository -y universe &>>${INSTALL_LOG}
elif [[ ${ID,,} = "debian" ]] || [[ ${ID,,} = "raspbian" ]]; then
    JPEGTURBO="libjpeg62-turbo-dev"
    LIBPNG="libpng-dev"
fi

# Check for the more recent versions of Tomcat currently supported by the distro
if [[ $(apt-cache show tomcat10 2>/dev/null | egrep "Version: 10" | wc -l) -gt 0 ]]; then
    TOMCAT_VERSION="tomcat10"
elif [[ $(apt-cache show tomcat9 2>/dev/null | egrep "Version: 9" | wc -l) -gt 0 ]]; then
    TOMCAT_VERSION="tomcat9"
else
    # Default to this version
    TOMCAT_VERSION="tomcat9"
fi

#######################################################################################################################
# Ongoing fixes and workarounds as distros diverge/change #############################################################
#######################################################################################################################

# Workaround for Debian incompatibilities with later Tomcat versions. (Adds the oldstable repo and downgrades the Tomcat version)
if [[ ${ID,,} = "debian" && ${VERSION_CODENAME,,} = *"bookworm"* ]] || [[ ${ID,,} = "debian" && ${VERSION_CODENAME,,} = *"trixie"* ]]; then #(checks for upper and lower case)
    echo "deb http://deb.debian.org/debian/ bullseye main" | tee /etc/apt/sources.list.d/bullseye.list &> /dev/null
    apt-get update -qq &> /dev/null
    TOMCAT_VERSION="tomcat9"
fi

# Workaround for Ubuntu 23.x Tomcat 10 incompatibilities. Downgrades Tomcat to version 9 which is available from the Lunar repo.
if [[ ${ID,,} = "ubuntu" ]] && [[ ${VERSION_CODENAME,,} = *"lunar"* ]]; then
    TOMCAT_VERSION="tomcat9"
fi

# Workaround for Ubuntu 24.x Tomcat 10 incompatibilities. (Adds old Jammy repo and downgrades the Tomcat version)
if [[ ${ID,,} = "ubuntu" && ${VERSION_CODENAME,,} = *"noble"* ]]; then
    echo "deb http://archive.ubuntu.com/ubuntu/ jammy universe" | tee /etc/apt/sources.list.d/jammy.list &> /dev/null
    apt-get update -qq &> /dev/null
    TOMCAT_VERSION="tomcat9"
fi

# Uncomment here to force a specific Tomcat version.
# TOMCAT_VERSION="tomcat9"

# Workaround for 1.5.4 specific bug, see issue #31. This was fixed in 1.5.5
if [[ "${ID,,}" = "debian" && "${VERSION_CODENAME,,}" = *"bullseye"* ]] || [[ "${ID,,}" = "ubuntu" && "${VERSION_CODENAME,,}" = *"focal"* ]]; then
    IFS='.' read -ra guac_version_parts <<< "${GUAC_VERSION}"
    major="${guac_version_parts[0]}"
    minor="${guac_version_parts[1]}"
    patch="${guac_version_parts[2]}"
    # Uncomment 2nd line and comment first line if issue returns >=1.5.4 (See https://issues.apache.org/jira/browse/GUACAMOLE-1892))
	if (( major == 1 && minor == 5 && patch == 4 )); then
	#if (( major > 1 || (major == 1 && minor > 5) || ( major == 1 && minor == 5 && patch >= 4 ) )); then
      export LDFLAGS="-lrt"
    fi
fi

#######################################################################################################################
# DO NOT EDIT PAST THIS POINT! ########################################################################################
#######################################################################################################################

resolved_status=$(systemctl is-active systemd-resolved.service)



#######################################################################################################################
# Begin install menu prompts ##########################################################################################
#######################################################################################################################

# Consistent /etc/hosts and domain suffix values are needed for TLS implementation. The below approach
# allows the user to either hit enter at the prompt to keep current values, or enter new values for both. Silent install
# pre-set values (if provided) will bypass these prompts.

# Ensure SERVER_NAME is consistent with local host entries
if [[ -z ${SERVER_NAME} ]]; then
    SERVER_NAME=$HOSTNAME
else
    # A SERVER_NAME value was derived from a pre-set silent install option.
    # Apply the SERVER_NAME value & remove & update any old 127.0.1.1 localhost references
    $(hostnamectl set-hostname $SERVER_NAME &>/dev/null &) &>/dev/null
	sleep 1
    sed -i '/127.0.1.1/d' /etc/hosts &>>${INSTALL_LOG}
    echo '127.0.1.1       '${SERVER_NAME}'' | tee -a /etc/hosts &>>${INSTALL_LOG}
    $(systemctl restart systemd-hostnamed &>/dev/null &) &>/dev/null
fi

DEFAULT_FQDN=""
# Ensure LOCAL_DOMAIN suffix & localhost entries are consistent
if [[ -z ${LOCAL_DOMAIN} ]]; then
    all_domains=()
    while read line; do
    if [[ -n "$line" ]]; then
        all_domains+=("$line");
    fi;
    done < <(grep -E '^search[[:space:]]+' /etc/resolv.conf | awk '/search/ {for (i=2; i<=NF; i++) print $i}')

    while read line; do
    if [[ -n "$line" ]] && ! printf '%s\0' "${all_domains[@]}" | grep -Fxzq -- "$line"; then
        all_domains+=("$line");
    fi;
    done < <(grep -E '^domain[[:space:]]+' /etc/resolv.conf | awk '/domain/ {for (i=2; i<=NF; i++) print $i}')
else
    echo "User specified domain: ${LOCAL_DOMAIN}" &>>${INSTALL_LOG}
    DEFAULT_FQDN="${SERVER_NAME}.${LOCAL_DOMAIN}"
fi

# Default RDP share and host labels will now use the updated $SERVER_NAME value as default (if not otherwise specified in silent setup options).
if [[ -z ${RDP_SHARE_HOST} ]]; then
    RDP_SHARE_HOST=$SERVER_NAME
fi

# Set MYSQL settings and values
echo -e "MySQL setup options:"
if [[ -z ${INSTALL_MYSQL} ]]; then
    INSTALL_MYSQL=true
fi

if [[ -z ${SECURE_MYSQL} ]] && [[ "${INSTALL_MYSQL}" = true ]]; then
    SECURE_MYSQL=false
fi

# Checking if a mysql host given, if not set a default
if [[ -z "${MYSQL_HOST}" ]]; then
    MYSQL_HOST="localhost"
fi
# Checking if a mysql port given, if not set a default
if [[ -z "${MYSQL_PORT}" ]]; then
    MYSQL_PORT="3306"
fi
# Checking if a database name given, if not set a default
if [[ -z "${GUAC_DB}" ]]; then
    GUAC_DB="guacamole_db"
fi
# Checking if a mysql user given, if not set a default
if [[ -z "${GUAC_USER}" ]]; then
    GUAC_USER="guacamole_user"
fi

# MySQL root password. No root pw needed for remote instances.
if [[ "${INSTALL_MYSQL}" = true ]]; then
    if [[ -f "${MYSQL_ROOT_PWD_FILE}" ]]; then
            MYSQL_ROOT_PWD=$(cat "${MYSQL_ROOT_PWD_FILE}")
    elif [[ -z "${MYSQL_ROOT_PWD}" ]]; then
        echo "Root password for MySQL deployment is required" &>>${INSTALL_LOG}
    fi
fi

if [[ -f "${GUAC_PWD_FILE}" ]]; then
        GUAC_PWD=$(cat "${GUAC_PWD_FILE}")
elif [[ -z "${GUAC_PWD}" ]]; then
    echo "User password for the MySQL database is required" &>>${INSTALL_LOG}
fi

if [[ -z ${SETUP_EMAIL} ]]; then
    SETUP_EMAIL=false
fi

# TODO: Make sure an empty backup email does not cause errors - search for BACKUP_EMAIL in script files

if [[ -z ${INSTALL_TOTP} ]]; then
    INSTALL_TOTP=false
fi

if [[ -z ${INSTALL_DUO} ]]; then
    INSTALL_DUO=false
fi

# We can't install TOTP and Duo at the same time (option not supported by Guacamole)
if [[ "${INSTALL_TOTP}" = true ]] && [[ "${INSTALL_DUO}" = true ]]; then
    echo "GUAC MFA: TOTP and Duo cannot be installed at the same time." &>>${INSTALL_LOG}
    exit 1
fi

if [[ -z "${INSTALL_LDAP}" ]]; then
    INSTALL_LDAP=false
fi

# Prompt to install OpenID Connect SSO extension
if [[ -z "${INSTALL_OPENID}" ]]; then
    INSTALL_OPENID=false
fi


# Quick Connect feature (some higher security use cases may not want this)
if [[ -z "${INSTALL_QCONNECT}" ]]; then
    INSTALL_QCONNECT=false
fi

# History Recorded Storage feature
if [[ -z "${INSTALL_HISTREC}" ]]; then
    INSTALL_HISTREC=false
fi

HISTREC_PATH_DEFAULT=/var/lib/guacamole/recordings # Apache default
# If no custom path is given, assume the Apache default path
if [[ -z "${HISTREC_PATH}" ]] && [[ "${INSTALL_HISTREC}" = true ]]; then
    HISTREC_PATH="${HISTREC_PATH_DEFAULT}"
fi


# Guacamole front end reverse proxy option
if [[ -z ${INSTALL_NGINX} ]];
    INSTALL_NGINX=false
fi

# Prompt to redirect http://root:8080 to http://root:8080/guacamole if not installing reverse proxy
if [[ -z ${GUAC_URL_REDIR} ]] && [[ "${INSTALL_NGINX}" = false ]]; then
    GUAC_URL_REDIR=true
fi

if [[ ${GUAC_URL_REDIR} = true ]] && [[ "${INSTALL_NGINX}" = true ]]; then
    GUAC_URL_REDIR=false
fi

# If no proxy site dns name is given, lets assume the default FQDN is the proxy site name
if [[ -z "${PROXY_SITE}" ]] && [[ -n "${DEFAULT_FQDN}" ]] && [[ "${INSTALL_NGINX}" = true ]]; then
    PROXY_SITE="${DEFAULT_FQDN}"
fi

# Self-signed TLS reverse proxy option
if [[ -z ${SELF_SIGN} ]] && [[ "${INSTALL_NGINX}" = true ]]; then
    SELF_SIGN=false
fi

# Self-signed TLS certificate expiry
if [[ -z "${CERT_DAYS}" ]] && [[ "${SELF_SIGN}" = true ]]; then
    CERT_DAYS="3650"
fi

# Let's Encrypt TLS reverse proxy configuration option
if [[ -z ${LETS_ENCRYPT} ]] && [[ "${INSTALL_NGINX}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    LETS_ENCRYPT=false
fi

# Let's Encrypt public dns name
if [[ -z ${LE_DNS_NAME} ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    echo "Public DNS name is required for Let's Encrypt configuration" &>>${INSTALL_LOG}
    exit 1
fi

# Let's Encrypt admin email
if [[ -z ${LE_EMAIL} ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" = false ]]; then
    echo "Admin email is required for Let's Encrypt configuration" &>>${INSTALL_LOG}
    exit 1
fi

#######################################################################################################################
# Start global setup actions  #########################################################################################
#######################################################################################################################

echo "Beginning Guacamole setup..." &>>${INSTALL_LOG}

echo "Synchronising the install script suite with the selected installation options..." &>>${INSTALL_LOG}
# Sync the various manual config scripts with the relevant variables selected at install
# This way scripts can be run at a later time without modification to match the original install
sed -i "s|MYSQL_HOST=|MYSQL_HOST='${MYSQL_HOST}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|MYSQL_PORT=|MYSQL_PORT='${MYSQL_PORT}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_USER=|GUAC_USER='${GUAC_USER}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_PWD=|GUAC_PWD='${GUAC_PWD}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|GUAC_DB=|GUAC_DB='${GUAC_DB}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|DB_BACKUP_DIR=|DB_BACKUP_DIR='${DB_BACKUP_DIR}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|BACKUP_EMAIL=|BACKUP_EMAIL='${BACKUP_EMAIL}'|g" $DOWNLOAD_DIR/backup-guacamole.sh
sed -i "s|BACKUP_RETENTION=|BACKUP_RETENTION='${BACKUP_RETENTION}'|g" $DOWNLOAD_DIR/backup-guacamole.sh

sed -i "s|CERT_COUNTRY=|CERT_COUNTRY='${CERT_COUNTRY}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_STATE=|CERT_STATE='${CERT_STATE}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_LOCATION=|CERT_LOCATION='${CERT_LOCATION=}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_ORG=|CERT_ORG='${CERT_ORG}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_OU=|CERT_OU='${CERT_OU}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh
sed -i "s|CERT_DAYS=|CERT_DAYS='${CERT_DAYS}'|g" $DOWNLOAD_DIR/add-tls-guac-daemon.sh

sed -i "s|INSTALL_MYSQL=|INSTALL_MYSQL='${INSTALL_MYSQL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_HOST=|MYSQL_HOST='${MYSQL_HOST}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_PORT=|MYSQL_PORT='${MYSQL_PORT}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_DB=|GUAC_DB='${GUAC_DB}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|MYSQL_ROOT_PWD=|MYSQL_ROOT_PWD='${MYSQL_ROOT_PWD}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_USER=|GUAC_USER='${GUAC_USER}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUAC_PWD=|GUAC_PWD='${GUAC_PWD}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|GUACD_ACCOUNT=|GUACD_ACCOUNT='${GUACD_ACCOUNT}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh

sed -i "s|RDP_SHARE_HOST=|RDP_SHARE_HOST='${RDP_SHARE_HOST}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|RDP_SHARE_LABEL=|RDP_SHARE_LABEL='${RDP_SHARE_LABEL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh
sed -i "s|RDP_PRINTER_LABEL=|RDP_PRINTER_LABEL='${RDP_PRINTER_LABEL}'|g" $DOWNLOAD_DIR/upgrade-guacamole.sh

# TODO: Split the 3-install-nginx.sh script into two files:
# 1. The install and global configuration script
# 2. The site configurations script - run per discovered domain
if [[ ${#all_domains[@]} -gt 0 ]]; then
    for i in ${!all_domains[@]}; do
        dom=${all_domains[$i]}
        config_file="${DOWNLOAD_DIR}/3-config-nginx-${i}.sh"
        echo "Creating NGINX site configuration file '${config_file}' for domain '${dom}'" &>>${INSTALL_LOG}
        cp -f "${DOWNLOAD_DIR}/3-config-nginx.sh" "${config_file}"
        sed -i "s|PROXY_SITE=|PROXY_SITE='${SERVER_NAME}.${dom}'|g" "${config_file}"
        sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" "${config_file}"
        sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" "${config_file}"
    done
else
    echo "Writing proxy URL '${PROXY_SITE}' to NGINX configuration file" &>>${INSTALL_LOG}
    sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" "${DOWNLOAD_DIR}/3-config-nginx.sh"
    sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" "${DOWNLOAD_DIR}/3-config-nginx.sh"
    sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" "${DOWNLOAD_DIR}/3-config-nginx.sh"

fi

sed -i "s|DOWNLOAD_DIR=|DOWNLOAD_DIR='${DOWNLOAD_DIR}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_COUNTRY=|CERT_COUNTRY='${CERT_COUNTRY}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_STATE=|CERT_STATE='${CERT_STATE}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_LOCATION=|CERT_LOCATION='${CERT_LOCATION=}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_ORG=|CERT_ORG='${CERT_ORG}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_OU=|CERT_OU='${CERT_OU}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|CERT_DAYS=|CERT_DAYS='${CERT_DAYS}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|DEFAULT_IP=|DEFAULT_IP='${DEFAULT_IP}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh
sed -i "s|RSA_KEYLENGTH=|RSA_KEYLENGTH='${RSA_KEYLENGTH}'|g" $DOWNLOAD_DIR/4a-install-tls-self-signed-nginx.sh

sed -i "s|DOWNLOAD_DIR=|DOWNLOAD_DIR='${DOWNLOAD_DIR}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|PROXY_SITE=|PROXY_SITE='${PROXY_SITE}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|GUAC_URL=|GUAC_URL='${GUAC_URL}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|LE_DNS_NAME=|LE_DNS_NAME='${LE_DNS_NAME}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|LE_EMAIL=|LE_EMAIL='${LE_EMAIL}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh
sed -i "s|INSTALL_LOG=|INSTALL_LOG='${INSTALL_LOG}'|g" $DOWNLOAD_DIR/4b-install-tls-letsencrypt-nginx.sh

sed -i "s|LOCAL_DOMAIN=|LOCAL_DOMAIN='${LOCAL_DOMAIN}'|g" $DOWNLOAD_DIR/add-smtp-relay-o365.sh
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" &>>${INSTALL_LOG}
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
fi

# Export the required variables for use by child install scripts
export DOWNLOAD_DIR="${DOWNLOAD_DIR}"
export GUAC_VERSION=$GUAC_VERSION
export GUAC_SOURCE_LINK=$GUAC_SOURCE_LINK
export ID=$ID
export VERSION_ID=$VERSION_ID
export VERSION_CODENAME=$VERSION_CODENAME
export MYSQLJCON=$MYSQLJCON
export MYSQLJCON_SOURCE_LINK=$MYSQLJCON_SOURCE_LINK
export MYSQL_VERSION=$MYSQL_VERSION
export MARIADB_SOURCE_LINK=$MARIADB_SOURCE_LINK
export MYSQLSRV=$MYSQLSRV
export MYSQLCLIENT=$MYSQLCLIENT
export DB_CMD=$DB_CMD
export TOMCAT_VERSION=$TOMCAT_VERSION
export GUAC_URL=$GUAC_URL
export INSTALL_LOG=$INSTALL_LOG
export JPEGTURBO=$JPEGTURBO
export LIBPNG=$LIBPNG
export INSTALL_MYSQL=$INSTALL_MYSQL
export SECURE_MYSQL=$SECURE_MYSQL
export MYSQL_HOST=$MYSQL_HOST
export MYSQL_PORT=$MYSQL_PORT
export GUAC_DB=$GUAC_DB
export GUAC_USER=$GUAC_USER
export MYSQL_ROOT_PWD="${MYSQL_ROOT_PWD}"
export GUAC_PWD="${GUAC_PWD}"
export GUACD_ACCOUNT=$GUACD_ACCOUNT
export DB_TZ="${DB_TZ}"
export INSTALL_TOTP=$INSTALL_TOTP
export INSTALL_DUO=$INSTALL_DUO
export INSTALL_LDAP=$INSTALL_LDAP
export INSTALL_OPENID=$INSTALL_OPENID
export INSTALL_QCONNECT=$INSTALL_QCONNECT
export INSTALL_HISTREC=$INSTALL_HISTREC
export HISTREC_PATH="${HISTREC_PATH}"
export GUAC_URL_REDIR=$GUAC_URL_REDIR
export INSTALL_NGINX=$INSTALL_NGINX
export PROXY_SITE=$PROXY_SITE
export RSA_KEYLENGTH=$RSA_KEYLENGTH
export DEFAULT_IP=$DEFAULT_IP
export CERT_COUNTRY=$CERT_COUNTRY
export CERT_STATE="${CERT_STATE}"
export CERT_LOCATION="${CERT_LOCATION}"
export CERT_ORG="${CERT_ORG}"
export CERT_OU="${CERT_OU}"
export CERT_DAYS=$CERT_DAYS
export LE_DNS_NAME=$LE_DNS_NAME
export LE_EMAIL=$LE_EMAIL
export BACKUP_EMAIL=$BACKUP_EMAIL
export RDP_SHARE_HOST="${RDP_SHARE_HOST}"
export RDP_SHARE_LABEL="${RDP_SHARE_LABEL}"
export RDP_PRINTER_LABEL="${RDP_PRINTER_LABEL}"
export LOCAL_DOMAIN=$LOCAL_DOMAIN
export CRON_DENY_FILE=$CRON_DENY_FILE
export OPENID_AUTHORIZATION_ENDPOINT="${OPENID_AUTHORIZATION_ENDPOINT}"
export OPENID_JWKS_ENDPOINT="${OPENID_JWKS_ENDPOINT}"
export OPENID_ISSUER="${OPENID_ISSUER}"
export OPENID_CLIENT_ID="${OPENID_CLIENT_ID}"
export OPENID_REDIRECT_URI="${OPENID_REDIRECT_URI}"
export OPENID_USERNAME_CLAIM_TYPE="${OPENID_USERNAME_CLAIM_TYPE}"
export OPENID_GROUPS_CLAIM_TYPE="${OPENID_GROUPS_CLAIM_TYPE}"
export OPENID_SCOPE="${OPENID_SCOPE}"
export OPENID_ALLOWED_CLOCK_SKEW="${OPENID_ALLOWED_CLOCK_SKEW}"
export OPENID_MAX_TOKEN_VALIDITY="${OPENID_MAX_TOKEN_VALIDITY}"
export OPENID_MAX_NONCE_VALIDITY="${OPENID_MAX_NONCE_VALIDITY}"

# Run the Guacamole install script (with all exported variables from this current shell)
-E ./2-install-guacamole.sh
if [[ $? -ne 0 ]]; then
    echo -e "Guacamole install failed. See ${INSTALL_LOG}" 1>&2
    exit 1
if [[ "${INSTALL_NGINX}" = false ]]; then
    if [[ "${GUAC_URL_REDIR}" = true ]]; then
        guac_path=""
    else
        guac_path="/guacamole"
    fi
    if [[ ${#all_domains[@]} -gt 0 ]]; then
        for dom in ${all_domains[@]}; do
            echo "Guacamole install complete\nhttp://${SERVER_NAME}.${dom}:8080${guac_path} - login user/pass: guacadmin/guacadmin\n***Be sure to change the password***" &>>${INSTALL_LOG}
        done
    else
        echo "Guacamole install complete\nhttp://${PROXY_SITE}:8080 - login user/pass: guacadmin/guacadmin\n***Be sure to change the password***" &>>${INSTALL_LOG}
    fi
fi

# Add a Guacamole database backup (Mon-Fri 12:00am) into the current user's cron
mv $DOWNLOAD_DIR/backup-guacamole.sh $DB_BACKUP_DIR
crontab -l >cron_1
# Remove any pre-existing entry just in case
sed -i '/# backup guacamole/d' cron_1
# Create the backup job
echo "0 0 * * 1-5 ${DB_BACKUP_DIR}/backup-guacamole.sh # backup guacamole" >>cron_1
# Overwrite the old cron settings and cleanup
crontab cron_1
rm cron_1

#######################################################################################################################
# Start optional setup actions   ######################################################################################
#######################################################################################################################

# Install Nginx reverse proxy front end to Guacamole if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]]; then
    -E ./3-install-nginx.sh
    echo "Nginx install complete" &>>${INSTALL_LOG}
    if [[ ${#all_domains[@]} -gt 0 ]]; then
        for i in ${!all_domains[@]}; do
            -E "./3-config-nginx-${i}.sh"
            dom=${all_domains[$i]}
            echo "NGINX server configured\nhttp://${SERVER_NAME}.${dom}:8080${guac_path} - login user/pass: guacadmin/guacadmin\n***Be sure to change the password***" &>>${INSTALL_LOG}
        done
    else
        -E "./3-config-nginx.sh"
        echo "Nginx server configured\nhttp://${PROXY_SITE} - admin login: guacadmin pass: guacadmin\n***Be sure to change the password***" &>>${INSTALL_LOG}
    fi
fi

# Apply self signed TLS certificates to Nginx reverse proxy if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]] && [[ "${SELF_SIGN}" = true ]] && [[ "${LETS_ENCRYPT}" != true ]]; then
    -E ./4a-install-tls-self-signed-nginx.sh ${PROXY_SITE} ${CERT_DAYS} ${DEFAULT_IP} | tee -a ${INSTALL_LOG} # Logged to capture client cert import instructions
    echo "Self signed certificate configured for Nginx \nhttps://${PROXY_SITE}  - login user/pass: guacadmin/guacadmin\n***Be sure to change the password***"
fi

# Apply Let's Encrypt TLS certificates to Nginx reverse proxy if option is selected (with all exported variables from this current shell)
if [[ "${INSTALL_NGINX}" = true ]] && [[ "${LETS_ENCRYPT}" = true ]] && [[ "${SELF_SIGN}" != true ]]; then
    -E ./4b-install-tls-letsencrypt-nginx.sh
    echo "Let's Encrypt TLS configured for Nginx \nhttps://${LE_DNS_NAME}  - login user/pass: guacadmin/guacadmin\n***Be sure to change the password***"
fi

# Duo Settings reminder - If Duo is selected you can't login to Guacamole until this extension is fully configured
if [[ $INSTALL_DUO == "true" ]]; then
    echo
    echo "Reminder: Duo requires extra account specific info configured in the\n/etc/guacamole/guacamole.properties file before you can log in to Guacamole."
    echo "See https://guacamole.apache.org/doc/gug/duo-auth.html"
fi

# LDAP Settings reminder, LDAP auth is not functional until the config is complete
if [[ $INSTALL_LDAP == "true" ]]; then
    echo
    echo "${LYELLOW}Reminder: LDAP requires that your LDAP directory configuration match the exact format\nadded to the /etc/guacamole/guacamole.properties file before LDAP auth will be active."
    echo "See https://guacamole.apache.org/doc/gug/ldap-auth.html"
fi

# OpenID Connect Settings reminder, LDAP auth is not functional until the config is complete
if [[ $INSTALL_OPENID == "true" ]]; then
    echo
    echo -e "${LYELLOW}Reminder: OpenID Connect requires that your OpenID Connect identity provider configuration match the exact format\nadded to the /etc/guacamole/guacamole.properties file before OpenID Connect auth will be active."
    echo -e "See https://guacamole.apache.org/doc/gug/openid-auth.html"
fi

# Tidy up
echo
echo "Removing build-essential package & cleaning up..." &>>${INSTALL_LOG}
mv $USER_HOME_DIR/1-setup.sh $DOWNLOAD_DIR
apt remove -y build-essential &>>${INSTALL_LOG} # Lets not leave build resources installed on a secure system
apt-get -y autoremove &>>${INSTALL_LOG}
if [[ $? -ne 0 ]]; then
    echo "Failed. See ${INSTALL_LOG}" 1>&2
    exit 1
else
    echo "OK" &>>${INSTALL_LOG}
    echo
fi

# Done
echo "Guacamole ${GUAC_VERSION} install complete!" &>>${INSTALL_LOG}
