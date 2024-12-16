#!/bin/bash
#######################################################################################################################
# Add OpenID Connect SSO support for Guacamole
# For Ubuntu / Debian / Raspbian
# Kenneth Glassey
# December 2024
#######################################################################################################################

# If run as standalone and not from the main installer script, check the below variables are correct.

if ! [[ $(id -u) = 0 ]]; then
    echo -e "${LRED}Please run this script as sudo or root${NC}" 1>&2
    exit 1
fi

if [[ -z ${TOMCAT_VERSION} ]]; then
    TOMCAT_VERSION=$(ls /etc/ | grep tomcat)
fi
if [[ -z ${GUAC_VERSION} ]]; then
    GUAC_VERSION=$(grep -oP 'Guacamole.API_VERSION = "\K[0-9\.]+' /var/lib/${TOMCAT_VERSION}/webapps/guacamole/guacamole-common-js/modules/Version.js)
fi
if [[ -z ${GUAC_SOURCE_LINK} ]]; then
    GUAC_SOURCE_LINK="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VERSION}"
fi

OPENID_JAR="openid/guacamole-auth-sso-openid-${GUAC_VERSION}.jar"
SSO_TAR_NAME="guacamole-auth-sso-${GUAC_VERSION}"
SSO_TAR="${SSO_TAR_NAME}.tar.gz"
wget -q -O ${SSO_TAR} ${GUAC_SOURCE_LINK}/binary/${SSO_TAR} &>>${INSTALL_LOG}
tar -xzf ${SSO_TAR}
mv -f ${SSO_TAR_NAME}/${OPENID_JAR} /etc/guacamole/extensions/
chmod 664 /etc/guacamole/extensions/${OPENID_JAR}
echo -e "Installed guacamole-auth-sso-${GUAC_VERSION}" &>>${INSTALL_LOG}

systemctl restart ${TOMCAT_VERSION}
systemctl restart guacd

rm -rf guacamole-*

echo "Done!" &>>${INSTALL_LOG}
