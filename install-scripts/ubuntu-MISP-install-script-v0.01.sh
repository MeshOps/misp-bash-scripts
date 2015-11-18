#!/bin/bash

#Variables you can edit
MISP="MISP"
MISPDIRNAME="${MISP}"
MISPDIRLOC="/var/www/${MISPDIRNAME}"
MISPREPO="https://github.com/MISP/MISP.git"
MISPVERSION"2.4-beta"
MISPDBNET="127.0.0.1"

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

#MYSQL DB info
MYSQLPASS="misp"
MISPDBUSER="misp"
MISPDB="misp"
MISPDBPASS="${MYSQLPASS}"

set -e -x
#Debian MISP install
apt-get update && apt-get upgrade -y

# Install useful utils
apt-get install -y rsync curl sudo rng-tools
#apt-get install -y munin munin-node

# Install the MISP dependencies:
apt-get install -y gcc zip php-pear git redis-server make \
libxml2-dev libxslt1-dev zlib1g-dev php5-dev libapache2-mod-php5 php5-mysql
##UNSURE if needed
#php5-curl

pear install Crypt_GPG
pear install Net_GeoIP

# Obtain MISP Repo via git
git clone ${MISPREPO} ${MISPDIRLOC}
git checkout ${MISPVERSION}

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
#pecl install redis
apt-get install -y php5-redis
# Note that the php5-redis package in Debian stable (wheezy) only exists in the backports repository: http://backports.debian.org/Instructions/
# After installing it, enable it in your php.ini file
#vim /etc/php5/apache2/php.ini
# add the following line:
#extension=redis.so

# Restart Apache
apachectl restart

# To use the scheduler worker for scheduled tasks, do the following:
cp -fva /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

#5/ Set the permissions
----------------------

# Check if the permissions are set correctly using the following commands as root:
chown -R www-data:www-data /var/www/MISP
#chmod -R 750 /var/www/MISP
#chmod -R g+ws /var/www/MISP/app/tmp
#chmod -R g+ws /var/www/MISP/app/files
#chmod -R g+ws /var/www/MISP/app/files/scripts/tmp

#BETTER!!
find /var/www/MISP -type d -exec chmod 2750 {} \+
find /var/www/MISP -type f -exec chmod 2640 {} \+
find /var/www/MISP/app/{tmp,files} -type d -exec chmod 2770 {} \+
find /var/www/MISP/app/{tmp,files} -type f -exec chmod 660 {} \+
find /var/www/MISP/app/Console -type f -exec chmod 770 {} \+

## CREATE DB ETC
EXPECTED_ARGS=3
E_BADARGS=65
MYSQL=`which mysql`
  
Q1="CREATE DATABASE IF NOT EXISTS $1;"
Q2="GRANT USAGE ON *.* TO $2@localhost IDENTIFIED BY '$3';"
Q3="GRANT ALL PRIVILEGES ON $1.* TO $2@localhost;"
Q4="FLUSH PRIVILEGES;"
SQL="${Q1}${Q2}${Q3}${Q4}"
  
if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: $0 misp misp misp"
  exit $E_BADARGS
fi
  
$MYSQL -umisp -pmisp -e "$SQL"

mysql -u misp -p${MISPDBPASS} misp < ${MISPDIRLOC}/INSTALL/MYSQL.sql

cp ${MISPDIRLOC}/INSTALL/apache.misp /etc/apache2/sites-available/misp.conf

a2dissite 000-default
a2ensite misp
a2enmod rewrite
apachectl restart

8/ MISP configuration
---------------------
# There are 4 sample configuration files in /var/www/MISP/app/Config that need to be copied
cd ${MISPDIRLOC}/app/Config
cp -a bootstrap.default.php bootstrap.php
cp -a database.default.php database.php
cp -a core.default.php core.php
cp -a config.default.php config.php
cd -


8/ MISP configuration
---------------------
# There are 4 sample configuration files in /var/www/MISP/app/Config that need to be copied
cd /var/www/MISP/app/Config
cp -va bootstrap.default.php bootstrap.php
cp -va database.default.php database.php
cp -va core.default.php core.php
cp -va config.default.php config.php

# Configure the fields in the newly created files:
# database.php : login, port, password, database
# bootstrap.php: uncomment the last 3 lines to enable the background workers (see below)
# CakePlugin::loadAll(array('CakeResque' => array('bootstrap' => true)));

# To enable the background workers, if you have installed the package required for it in 4/, uncomment the following lines:
# in core.php (if you have just recently updated MISP, just add this line at the end of the file):
# require_once dirname(__DIR__) . '/Vendor/autoload.php';

# Important! Change the salt key in /var/www/MISP/app/Config/config.php
# The salt key must be an at least 32 byte long string.
# The admin user account will be generated on the first login, make sure that the salt is changed before you create that user
# If you forget to do this step, and you are still dealing with a fresh installation, just alter the salt,
# delete the user from mysql and log in again using the default admin credentials (admin@admin.test / admin)

#Add this line after in Config/bootstrap.php
#After
# CakePlugin::loadAll(array('CakeResque' => array('bootstrap' => true)));
#Configure::write('MISP.background_jobs', true);


#CHECK out replacing this with sed
#'baseurl' => '192.168.1.30',

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
#chmod +x /var/www/MISP/app/Console/worker/start.sh
#sudo vim /etc/rc.local
# Add the following line before the last line (exit 0). Make sure that you replace www-data with your apache user:
#sed -i "/exit 0/i\su www-data -c 'bash ${MISPDIRLOC}/app/Console/worker/start.sh'" /etc/rc.local
#
#
#pip install pyzmq
# Now log in using the webinterface:
# The default user/pass = admin@admin.test/admin

# Using the server settings tool in the admin interface (Administration -> Server Settings), set MISP up to your preference
# It is especially vital that no critical issues remain!
# start the workers by navigating to the workers tab and clicking restart all workers

#Don't forget to change the email, password and authentication key after installation.

#Things to change in app/Config/config.php
#'email' => 'email@address.com',
#'baseurl' => '192.168.1.30',
#    'email' => 'email@address.com',
#    'contact' => 'email@address.com',
#  'MISP' =>
#  array (
#    'baseurl' => '192.168.1.30',
#    'footerpart1' => 'Powered by MISP',
#    'footerpart2' => '&copy; Belgian Defense CERT & NCIRC',
#    'org' => 'ORGNAME',
#    'showorg' => true,
#    'background_jobs' => true,
#    'cached_attachments' => false,
#    'email' => 'email@address.com',
#    'contact' => 'email@address.com',
#    'cveurl' => 'http://web.nvd.nist.gov/view/vuln/detail?vulnId=',
#    'disablerestalert' => false,
#    'default_event_distribution' => '0',
#    'default_attribute_distribution' => 'event',
#    'tagging' => true,
#    'full_tags_on_event_index' => true,
#    'footer_logo' => '',
#    'take_ownership_xml_import' => false,
#    'unpublishedprivate' => false,
#  ),
##
##  'GnuPG' =>
##  array (
##    'onlyencrypted' => false,
##    'email' => '',
##    'homedir' => '',
##    'password' => '',
##    'bodyonlyencrypted' => false,
##  ),
#
######
