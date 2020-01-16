#! /bin/bash

## AS root  (FROM https://www.digitalocean.com/community/tutorials/how-to-install-bacula-server-on-centos-7)

sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
yum install bacula-director bacula-storage bacula-console bacula-client mariadb-server -y
yum install nfs-utils -y
yum install httpd -y
yum install php php-gd php-gettext php-mysql php-pdo -y
yum install php-gd php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap curl curl-devel -y

systemctl enable mariadb
systemctl enable httpd.service
systemctl start mariadb
systemctl start httpd.service

/usr/libexec/bacula/grant_mysql_privileges
/usr/libexec/bacula/create_mysql_database -u root
/usr/libexec/bacula/make_mysql_tables -u bacula

mysql -e "UPDATE mysql.user SET Password = PASSWORD('equiinfra') WHERE User = 'root'"
mysql -e "DROP USER ''@'localhost'"
mysql -e "DROP USER ''@'$(hostname)'"
mysql -e "DROP DATABASE test"
mysql -e "FLUSH PRIVILEGES"
sleep 2
mysql -uroot -pequiinfra -Bse "UPDATE mysql.user SET Password=PASSWORD('equiinfra') WHERE User='bacula';"
mysql -uroot -pequiinfra -Bse "FLUSH PRIVILEGES;"
sleep 1
echo 1 | alternatives --config libbaccats.so ; echo

## BACKUP/RESTORE DIRs
mkdir -p /bacula/backup /bacula/restore
chown -R bacula:bacula /bacula
chmod -R 700 /bacula
cp /etc/bacula/bacula-dir.conf /etc/bacula/bacula-dir.conf.BAK
cp /etc/bacula/bacula-sd.conf /etc/bacula/bacula-sd.conf.BAK
cp /etc/bacula/bacula-fd.conf cp /etc/bacula/bacula-fd.conf.BAK

cat > /etc/bacula/bacula-dir.conf << 'EOF'
Director {                            # define myself
  Name = bacula-dir
  DIRport = 9101                # where we listen for UA connections
  QueryFile = "/etc/bacula/query.sql"
  WorkingDirectory = "/var/spool/bacula"
  PidDirectory = "/var/run"
  Maximum Concurrent Jobs = 1
  Password = "@@DIR_PASSWORD@@"         # Console password
  Messages = Daemon
  DirAddress = 0.0.0.0
}
JobDefs {
  Name = "DefaultJob"
  Type = Backup
  Level = Incremental
  Client = bacula-fd 
  FileSet = "Full Set"
  Schedule = "WeeklyCycle"
  Storage = File
  Messages = Standard
  Pool = File
  Priority = 10
  Write Bootstrap = "/var/spool/bacula/%c.bsr"
}
Job {
  Name = "BackupLocalFiles"
  JobDefs = "DefaultJob"
}
Job {
  Name = "BackupCatalog"
  JobDefs = "DefaultJob"
  Level = Full
  FileSet="Catalog"
  Schedule = "WeeklyCycleAfterBackup"
  # This creates an ASCII copy of the catalog
  # Arguments to make_catalog_backup.pl are:
  #  make_catalog_backup.pl <catalog-name>
  RunBeforeJob = "/usr/libexec/bacula/make_catalog_backup.pl MyCatalog"
  # This deletes the copy of the catalog
  RunAfterJob  = "/usr/libexec/bacula/delete_catalog_backup"
  Write Bootstrap = "/var/spool/bacula/%n.bsr"
  Priority = 11                   # run after main backup
}
Job {
  Name = "RestoreLocalFiles"
  Type = Restore
  Client=bacula-fd                 
  FileSet="Full Set"                  
  Storage = File                      
  Pool = Default
  Messages = Standard
  Where = /bacula/restore
}
FileSet {
  Name = "Full Set"
  Include {
    Options {
      signature = MD5
      compression = GZIP
    }
    File = /
  }
  Exclude {
    File = /var/spool/bacula
    File = /tmp
    File = /proc
    File = /tmp
    File = /.journal
    File = /.fsck
    File = /bacula
  }
}
Schedule {
  Name = "WeeklyCycle"
  Run = Full 1st sun at 23:05
  Run = Differential 2nd-5th sun at 23:05
  Run = Incremental mon-sat at 23:05
}
Schedule {
  Name = "WeeklyCycleAfterBackup"
  Run = Full sun-sat at 23:10
}
FileSet {
  Name = "Catalog"
  Include {
    Options {
      signature = MD5
    }
    File = "/var/spool/bacula/bacula.sql"
  }
}
Client {
  Name = bacula-fd
  Address = localhost
  FDPort = 9102
  Catalog = MyCatalog
  Password = "@@FD_PASSWORD@@"          # password for FileDaemon
  File Retention = 30 days            # 30 days
  Job Retention = 6 months            # six months
  AutoPrune = yes                     # Prune expired Jobs/Files
}
Storage {
  Name = File
  Address = 192.168.65.211                # N.B. Use a fully qualified name here
  SDPort = 9103
  Password = "@@SD_PASSWORD@@"
  Device = FileStorage
  Media Type = File
}
Catalog {
  Name = MyCatalog
  dbname = "bacula"; dbuser = "bacula"; dbpassword = "equiinfra"
}
Messages {
  Name = Standard
  mailcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula: %t %e of %c %l\" %r"
  operatorcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula: Intervention needed for %j\" %r"
  mail = root@localhost = all, !skipped            
  operator = root@localhost = mount
  console = all, !skipped, !saved
  append = "/var/log/bacula/bacula.log" = all, !skipped
  catalog = all
}
Messages {
  Name = Daemon
  mailcommand = "/usr/sbin/bsmtp -h localhost -f \"\(Bacula\) \<%r\>\" -s \"Bacula daemon message\" %r"
  mail = root@localhost = all, !skipped            
  console = all, !skipped, !saved
  append = "/var/log/bacula/bacula.log" = all, !skipped
}
Pool {
  Name = Default
  Pool Type = Backup
  Recycle = yes                       # Bacula can automatically recycle Volumes
  AutoPrune = yes                     # Prune expired volumes
  Volume Retention = 365 days         # one year
}
Pool {
  Name = File
  Pool Type = Backup
  Label Format = Local-
  Recycle = yes                       # Bacula can automatically recycle Volumes
  AutoPrune = yes                     # Prune expired volumes
  Volume Retention = 365 days         # one year
  Maximum Volume Bytes = 50G          # Limit Volume size to something reasonable
  Maximum Volumes = 100               # Limit number of Volumes in Pool
}
Pool {
  Name = Scratch
  Pool Type = Backup
}
Console {
  Name = bacula-mon
  Password = "@@MON_DIR_PASSWORD@@"
  CommandACL = status, .status
}
EOF

