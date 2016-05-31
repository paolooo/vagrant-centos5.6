if $percona_values == undef { $percona_values = hiera_hash('percona', false) }
if $php_values == undef { $php_values = hiera_hash('php', false) }
if $apache_values == undef { $apache_values = hiera_hash('apache', false) }
if $nginx_values == undef { $nginx_values = hiera_hash('nginx', false) }

if hash_key_equals($percona_values, 'install', 1) {

  if hash_key_equals($percona_values, 'install_server', 1) {
    $percona_server = true
  } else {
    $percona_server = false
  }

  if hash_key_equals($apache_values, 'install', 1)
    or hash_key_equals($nginx_values, 'install', 1)
  {
    $percona_webserver_restart = true
  } else {
    $percona_webserver_restart = false
  }

  if hash_key_equals($php_values, 'install', 1) {
    $percona_php_installed = true
    $percona_php_package   = 'php'
  } elsif hash_key_equals($hhvm_values, 'install', 1) {
    $percona_php_installed = true
    $percona_php_package   = 'hhvm'
  } else {
    $percona_php_installed = false
  }

  $root_username = 'root'

  if $percona_values['root_password'] {
    $root_password = $percona_values['root_password']
  } else {
    $root_password = ''
  }

  $mgmt_cnf =  '/etc/.puppet.cnf'

  $configuration = {
    'mysqld/max_connections' => 150,
    'mysqld/skip-name-resolve' => '',
    'mysqld/key_buffer_size' => '32M',
    'mysqld/ft_min_word_len' => 3,
    'mysqld/innodb_file_per_table' => 1,
    'mysqld/innodb_buffer_pool_size' => '1024M',
    'mysqld/innodb_file_format' => 'Barracuda',
    'mysqld/innodb_read_ahead_threshold' => 0,
    'mysqld/innodb_doublewrite' => 1,
    'mysqld/long_query_time' => 2,
    'mysqld/slow_query_log' => 1,
    'mysqld/slow_query_log_file' => '/var/log/mysql/mysql-slow.log',
    'mysqld/net_buffer_length' => '512K',
    'mysqld/read_buffer_size' => '1M',
    'mysqld/sort_buffer_size' => '1M',
    'mysqld/join_buffer_size' => '1M',
    'mysqld/performance_schema' => 'OFF',
    'mysqld/expire-logs-days' => 1
  }

  percona::mgmt_cnf { "${mgmt_cnf}":
    password => $root_password,
  }

  class { 'percona':
    server => $percona_server,
    percona_version => $percona_values['version'],
    configuration => $configuration,
    manage_repo => true,
  }

  percona::adminpass{ "${root_username}":
      password  => $root_password,
  }

  if count($percona_values['databases']) > 0 {

    $root_info = {
        root_username => $root_username,
        root_password => $root_password
    }


    each( $percona_values['databases'] ) |$key, $database| {
      $database_merged = delete(merge($database, {
        'dbname' => $database['name'],
      }), 'name')

      create_resources( percona_db, {
        "${key}" => $database_merged
      }, $root_info)
    }

  }

  if $percona_php_installed and $percona_php_package == 'php' {

    if $::osfamily == 'redhat' and $php_values['version'] == '53' {
      $percona_php_module = 'mysql'
    } elsif $::lsbdistcodename == 'lucid' or $::lsbdistcodename == 'squeeze' {
      $percona_php_module = 'mysql'
    } else {
      $percona_php_module = 'mysqlnd'
    }

    if ! defined(Puphet::Php::Module[$percona_php_module]) {
      puphpet::php::module { $percona_php_module:
        service_autorestart => $percona_webserver_restart,
      }
    }
  }

  if hash_key_equals($percona_values, 'adminer', 1)
    and $percona_php_installed
    and ! defined(Class['puphpet::adminer'])
  {

    $percona_apache_webroot = $puphpet::apache::params::default_vhost_dir
    $percona_nginx_webroot  = $puphpet::params::nginx_webroot_location

    if hash_key_equals($apache_values, 'install', 1) {
      $percona_adminer_webroot_location = $percona_apache_webroot
    } elsif hash_key_equals($nginx_values, 'install', 1) {
      $percona_adminer_webroot_location = $percona_nginx_webroot
    } else {
      $percona_adminer_webroot_location = $percona_apache_webroot
    }

    class { 'puphpet::adminer':
      location    => "${percona_adminer_webroot_location}/adminer",
      owner       => 'www-data',
      php_package => $percona_php_package
    }
  }

}

define percona_db (
  $user,
  $password,
  $dbname      = $name,
  $charset     = 'utf8',
  $collate     = 'utf8_general_ci',
  $host        = 'localhost',
  $grant       = 'ALL',
  $sql_file    = '',
  $enforce_sql = false,
  $ensure      = 'present',
  $root_username,
  $root_password
) {

$hash1 = {'one' => 1, 'two' => 2}
$hash2 = {'two' => 'dos', 'three' => 'tres'}
$merged_hash = merge($hash1, $hash2)

  $db_tables = "${dbname}.*"

  exec { "create-${dbname}-db":
    unless => "/usr/bin/mysql -u${root_username} -p${root_password} ${dbname}",
    command => "/usr/bin/mysql -u${root_username} -p${root_password} -e \"CREATE DATABASE IF NOT EXISTS ${dbname}; GRANT ALL ON ${db_tables} TO ${user}@${host} IDENTIFIED BY '${password}';\"",
    require => [Percona::Adminpass["${root_username}"], Service[$::percona::service_name]],
  }

  if $sql_file {
    notify { "sql_file: ${sql_file} ${root_username} ${root_password} ${dbname}": }
    exec{ "import-${dbname}-db":
      command     => "/usr/bin/mysql -u${user} -p${password} ${dbname} < ${sql_file}",
      logoutput   => true,
      refreshonly => $refresh,
      require     => [Exec["create-${dbname}-db"]],
    }
  }
}
