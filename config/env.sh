#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Environment variables and defaults
# -----------------------------------------------------------------------------


# Check if required vars are presented and not empty
REQUIRED_VARS=(
	USER
	GROUP
	HOME_DIR
	SERVER_IP
	EXTERNAL_IP
	INTERNAL_NETWORK
)

# main
TODAY=$(date +"%Y_%m_%d")
PASSWORD=$(openssl rand 60 | openssl base64 -A)
# admin
USER="bibo"
# root
GROUP="bibo"
# home
HOME_DIR="/home/${USER}"

#LOG_FILE="./logs/install.log"

# web
WEB_ROOT="/var/www/html"
# example
HOST_NAME="example.com"
# example.com
DOMAIN_NAME="${HOST_NAME}"
MAIL_DOMAIN_NAME="mail.${DOMAIN_NAME}"
# example.com
SITE_NAME="${HOST_NAME}"
SITE_ADDR="https://${SITE_NAME}"
# Real email address, used for psad notifications
EMAIL_ADDR="example@gmail.com"
# local email address, used for postfix
LOCAL_EMAIL_ADDR="root@localhost"
# if needed
GIT_USER=""
GIT_PASSWORD=""
MYSQL_PASSWORD=""

# mod security
MOD_SECURITY_WHITELIST_LAN="192.168.0.0/24"
# public ip address
MOD_SECURITY_WHITELIST_REGEX="^@\.@\.@\.@"

# certificates

COUNTRY="BG"
STATE="Bulgaria"
LOCALITY="Sofia"
ORGANISATION="example"
ORGANISATION_UNIT="example"
COMMON_NAME="${DOMAIN_NAME}"
EMAIL="example@example.com"

# apache
APACHE2_CONF="/etc/apache2/apache2.conf"
MOD_EVASIVE="/etc/apache2/mods-available/evasive.conf"
MOD_SECURITY="/etc/apache2/conf-available/security.conf"
MOD_SECURITY_2="/etc/apache2/mods-available/security2.conf"
MOD_QOS="/etc/apache2/mods-available/qos.conf"

# php
PHP_PATH="/etc/php"

PHP_VERSIONS=(
	"/etc/php/7.4"
	"/etc/php/8.0"
	"/etc/php/8.1"
	"/etc/php/8.2"
	"/etc/php/8.3"
	"/etc/php/8.4"
)
PHP_VARIANTS=(apache2 fpm cli cgi)

# timezone
TIMEZONE="Europe/Sofia"
# session name
SESSION_NAME="PHPSESSID"

# network
CLOUDFLARE_IP_LIST="$HOME/Documents/cloudflare-ips.txt"

IS_ROUTER="false"
# 192.168.0.1
SERVER_IP="191.168.1.108"
# 1.2.3.4
EXTERNAL_IP="94.158.26.30"
# 192.168.0.0/24
INTERNAL_NETWORK="192.168.1.0/24"
# eno1
MAIN_NETWORK_INTERFACE=$(route | grep '^default' | grep -o '[^ ]*$')
SECOND_NETWORK_INTERFACE=""
LOOPBACK="lo"

# ports
SSH=22
PROFTP=21
HTTP=80
HTTPS=443
SMTP=25
IMAP=143
IMAPS=993
POP3=110
POP3S=995
DNS=53

# Fail2Ban
JAIL_LOCAL="/etc/fail2ban/jail.local"


# Create directories
DIRS=(
    "${HOME_DIR}/Downloads"
    "${HOME_DIR}/Documents"
    "${HOME_DIR}/Desktop"
    "${HOME_DIR}/Pictures"
)


DOCUMENTS="${HOME_DIR}/Documents"

# Install software
TOOLS=(
	"net-tools"
	"wget"
	"ufw"
	"htop"
	"dnsutils"
	"curl"
	"auditd"
	"sysstat"
	"unzip"
	"git"
	"fail2ban"
)

WEB=(
    "apache2"
    "php7.4"
    "php8.3"
    "php8.4"
    "redis"
    "varnish"
    "vsftpd"
    "libapache2-mod-security2"
    "libapache2-mod-evasive"
    "libapache2-mod-qos"
)

DATABASES=(
    "mariadb-server"
    "postgresql"
    "postgresql-contrib"
    "redis-server"
)

SECURITY=(
    "gnupg"
    "debsums"
    "cryptsetup"
    "chkrootkit"
    "clamav"
)

EMAIL=(
    "postfix"
    "mailutils"
)

SSL=(
	"certbot"
	"python3-certbot-apache"
	"letsencrypt"
)

FIREWALL=(
#    "iptables"
    "iptables-persistent"
    "psad"
    "aide"
)

EXTRAS=(
	"software-properties-common"
	"apt-transport-https"
	"apt-show-versions"
	"ca-certificates"
	"libpam-pwquality"
	"ca-certificates"
)

# -----------------------------------------------------------------------------
# Configuration files and directories to back up after installation
# -----------------------------------------------------------------------------
CONFIG_FILES=(
    # --- Apache ---
    "/etc/apache2/apache2.conf"
    "/etc/apache2/ports.conf"
    "/etc/apache2/mods-available/evasive.conf"
    "/etc/apache2/conf-available/security.conf"
    "/etc/apache2/mods-available/security2.conf"
    "/etc/apache2/mods-available/qos.conf"

    # --- PHP ---
    "/etc/php"

    # --- Databases ---
    "/etc/mysql/my.cnf"
    "/etc/mysql/mariadb.conf.d/50-server.cnf"
    "/etc/postgresql/"
    "/etc/redis/redis.conf"

    # --- Security & Networking ---
    "/etc/ufw/ufw.conf"
    "/etc/ssh/sshd_config"
    "/etc/fail2ban/jail.conf"
    "/etc/fail2ban/jail.local"
    "/etc/letsencrypt/"
    "/etc/psad/psad.conf"
    "/etc/aide/aide.conf"

    # --- System ---
    "/etc/hosts"
    "/etc/hostname"
    "/etc/resolv.conf"
    "/etc/network/interfaces"
    "/etc/netplan/"
)


# Install php extensions
PHP_EXTENSIONS=(
    "cli"
    "fpm"
    "common"
    "mysql"
    "zip"
    "gd"
    "mbstring"
    "curl"
    "bcmath"
    "fileinfo"
    "tokenizer"
    "ctype"
    "pdo"
    "xml"
    "xmlwriter"
    "xmlreader"
    "apcu"
    "imagick"
    "gmp"
)

APACHE_MODULES=(
    "headers"
    "rewrite"
    "ssl"
    "evasive"
    "security"
    "proxy"
    "envvars"
    "http2"
    "remoteip"
	"qos"
    "env"
    "dir"
    "mime"
)
