#!/usr/bin/env bash

echo "Start services - httpd, mysql, and php-fpm"
service httpd start
service mysql start
service php-fpm start