cat > /etc/bacula/bacula-dir.conf << 'EOF'
Storage {                             # definition of myself
  Name = bacula-sd
  SDPort = 9103                  # Director's port      
  WorkingDirectory = "/var/spool/bacula"
  Pid Directory = "/var/run"
  Maximum Concurrent Jobs = 20
  SDAddress = 192.168.65.211
}
Director {
  Name = bacula-dir
  Password = "@@SD_PASSWORD@@"
}
Director {
  Name = bacula-mon
  Password = "@@MON_SD_PASSWORD@@"
  Monitor = yes
}
Device {
  Name = FileStorage
  Media Type = File
  Archive Device = /bacula/backup
  LabelMedia = yes;                   # lets Bacula label unlabeled media
  Random Access = Yes;
  AutomaticMount = yes;               # when device opened, read it
  RemovableMedia = no;
  AlwaysOpen = no;
}
Messages {
  Name = Standard
  director = bacula-dir = all
}
EOF

cat > /etc/bacula/bacula-fd.conf << 'EOF'
Director {
  Name = bacula-dir
  Password = "@@FD_PASSWORD@@"
}
Director {
  Name = bacula-mon
  Password = "@@MON_FD_PASSWORD@@"
  Monitor = yes
}
FileDaemon {                          # this is me
  Name = bacula-fd
  FDport = 9102                  # where we listen for the director
  WorkingDirectory = /var/spool/bacula
  Pid Directory = /var/run
  Maximum Concurrent Jobs = 20
}
Messages {
  Name = Standard
  director = bacula-dir = all, !skipped, !restored
}
EOF

bacula-sd -tc /etc/bacula/bacula-sd.conf
bacula-dir -tc /etc/bacula/bacula-dir.conf
bacula-dir -tc /etc/bacula/bacula-fd.conf

