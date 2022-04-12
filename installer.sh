#!/bin/bash

########################################################################
#                                                                      #
# Pterodactyl Installer #                         #
#                                                                      #
# This script is not associated with the official Pterodactyl Panel.   #
#                                                                      #
########################################################################


SSL_CONFIRM=""
SSLCONFIRM=""
SSLSTATUS=""
FQDN=""
AGREE=""
LASTNAME=""
FIRSTNAME=""
USERNAME=""
PASSWORD=""
DATABASE_PASSWORD=""
WEBSERVER="" 

output(){
    echo -e '\e[36m'"$1"'\e[0m';
}

warning(){
    echo -e '\e[31m'"$1"'\e[0m';
}

if [[ $EUID -ne 0 ]]; then
  echo "* Sorry, but you need to be root to run this script."
  exit 1
fi

if ! [ -x "$(command -v curl)" ]; then
  echo "* cURL is required to run this script."
  exit 1
fi



finish(){
    output "The script has ended. $(hyperlink "$appurl") to go to your Panel."
}

apachewebserver(){
    if  [ "$WEBSERVER" =  "apache" ]; then
        if  [ "$SSLCONFIRM" =  "yes" ]; then
            a2dissite 000-default.conf
            output "Configuring webserver..."
            curl -o /etc/apache2/sites-enabled/pterodactyl.conf https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/config/pterodactyl-apache-ssl.conf
            sed -i -e "s@<domain>@${FQDN}@g" /etc/apache2/sites-enabled/pterodactyl.conf
            certbot certonly --no-eff-email --email "$EMAIL" -d "$FQDN" || exit
            apt install libapache2-mod-php
            sudo a2enmod rewrite
            systemctl restart apache2
            finish
            fi
        else :
            a2dissite 000-default.conf
            output "Configuring webserver..."
            curl -o /etc/apache2/sites-enabled/pterodactyl.conf https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/config/pterodactyl-apache.conf
            sed -i -e "s@<domain>@${FQDN}@g" /etc/apache2/sites-enabled/pterodactyl.conf
            apt install libapache2-mod-php
            sudo a2enmod rewrite
            systemctl restart apache2
            finish
            fi
}

start(){
    output "The script will install Pterodactyl Panel, you will be asked for several things before installation."
    output "Do you agree to this?"
    output "(Y/N):"
    read -r AGREE

    if [[ "$AGREE" =~ [Yy] ]]; then
        AGREE=yes
        web
    fi
}

webserver(){
    if  [ "$WEBSERVER" =  "nginx" ]; then
        if  [ "$SSLCONFIRM" =  "true" ]; then
            rm -rf /etc/nginx/sites-enabled/default
            output "Configuring webserver..."
            curl -o /etc/nginx/sites-enabled/pterodactyl.conf https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/config/pterodactyl-nginx-ssl.conf
            sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
            certbot certonly --no-eff-email --email "$EMAIL" -d "$FQDN" || exit
            systemctl restart nginx
            apachewebserver
            fi
        else :
            rm -rf /etc/nginx/sites-enabled/default
            output "Configuring webserver..."
            curl -o /etc/nginx/sites-enabled/pterodactyl.conf https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/config/pterodactyl-nginx.conf
            sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
            systemctl restart nginx
            apachewebserver
            fi
}

