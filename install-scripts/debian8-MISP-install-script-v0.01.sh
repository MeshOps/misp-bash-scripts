#!/bin/bash
set -e -x

USAGE="Usage: $(basename $0) [-hv] args"
#Check if user is root
[ $(id -u) -ne 0 ] && {
  echo "This program must be run by the root user!"
  }
#Check if Debian is the Linux Distro being used
if [ ! -f /etc/debian_version ];
  then
    echo "Unsupported Linux Distro! ....Exiting";
    exit 1;
fi

# Install useful utils
apt-get install -y apg rsync curl sudo rng-tools openssh-server
#apt-get install -y munin munin-node

#Variables you can edit
# Login credentials information
CREDSFILE="/root/.credentials.txt"

MISP="MISP"
MISPDIRNAME="${MISP}"
MISPDIRLOC="/var/www/${MISPDIRNAME}"
MISPREPO="https://github.com/MISP/MISP.git"
MISPVERSION="2.4-beta"
MISPDBHOST="localhost"
MISPDBPORT="3306"
MISPDBPREFIX=""

# CYBOX info
CYBOX="python-cybox"
CYBOXDIRNAME="${CYBOX}"
CYBOXDIRLOC="${MISPDIRLOC}/app/files/scripts/${CYBOXDIRNAME}"
CYBOXREPO="https://github.com/CybOXProject/python-cybox.git"

# STIX info
STIX="python-stix"
STIXDIRNAME="${STIX}"
STIXDIRLOC="${MISPDIRLOC}/app/files/scripts/${STIXDIRNAME}"
STIXREPO="https://github.com/STIXProject/python-stix.git"

#Composer URI
COMPOSERURI="https://getcomposer.org/installer"

#MySQL Variables
MYSQL_VER="mysql-server-5.5"
MYSQL_ROOT_PASS=$(apg -q -a 1 -n 1 -m 15 -x 15 -M NCL)
MYSQL_USER="misp"
MYSQL_USER_DB="misp"
MYSQL_USER_PASS=$(apg -q -a 1 -n 1 -m 15 -x 15 -M NCL)

# MISP config.php values
MISPSALT=$(apg -q -a 1 -n 1 -m 32 -x 32 -M NCLS)

# Set Apt-Cacher-NG Proxy
APTPROXY="http://192.168.1.91:3142/"
echo -e "[+] Configuring APT repositories...\n"
# Enabling APT-CACHER-NG PROXY
echo "Acquire::http::Proxy \"${APTPROXY}\";" > /etc/apt/apt.conf

#Debian MISP install
apt-get update && apt-get upgrade -y

# Install the MISP dependencies:
apt-get install -y gcc zip php-pear git redis-server make openssl apache2 \
libxml2-dev libxslt1-dev zlib1g-dev \
php5-dev libapache2-mod-php5 php5-mysql php5-curl

pear install Crypt_GPG
pear install Net_GeoIP

# Obtain MISP Repo via git
git clone ${MISPREPO} ${MISPDIRLOC}
#git checkout ${MISPVERSION}

# Fix Git PERMS
cd ${MISPDIRLOC} && git config core.filemode false && cd -

# install Mitre's STIX and its dependencies by running the following commands:
apt-get install -y python-dev python-pip libxml2-dev libxslt1-dev zlib1g-dev

cd ${MISPDIRLOC}/app/files/scripts

git clone ${CYBOXREPO} ${CYBOXDIRLOC}
git clone ${STIXREPO} ${STIXDIRLOC}
cd ${CYBOXDIRLOC} && git checkout v2.1.0.10 && python setup.py install && cd -

cd ${STIXDIRLOC} && git checkout v1.1.1.4 && python setup.py install && cd -

# Set up CakePHP
# CakePHP is now included as a submodule of MISP, execute the following commands to let git fetch it:
cd ${MISPDIRLOC} && git submodule init && git submodule update && cd -

# Once done, install CakeResque along with its dependencies if you intend to use the built in background jobs:
cd ${MISPDIRLOC}/app
curl -s ${COMPOSERURI} | php
php composer.phar require kamisama/cake-resque:4.1.2
php composer.phar config vendor-dir Vendor
#php composer.phar config vendor-dir vendor
php composer.phar install
cd -