## PASSWORDS SET
DIR_PASSWORD=`date +%s | sha256sum | base64 | head -c 33`
sed -i "s/@@DIR_PASSWORD@@/${DIR_PASSWORD}/" /etc/bacula/bacula-dir.conf
sed -i "s/@@DIR_PASSWORD@@/${DIR_PASSWORD}/" /etc/bacula/bconsole.conf
SD_PASSWORD=`date +%s | sha256sum | base64 | head -c 33`
sed -i "s/@@SD_PASSWORD@@/${SD_PASSWORD}/" /etc/bacula/bacula-sd.conf
sed -i "s/@@SD_PASSWORD@@/${SD_PASSWORD}/" /etc/bacula/bacula-dir.conf
FD_PASSWORD=`date +%s | sha256sum | base64 | head -c 33`
sed -i "s/@@FD_PASSWORD@@/${FD_PASSWORD}/" /etc/bacula/bacula-dir.conf
sed -i "s/@@FD_PASSWORD@@/${FD_PASSWORD}/" /etc/bacula/bacula-fd.conf


## Starting Services
systemctl enable bacula-dir
systemctl enable bacula-sd
systemctl enable bacula-fd
systemctl start bacula-dir
systemctl start bacula-sd
systemctl start bacula-fd


## Installing Webmin
cat > /etc/yum.repos.d/webmin.repo << 'EOF'
[Webmin]
name=Webmin Distribution Neutral
#baseurl=http://download.webmin.com/download/yum
mirrorlist=http://download.webmin.com/download/yum/mirrorlist
enabled=1
EOF
rpm --import http://www.webmin.com/jcameron-key.asc
yum repolist
yum install webmin  -y
chkconfig webmin on
service webmin start

## INSTALLING Bacula-web
mkdir -p /root/bacula-web
cd /root/bacula-web
curl -O -L https://www.bacula-web.org/files/bacula-web.org/downloads/bacula-web-latest.tgz
tar zxvf bacula-web-latest.tgz

cat > /root/bacula-web/bacula-web/application/config/config.php << 'EOF'
<?php

// Show inactive clients (false by default)
$config['show_inactive_clients'] = true;

// Hide empty pools (displayed by default)
$config['hide_empty_pools'] = false;

// Custom datetime format (by default: Y-m-d H:i:s)
// Examples 
// $config['datetime_format'] = 'd/m/Y H:i:s';
// $config['datetime_format'] = 'm-d-Y H:i:s';

// Security
$config['enable_users_auth'] = true;

// Debug mode 
$config['debug'] = false;

// Translations
$config['language'] = 'en_US';

// en_US -> English 
// be_BY -> Belarusian
// ca_ES -> Catalan
// pl_PL -> Polish
// ru_RU -> Russian
// zh_CN -> Chinese
// no_NO -> Norwegian
// ja_JP -> Japanese
// sv_SE -> Swedish
// es_ES -> Spanish
// de_DE -> German
// it_IT -> Italian
// fr_FR -> French
// pt_BR -> Portuguese Brazil
// nl_NL -> Dutch

// Database connection parameters
// Copy/paste and adjust parameters according to your configuration

// For Unix socket connection, use parameters decribed below
// MySQL: use localhost for $config[0]['host']
// postgreSQL: do not define $config[0]['host']

// MySQL bacula catalog
$config[0]['label'] = 'Backup Server';
$config[0]['host'] = 'localhost';
$config[0]['login'] = 'bacula';
$config[0]['password'] = 'equiinfra';
$config[0]['db_name'] = 'bacula';
$config[0]['db_type'] = 'mysql';
$config[0]['db_port'] = '3306';

// postgreSQL bacula catalog
// $config[0]['label'] = 'Prod Server';
// $config[0]['host'] = 'db-server.domain.com';
// $config[0]['login'] = 'bacula';
// $config[0]['password'] = 'otherstrongpassword';
// $config[0]['db_name'] = 'bacula';
// $config[0]['db_type'] = 'pgsql';
// $config[0]['db_port'] = '5432'; 

// SQLite bacula catalog
// $config[0]['label'] = 'Dev backup server';
// $config[0]['db_type'] = 'sqlite';
// $config[0]['db_name'] = '/path/to/database/db.sdb';
// Copy the section below only if you have at least two Bacula catalog
// Don't forget to modify options such as label, host, login, password, etc.

// 2nd bacula catalog (MySQL)
// $config[1]['label'] = 'Dev backup server';
// $config[1]['host'] = 'mysql-server.domain.net';
// $config[1]['login'] = 'bacula';
// $config[1]['password'] = 'verystrongpassword';
// $config[1]['db_name'] = 'bacula';
// $config[1]['db_type'] = 'mysql';
// $config[1]['db_port'] = '3306';
EOF

mkdir -p /var/www/html/bacula
cp -r /root/bacula-web/bacula-web/* /var/www/html/bacula
chown -Rv apache: /var/www/html/bacula/

echo "Bacula-Web AT http://192.168.65.211/bacula/"
echo "WEBMIN AT https://192.168.65.211:10000"

reboot