extra(){
    if  [ "$lsb_dist" =  "ubuntu" ] || [ "$lsb_dist" =  "debian" ]; then
        output "Changing permissions..."
        chown -R www-data:www-data /var/www/pterodactyl/*
        curl -o /etc/systemd/system/pteroq.service https://raw.githubusercontent.com/guldkage/Pterodactyl-Installer/main/config/pteroq.service
        * * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1
        sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service
        sudo systemctl enable --now redis-server
        sudo systemctl enable --now pteroq.service
    fi
}

configuration(){
    output "Setting up the Panel..."
    [ "$SSL_CONFIRM" == true ] && appurl="https://$FQDN"
    [ "$SSL_CONFIRM" == false ] && appurl="http://$FQDN"

    php artisan p:environment:setup \
        --author="$EMAIL" \
        --url="$appurl" \
        --timezone="America/New_York" \
        --cache="redis" \
        --session="redis" \
        --queue="redis" \
        --redis-host="localhost" \
        --redis-pass="null" \
        --redis-port="6379" \
        --settings-ui=true

    php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="panel" \
        --username="pterodactyl" \
        --password="$DATABASE_PASSWORD"

    php artisan migrate --seed --force
    php artisan p:user:make \
        --email="$EMAIL" \
        --username="$USERNAME" \
        --name-first="$FIRSTNAME" \
        --name-last="$LASTNAME" \
        --password="$PASSWORD" \
        --admin=1
    extra
}

composer(){
    output "Installing composer.."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    files
}

files(){
    output "Downloading files... "
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl || exit
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env
    php artisan key:generate --force
    configuration
}

database(){
    warning ""
    output "Let's set up your database connection."
    output "Please enter a password for the pterodactyl user."
    warning ""
    read -r DATABASE_PASSWORD
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DATABASE_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"
    firstname
}

required(){
    output ""
    output "Installing packages..."
    output ""
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    add-apt-repository -y ppa:chris-lea/redis-server
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    apt-add-repository universe
    apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    database
}

begin(){
    output ""
    output "Let's begin the installation! Are you ready?"
    output "Continuing in 5 seconds.."
    sleep 5s
    composer
}

password(){
    output ""
    output "Please enter password for account"
    read -r PASSWORD
    begin
}


username(){
    output ""
    output "Please enter username for account"
    read -r USERNAME
    password
}


lastname(){
    output ""
    output "Please enter last name for account"
    read -r LASTNAME
    username
}

firstname(){
    output "In order to create an account on the Panel, we need some more information."
    output "You do not need to type in real first and last name."
    output ""
    output "Please enter first name for account"
    read -r FIRSTNAME
    lastname
}

fqdn(){
    output ""
    output "Enter your FQDN or IP"
    read -r FQDN
    required
}

ssl(){
    output ""
    output "Do you want to use SSL? This requires a domain."
    output "(Y/N):"
    read -r SSL_CONFIRM

    if [[ "$SSL_CONFIRM" =~ [Yy] ]]; then
        SSLSTATUS=true
        emailsslyes
    fi
    if [[ "$SSL_CONFIRM" =~ [Nn] ]]; then
        emailsslno
    fi
}

emailsslyes(){
    warning ""
    warning "Read:"
    output "The script now asks for your email. It will be shared with Lets Encrypt to complete the SSL. It will also be used to setup the Panel."
    output "If you do not agree, stop the script."
    warning ""
    output "Please enter your email"
    read -r EMAIL
    fqdn
}

emailsslno(){
    warning ""
    warning "Read:"
    output "The script now asks for your email. It will be used to setup the Panel."
    output "If you do not agree, stop the script."
    warning ""
    output "Please enter your email"
    read -r EMAIL
    fqdn
}

web(){
    output ""
    output "What webserver would you like to use?"
    output "[1] NGINX"
    output "[2] Apache"
    output ""
    read -r option
    case $option in
        1 ) option=1
            WEBSERVER="nginx"
            ssl
            ;;
        2 ) option=2
            WEBSERVER="apache"
            ssl
            ;;
        * ) output ""
            warning "Script will exit. Unexpected output."
            sleep 1s
            options
    esac
}

options(){
    output "Please select your installation option:"
    output "[1] Install Panel. | Installs latest version of Pterodactyl Panel"
    output "[2] Update Panel. | Updates your Panel to the latest version. May remove addons and themes."
    output "[3] Update Wings. | Updates your Wings to the latest version."
    output "[4] Update Both. | Updates your Panel and Wings to the latest versions."
    output ""
    output "[5] Uninstall Wings. | Uninstalls your Wings. THIS WILL ALSO REMOVE ALL OF YOUR SERVERS ON THE PANEL!"
    output "[6] Uninstall Panel. | Uninstalls your Panel. You will only be left with your database and web server."
    output ""
    read -r option
    case $option in
        1 ) option=1
            updatepanel
            ;;
        2 ) option=2
            updatewings
            ;;
        3 ) option=3
            updateboth
            ;;
        4 ) option=4
            warning "Hang on.... Uninstalling Wings..."
            uninstallwings
            ;;
        5 ) option=5
            warning "Hang on.... Uninstalling Panel..."
            uninstallpanel
            ;;
        * ) output ""
            warning "Please enter a valid option."
            warning "This script will exit."
            sleep 1s
            options
    esac
}

clear
output ""
warning "Pterodactyl Installer @ v1.0"
warning "https://github.com/guldkage/Pterodactyl-Installer"
output ""
output "This script is not resposible for any damages. The script has been tested several times without issues."
output "Support is not given."
output "This script will only work on a fresh installation. Proceed with caution if not having a fresh installation"
output ""
sleep 3s
options