# CakeResque normally uses phpredis to connect to redis, but it has a (buggy) fallback connector through Redisent. It is highly advised to install phpredis
pecl install redis
apt-get install -y php5-redis

# Restart Apache
apachectl restart

# To use the scheduler worker for scheduled tasks, do the following:
cp -fva ${MISPDIRLOC}/INSTALL/setup/config.php ${MISPDIRLOC}/app/Plugin/CakeResque/Config/config.php

#5/ Set the permissions
#----------------------

# Check if the permissions are set correctly using the following commands as root:
chown -R www-data:www-data /var/www/MISP
find /var/www/MISP -type d -exec chmod 2750 {} \+
find /var/www/MISP -type f -exec chmod 2640 {} \+
find /var/www/MISP/app/{tmp,files} -type d -exec chmod 2770 {} \+
find /var/www/MISP/app/{tmp,files} -type f -exec chmod 660 {} \+
find /var/www/MISP/app/Console -type f -exec chmod 770 {} \+


export DEBIAN_FRONTEND=noninteractive
#Setup debconf for mysql-server
echo "${MYSQL_VER} mysql-server/root_password_again password ${MYSQL_ROOT_PASS}" | debconf-set-selections
echo "${MYSQL_VER} mysql-server/root_password password ${MYSQL_ROOT_PASS}" | debconf-set-selections

# Install mysql
apt-get install ${MYSQL_VER} -y

mysql --host=${MISPDBHOST} --user=root --password=${MYSQL_ROOT_PASS} -e "CREATE DATABASE IF NOT EXISTS $MYSQL_USER_DB;"
mysql --host=${MISPDBHOST} --user=root --password=${MYSQL_ROOT_PASS} -e "GRANT ALL PRIVILEGES ON ${MYSQL_USER_DB}.* TO ${MYSQL_USER}@${MISPDBHOST} IDENTIFIED BY '${MYSQL_USER_PASS}';"
mysql --host=${MISPDBHOST} --user=root --password=${MYSQL_ROOT_PASS} -e "FLUSH PRIVILEGES;"

mysql -u ${MYSQL_USER} -p${MYSQL_USER_PASS} ${MYSQL_USER_DB} < ${MISPDIRLOC}/INSTALL/MYSQL.sql


#Create and install a selfsigned certificate for Nginx
echo -e "[+] Creating a self signed SSL certificate for Nginx...\n"
echo -e "GB\nUnited Kingdom\nLondon\nMe5h Ltd.\
\nIT\nMe5h\nssl@me5h.com\n" | \
openssl req -x509 -nodes -days 365 -new -newkey rsa:2048 -keyout /etc/ssl/private/nginx.key -out /etc/ssl/certs/nginx.pem
chmod 600 /etc/ssl/private/nginx.key
chmod 644 /etc/ssl/certs/nginx.pem

cp ${MISPDIRLOC}/INSTALL/apache.misp /etc/apache2/sites-available/misp.conf

a2dissite 000-default
a2ensite misp
a2enmod rewrite
apachectl restart

#8/ MISP configuration
#---------------------
# There are 4 sample configuration files in /var/www/MISP/app/Config that need to be copied
cd ${MISPDIRLOC}/app/Config
cp -a bootstrap.default.php bootstrap.php
cp -a database.default.php database.php
cp -a core.default.php core.php
cp -a config.default.php config.php
cd -


#8/ MISP configuration
#---------------------
# There are 4 sample configuration files in /var/www/MISP/app/Config that need to be copied
cd /var/www/MISP/app/Config
cp -va bootstrap.default.php bootstrap.php
cp -va database.default.php database.php
cp -va core.default.php core.php
cp -va config.default.php config.php

