#!/bin/bash

. ./util_functions.sh

# Default values
OTRS_BACKUP_DIR="/var/otrs/backups"
OTRS_CONFIG_DIR="${OTRS_ROOT}Kernel/"
OTRS_CONFIG_FILE="${OTRS_CONFIG_DIR}Config.pm"
OTRS_CONFIG_MOUNT_DIR="/Kernel"

mysqlcmd="mysql -uroot -h$OTRS_DB_SERVER -p$MYSQL_ROOT_PASSWORD "

function wait_for_db(){
  while true; do
    out="`$mysqlcmd -e "SELECT COUNT(*) FROM mysql.user;" 2>&1`"
    print_info $out
    echo "$out" | grep -E "COUNT|Enter" 2>&1 > /dev/null
    if [ $? -eq 0 ]; then
      print_info "MySQL server is up !"
      break
    fi
    print_warning "DB server still isn't up, sleeping a little bit ..."
    sleep 2
  done
}

function create_db(){
  print_info "Creating OTRS database..."
  $mysqlcmd -e "CREATE DATABASE IF NOT EXISTS $OTRS_DATABASE DEFAULT CHARACTER SET = utf8;"
  [ $? -gt 0 ] && print_error "Couldn't create OTRS database !!" && exit 1
  $mysqlcmd -e "GRANT ALL ON $OTRS_DATABASE.* to '$OTRS_DB_USER'@'%' identified by '$OTRS_DB_PASSWORD';"
  [ $? -gt 0 ] && print_error "Couldn't create database user !!" && exit 1
  $mysqlcmd -e "FLUSH PRIVILEGES;"
}

function restore_backup(){
  [ -z $1 ] && print_error "\n\e[1;31mERROR:\e[0m OTRS_BACKUP_DATE not set.\n" && exit 1

  # Check if a host-mounted volume for configuration storage was added to this container
  check_host_mount_dir

  # Check if OTRS database exists
  $mysqlcmd -e "USE $OTRS_DATABASE" 2>/dev/null
  if [ $? -eq 0  ]; then
    print_info "Dropping existing database...\n"
    $mysqlcmd -e "DROP DATABASE $OTRS_DATABASE"
  fi

  create_db

  # import database
  print_info "decompress SQL-file ..."
  gunzip $OTRS_BACKUP_DIR/$1/DatabaseBackup.sql.gz
  print_info "cat SQL-file into database"
  mysql -f -u${OTRS_DB_USER} -p${OTRS_DB_PASSWORD} -h${OTRS_DB_SERVER} ${OTRS_DATABASE} < $OTRS_BACKUP_DIR/$1/DatabaseBackup.sql
  [ $? -gt 0 ] && failed=yes
  print_info "compress SQL-file..."
  gzip $OTRS_BACKUP_DIR/$1/DatabaseBackup.sql
  if [ "$failed" == "yes" ]; then
    print_error "Couldn't restore database from OTRS backup !!"
    exit 1
  fi

  # Clear existing OTRS files
  cd ${OTRS_ROOT}
  find -maxdepth 1 -type d -not -name Kernel -not -name "." -not -name "var" -exec rm -r {} \;
  rm -rf ${OTRS_ROOT}Kernel/*
  cd var
  find -maxdepth 1 -type d -not -name article -not -name "." -exec rm -r {} \;
  rm -rf ${OTRS_ROOT}var/article/*

  # restore OTRS files
  print_info "Restoring ${OTRS_BACKUP_DIR}/${1}/Application.tar.gz ..."
  print_info "This may take a while..."
  cd ${OTRS_ROOT}
  tar -xzf $OTRS_BACKUP_DIR/$1/Application.tar.gz
  [ $? -gt 0 ] && print_error "Couldn't restore OTRS files from backup !!" && exit 1

  update_database_settings

  # Update file permissions
  ${OTRS_ROOT}bin/otrs.SetPermissions.pl --otrs-user=otrs --web-group=www-data ${OTRS_ROOT}

  # Get hostname and admin email settings
  OTRS_HOSTNAME=`su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Config::Dump FQDN" -s /bin/bash otrs`
  OTRS_ADMIN_EMAIL=`su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Config::Dump AdminEmail" -s /bin/bash otrs`
}

function update_database_settings() {
    #Update database settings in Config.pm
    update_config_value "DatabaseHost" $OTRS_DB_SERVER
    update_config_value "Database" $OTRS_DATABASE
    update_config_value "DatabaseUser" $OTRS_DB_USER
    update_config_value "DatabasePw" $OTRS_DB_PASSWORD
}

function update_config_value(){
  if grep -v ".*#.*$1" ${OTRS_CONFIG_FILE} | grep -q "[{\"']$1[}\"']"
  then
    sed  -i -r "s/($Self->\{['\"]?$1['\"]?\} *= *).*/\1'$2';/" ${OTRS_CONFIG_FILE}
  else
    sed -i "/$Self->{Home} = '\/opt\/otrs';/a \
    \$Self->{'$1'} = '$2';" ${OTRS_CONFIG_FILE}
  fi
}

