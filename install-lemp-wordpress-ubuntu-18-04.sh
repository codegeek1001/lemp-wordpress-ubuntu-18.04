#!/bin/sh

# Turn non interactive mode on so script can run without user involvement
export DEBIAN_FRONTEND=noninteractive

# initial variables
mysql_root_passwd=`date +%s | sha256sum | base64 | head -c 12`
wp_site_name=$1
wp_site_root=/var/www/$wp_site_name
wp_db_prefix=wp
wp_dbname=`date +%s | sha256sum | base64 | head -c 8`
wp_dbusr=`date +%s | sha256sum | base64 | head -c 10`
wp_dbusr_passwd=`date +%s | sha256sum | base64 | head -c 12`

# save passwords in tmp password file to retrieve if needed
passwd_file='/root/lemp-wordpress-ubuntu-18-04-passwords.txt'
touch $passwd_file

save_passwords_in_file() {
    echo "mysql root password: $mysql_root_passwd" >> $passwd_file
    echo "wordpress database user: $wp_dbusr" >> $passwd_file
      echo "wordpress database user password: $wp_dbusr_passwd" >> $passwd_file
    echo "wordpress database: $wp_dbname" >> $passwd_file
}

# Function to install PHP. Currently PHP 7.1
setup_php() {
    sudo apt-get update
    sudo apt-get install php7.1-fpm -y
    sudo apt-get install php7.1-cli php7.1-common php7.1-json php7.1-opcache php7.1-mysql php7.1-mbstring php7.1-mcrypt php7.1-zip php7.1-fpm php7.1-ldap php7.1-tidy php7.1-recode php7.1-curl -y
    # Configure PHP by mostly increasing default variables!
    sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.1/fpm/php.ini
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 20M/" /etc/php/7.1/fpm/php.ini
    sed -i "s/post_max_size = 8M/post_max_size = 20M/" /etc/php/7.1/fpm/php.ini
    sed -i "s/max_execution_time = 30/max_execution_time = 120/" /etc/php/7.1/fpm/php.ini
    sed -i "s/max_input_time = 60/max_input_time = 120/" /etc/php/7.1/fpm/php.ini
    sed -i "s/; max_input_vars = 1000/max_input_vars = 6000/" /etc/php/7.1/fpm/php.ini
    
}

# Install mysql. Currenly MySQL 5.7
setup_mysql() {
   
    apt-get -y install debconf-utils
    echo mysql-server mysql-server/root_password password $mysql_root_passwd | sudo debconf-set-selections
    echo mysql-server mysql-server/root_password_again password $mysql_root_passwd | sudo debconf-set-selections
    sudo apt-get -y install mysql-server mysql-client
    apt-get -y install mysql-server-5.7
}