echo -e "[+] Rewriting values for database connection in ${MISPDIRLOC}/app/Config/database.php...\n"
sed -i "s/'host' => 'localhost',/'host' => '${MISPDBHOST}',/g"  app/Config/database.php
sed -i "s/'login' => 'db login',/'login' => '${MYSQL_USER}',/g"  app/Config/database.php
sed -i "s/'port' => '3306',/'port' => '${MISPDBPORT}',/g"  app/Config/database.php
sed -i "s/'password' => 'db password',/'password' => '${MYSQL_USER_PASS}',/g"  app/Config/database.php
sed -i "s/'database' => 'misp',/'database' => '${MYSQL_USER_DB}',/g"  app/Config/database.php
sed -i "s/'prefix' => '',/'prefix' => '${MISPDBPREFIX}',/g"  app/Config/database.php

echo -e "[+] Loading CakePlugin by appending to ${MISPDIRLOC}/app/Config/bootstrap.php ...\n"
cat <<LOADCAKERESQ >> ${MISPDIRLOC}/app/Config/bootstrap.php
CakePlugin::loadAll(array(
        'CakeResque' => array('bootstrap' => true)
));

LOADCAKERESQ

echo -e "[+] Appending autoload to ${MISPDIRLOC}/app/Config/core.php ...\n"
cat <<VENDOR >> ${MISPDIRLOC}/app/Config/core.php
require_once dirname(__DIR__) . '/Vendor/autoload.php';

VENDOR

echo -e "[+] Appending background_jobs to ${MISPDIRLOC}/app/Config/bootstrap.php ...\n"
cat <<BACKGROUND >> ${MISPDIRLOC}/app/Config/bootstrap.php
Configure::write('MISP.background_jobs', true);

BACKGROUND

echo -e "[+] Rewriting values in config.php ...\n"
sed -i "s/'salt' => 'Rooraenietu8Eeyo<Qu2eeNfterd-dd+',/'salt' => '${MISPSALT}',/g"  app/Config/config.php

# and make sure the file permissions are still OK
chown -R www-data:www-data ${MISPDIRLOC}/app/Config
find ${MISPDIRLOC}/app/Config -type d -exec chmod 2750 {} \+
find ${MISPDIRLOC}/app/Config -type f -exec chmod 2640 {} \+

# Generate a GPG encryption key.
#mkdir ${MISPDIRLOC}/.gnupg
#mkdir -m 700 ${MISPDIRLOC}/.gnupg
#chown www-data:www-data ${MISPDIRLOC}/.gnupg
#sudo -u www-data gpg --homedir ${MISPDIRLOC}/.gnupg --gen-key

# The email address should match the one set in the config.php configuration file
# Make sure that you use the same settings in the MISP Server Settings tool (Described on line 184)

#rngd -r /dev/urandom &

# And export the public key to the webroot
#sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --export --armor YOUR-EMAIL > /var/www/MISP/app/webroot/gpg.asc

# To make the background workers start on boot
chmod +x /var/www/MISP/app/Console/worker/start.sh
sed -i "/exit 0/i\su www-data -c 'bash ${MISPDIRLOC}/app/Console/worker/start.sh'" /etc/rc.local

echo -e "[+] Install pyzmq using 'pip'...\n"
pip install pyzmq

# Send all necessary credential to a text file located where ever you
# specified in CREDSFILE="/path/to/credentials/file"
cat <<LEMP-creds > $CREDSFILE
Operating System:		Debian $OS_VER
MySQL installed version:	$MYSQL_VER
MySQL root password:		$MYSQL_ROOT_PASS
MySQL user:			$MYSQL_USER
MySQL database:			$MYSQL_USER_DB
MySQL user password:		$MYSQL_USER_PASS
MISP Version:			$MISPVERSION
MISP Database Host:		$MISPDBHOST
MISP Database Port:		$MISPDBPORT
MISP Database Prefix:		$MISPDBPREFIX
MISP admin user:		admin@admin.test
MISP ddmin password:		admin

LEMP-creds

chmod 600 ${CREDSFILE}
echo
echo -e "[+] Credentials file located at "${CREDSFILE}""
echo -e "[+] PLEASE DELETE FILE MANUALLY WHEN FINISHED!\n"

#Delete history of commands executed

echo -e "[+] Deleting history Bash history file..."
cat /dev/null > /root/.bash_history
history -c