function update_otrs_settings(){

  /otrs-update-setting.pl SecureMode option-mod-item -value 1
  /otrs-update-setting.pl ScriptAlias string-mod-item -value ""
  /otrs-update-setting.pl LogModule option-mod-item -value "Kernel::System::Log::SysLog"

  test -f /update-otrs-custom-settings.sh && . $_
}

function set_default_language(){
  if [ ! -z $OTRS_LANGUAGE ]; then
    print_info "Setting default language to: \e[92m'$OTRS_LANGUAGE'\e[0m"
    /otrs-update-setting.pl DefaultLanguage string-mod-item -value $OTRS_LANGUAGE
 fi
}

function set_ticket_counter() {
  if [ ! -z "${OTRS_TICKET_COUNTER}" ]; then
    print_info "Setting the start of the ticket counter to: \e[92m'$OTRS_TICKET_COUNTER'\e[0m"
    echo "$OTRS_TICKET_COUNTER" > ${OTRS_ROOT}var/log/TicketCounter.log
  fi
  if [ ! -z $OTRS_NUMBER_GENERATOR ]; then
    print_info "Setting ticket number generator to: \e[92m'$OTRS_NUMBER_GENERATOR'\e[0m"
    /otrs-update-setting.pl "Ticket::NumberGenerator" option-mod-item -value "Kernel::System::Ticket::Number::${OTRS_NUMBER_GENERATOR}"
  fi
}

function set_fetch_email_time(){
  if [ ! -z $OTRS_POSTMASTER_FETCH_TIME ]; then
    if [ $OTRS_POSTMASTER_FETCH_TIME -eq 0 ]; then
      print_info "Disabling fetching of postmaster emails."
      /otrs-update-setting.pl "Daemon::SchedulerCronTaskManager::Task###MailAccountFetch" disable
    else
      print_info "Setting Postmaster fetch emails time to \e[92m$OTRS_POSTMASTER_FETCH_TIME\e[0m minutes"
      /otrs-update-setting.pl "Daemon::SchedulerCronTaskManager::Task###MailAccountFetch" hash-mod-key-value -key Schedule -value "*/${OTRS_POSTMASTER_FETCH_TIME} * * * *"
    fi
  fi
}

function check_host_mount_dir(){
  # Copy the configuration from /Kernel (put there by the Dockerfile) to $OTRS_CONFIG_DIR
  # to be able to use host-mounted volumes. copy only if ${OTRS_CONFIG_DIR} doesn't exist
  if [ "$(ls -A ${OTRS_CONFIG_MOUNT_DIR})" ] && [ ! "$(ls -A ${OTRS_CONFIG_DIR})" ];
  then
    print_info "Found empty \e[92m${OTRS_CONFIG_DIR}\e[0m, copying default configuration to it..."
    mkdir -p ${OTRS_CONFIG_DIR}
    cp -rp ${OTRS_CONFIG_MOUNT_DIR}/* ${OTRS_CONFIG_DIR}
    if [ $? -eq 0 ];
      then
        print_info "Done."
      else
        print_error "Can't move OTRS configuration directory to ${OTRS_CONFIG_DIR}" && exit 1
    fi
  else
    print_info "Found existing configuration directory, Ok."
  fi
  rm -rf ${OTRS_CONFIG_MOUNT_DIR}
}

function reinstall_modules () {
  print_info "Reinstalling OTRS modules..."
  su -c "$OTRS_ROOT/bin/otrs.Console.pl Admin::Package::ReinstallAll > /dev/null 2>&1> /dev/null 2>&1" -s /bin/bash otrs

  if [ $? -gt 0 ]; then
    print_error "Could not reinstall OTRS modules, try to do it manually with the Package Manager at the admin section."
  else
    print_info "Done."
  fi
}

function disable_phone_home_features() {
      sed -i -e '/Task###OTRSBusinessEntitlementCheck/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###OTRSBusinessAvailabilityCheck"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###SupportDataCollectAsynchronous"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###RegistrationUpdateSend"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
}

function enable_phone_home_features() {
      sed -i -e '/Task###OTRSBusinessEntitlementCheck/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###OTRSBusinessAvailabilityCheck"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###SupportDataCollectAsynchronous"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
      sed -i -e '/Task###RegistrationUpdateSend"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
}