setup_nginx() {
    #install nginx
    sudo apt-get update
    sudo apt-get -y install nginx
    # Adjust Firewall after Nginx is installed
    sudo ufw allow 'Nginx HTTP'

    # Backup default nginx sites-available and create a new sites-available for $wp_site_name
    cp -avr /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    cp -avr /etc/nginx/sites-available/default /etc/nginx/sites-available/$wp_site_name
   
   # backup existing nginx configuration file
   if [ ! -f /etc/nginx/nginx.conf.bak ]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    fi

    # settings for log file and cache
    sed -i "s/server_name _;/server_name _;\n\n\tlocation = \/favicon.ico {\n\t\tlog_not_found off;\n\t\taccess_log off;\n\t}/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/server_name _;/server_name _;\n\n\tlocation = \/robots.txt {\n\t\tlog_not_found off;\n\t\taccess_log off;\n\t}/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/server_name _;/server_name _;\n\n\tlocation ~* \\\.(js|css|ogg\|ogv\|svg\|svgz\|eot\|otf\|woff\|mp4\|ttf\|rss\|atom\|jpg\|jpeg\|gif\|png\|ico\|zip\|tgz\|gz\|rar\|bz2\|doc\|xls\|exe\|ppt\|tar\|mid\|midi\|wav\|bmp\|rtf)\$ {\n\t\texpires 30d;\n\t\tlog_not_found off;\n\t}/" /etc/nginx/sites-available/$wp_site_name

    
    # No .htaccess
    sed -i "s/#location ~ \/\\\.ht {/location ~ \/\\\.ht {/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/#\tdeny all;/\tdeny all;/" /etc/nginx/sites-available/$wp_site_name
    
    
    # gzip
    sed -i "s/# gzip_vary on;/gzip_vary on;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_proxied any;/gzip_proxied any;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_comp_level 6;/gzip_comp_level 6;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_buffers 16 8k;/gzip_buffers 16 8k;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_http_version 1.1;/gzip_http_version 1.1;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_min_length 256;/gzip_min_length 256;/" /etc/nginx/nginx.conf
    sed -i "s/# gzip_types text\/plain/gzip_types text\/plain application\/vnd.ms\-fontobject application\/x-font-ttf font\/opentype image\/svg+xml image\/x-icon/" /etc/nginx/nginx.conf
    
    # Change localhost to wp_site_name if needed
    if [ "$wp_site_name" != "localhost" ]; then
    sed -i "s/listen 80 default_server;/listen 80;/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/listen \[\:\:\]\:80 default_server;/listen \[\:\:\]\:80;/" /etc/nginx/sites-available/$wp_site_name
    fi

    # setup server_name and ensure that index.php is added
    sed -i "s/try_files \$uri \$uri\/ =404;/try_files \$uri \$uri\/ \/index.php\$is_args\$args;/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/server_name _;/server_name $wp_site_name;/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/root \/var\/www\/html;/root \/var\/www\/$wp_site_name;/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/index index.html/index index.php index.html/" /etc/nginx/sites-available/$wp_site_name

    
    # PHP-7.1-FPM setup in nginx to ensure PHP applications can be run
    sed -i "s/#location ~ \\\.php\$ {/location ~ \\\.php\$ {/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/#\tinclude snippets\/fastcgi-php.conf;/\tinclude snippets\/fastcgi-php.conf;/" /etc/nginx/sites-available/$wp_site_name
    sed -i "s/#\tfastcgi_pass unix:\/var\/run\/php\/php7.0-fpm.sock;/\tfastcgi_pass unix:\/run\/php\/php7.1-fpm.sock;\n\t\tinclude fastcgi_params;/" /etc/nginx/sites-available/$wp_site_name
    
    # Finalize and create a info.php file to double check configuration
    sed -i "s/\t#}/\t}/" /etc/nginx/sites-available/$wp_site_name
    mv /etc/nginx/sites-available/$wp_site_name /etc/nginx/sites-enabled/$wp_site_name
     rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/default

}



setup_wordpress() {
    # Install unzip first
    apt-get -y install unzip

    # Downloda WordPress from official WordPress Org site
    if [ -d /tmp/wp_files/ ]; then
    rm -rf /tmp/wp_files/*
    fi
   #Downloading & Unzipping WordPress Latest Release"
    wget https://wordpress.org/latest.zip -O /tmp/wp_files.zip;
    cd /tmp/;
    unzip /tmp/wp_files.zip;

    # Create directory for the specific $site_name
    mkdir -p $wp_site_root

    # copy the wp files initially downloaded at /tmp/wp_files into wp_site_root
    mv /tmp/wp_files/* $wp_site_root

    # setup wp-config.php file
    cp $wp_site_root/wp-config-sample.php $wp_site_root/wp-config.php
    sed -i "s/'WP_DEBUG', false);/'WP_DEBUG', false);\r\ndefine('WP_MEMORY_LIMIT', '96M');/" $wp_site_root/wp-config.php;
    sed -i "s|'DB_NAME', 'database_name_here'|'DB_NAME', '$wp_dbname'|g" $wp_site_root/wp-config.php;
    sed -i "s/'DB_USER', 'username_here'/'DB_USER', '$wp_dbusr'/g" $wp_site_root/wp-config.php;
    sed -i "s/'DB_PASSWORD', 'password_here'/'DB_PASSWORD', '$wp_dbusr_passwd'/g" $wp_site_root/wp-config.php;
    sed -i "s/\$table_prefix  = 'wp_';/\$table_prefix  = '$wp_db_prefix';/" $wp_site_root/wp-config.php;
    for i in `seq 1 8`
    do
    wp_salt=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#$%^&*()\-_ []{}<>~`+=,.;:/?|' | head -c 64 | sed -e 's/[\/&]/\\&/g');
    sed -i "0,/put your unique phrase here/s/put your unique phrase here/$wp_salt/" $wp_site_root/wp-config.php;
    done
    chown -Rf www-data:www-data $wp_site_root;

    # Remove initially downloaded WordPress files from /tmp
    rm -rf /tmp/wp_files
    rm -f /tmp/wp_files.zip


}

restart_services() {
    
    sudo systemctl restart php7.1-fpm
   sudo systemctl restart nginx
    sudo service mysql restart
    
}

# Function to run everything
run() {
    setup_php
    setup_nginx
    setup_mysql
    setup_wordpress
    restart_services
}

# Lets run it
run

