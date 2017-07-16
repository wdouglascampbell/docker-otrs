#!/bin/bash
# Startup script for OTRS container.
#
# Starts up an OTRS container based on the setting of the FIRSTRUN_ACTION
# environment variable.  Note that the first run actions only occur the first
# time a container is run after being created.  All subsequent runs of the
# container will just start the container in the same state/configuration in
# which it was stopped.
#
# FIRSTRUN_ACTION possible values:
#    - "none" *DEFAULT*
#      No configuration options will be changed.
#    - "freshinstall"
#      Re-installs the OTRS database and Kernel directory files with a clean
#      configuration.  In addition any optional settings set in the
#      otrs-setup.env file will also be configured.
#    - "restore"
#      Restores an OTRS backup.  Files to restore from are indicated by the
#      value of OTRS_BACKUP_DATE in the otrs-setup.env file.  The value will
#      indicate the directory containing the backup files from the path
#      ${OTRS_ROOT}/backups.
#    - "updateconfig"
#      Updates OTRS with any of the configuration options set in otrs-setup.env
#

### Handle `docker stop` for graceful shutdown
function gracefulShutdown {
    print_info "Shutting down OTRS..."
    supervisorctl stop all
    rm -f /run/supervisord.sock
    echo "Cron.sh - start/stop OTRS cronjobs"
    echo "Copyright (C) 2001-2017 OTRS AG, http://otrs.com/"
    crontab -d -u otrs
    echo "done"
    su -c "/opt/otrs/bin/otrs.Daemon.pl stop" -s /bin/bash otrs
    print_info "OTRS stopped!"
    echo "======================================================================"
    exit 0
}

trap gracefulShutdown SIGTERM
####

. ./functions.sh

#Wait for database to come up
wait_for_db

# check for first time run
if [ -e "${OTRS_ROOT}var/tmp/firsttime" ]; then

  [ -z "${FIRSTRUN_ACTION}" ] && FIRSTRUN_ACTION=none
  [ -z "${OTRS_DATABASE}" ] && OTRS_DATABASE=otrs
  [ -z "${OTRS_DB_USER}" ] && OTRS_DB_USER=otrs
  [ -z "${OTRS_DB_PASSWORD}" ] && OTRS_DB_PASSWORD=$(random_string)$(random_string) && print_info "Generated MySQL password for \`${OTRS_DB_USER}\` user is: \e[92m${OTRS_DB_PASSWORD}\e[0m"
  [ -z "${OTRS_POSTMASTER_FETCH_TIME}" ] && OTRS_POSTMASTER_FETCH_TIME=0

  # check if requesting a fresh installation
  if [ "$FIRSTRUN_ACTION" == "freshinstall" ]; then

    # Clear Kernel directory
    print_info "Clearing OTRS Kernel directory..."
    rm -rf ${OTRS_CONFIG_DIR}/*

    # Clear Article directory
    print_info "Clearing OTRS Article directory..."
    rm -rf ${OTRS_ROOT}var/article/*

    # Clear Database Information
    print_info "Clearing OTRS database information..."
    $mysqlcmd -e "DROP DATABASE ${OTRS_DATABASE}; DELETE FROM mysql.db WHERE Db='${OTRS_DATABASE}'; DELETE FROM mysql.user WHERE User='${OTRS_DB_USER}';"

    # Load fresh install
    print_info "Starting a fresh \e[92mOTRS ${OTRS_VERSION}\e[0m installation."

    # Check if a host-mounted volume for configuration storage was added to this container
    check_host_mount_dir

    create_db

    print_info "Loading default db schema..."
    $mysqlcmd ${OTRS_DATABASE} < ${OTRS_ROOT}scripts/database/otrs-schema.mysql.sql
    [ $? -gt 0 ] && print_error "\n\e[1;31mERROR:\e[0m Couldn't load OTRS database schema !!\n" && exit 1

    print_info "Loading initial db inserts..."
    $mysqlcmd ${OTRS_DATABASE} < ${OTRS_ROOT}scripts/database/otrs-initial_insert.mysql.sql
    [ $? -gt 0 ] && print_error "\n\e[1;31mERROR:\e[0m Couldn't load OTRS database initial inserts !!\n" && exit 1

    update_database_settings

  elif [ "$FIRSTRUN_ACTION" == "restore" ];then

    print_info "Restoring OTRS backup: \e[92m$OTRS_BACKUP_DATE\e[0m"
    restore_backup $OTRS_BACKUP_DATE

  elif [ "$FIRSTRUN_ACTION" == "updateconfig" ]; then

    check_host_mount_dir

  else

    FIRSTRUN_ACTION="none"

    # remove /Kernel directory
    rm -rf ${OTRS_CONFIG_MOUNT_DIR}

  fi

  # Remove first time run flag
  rm -rf ${OTRS_ROOT}var/tmp/firsttime

  if [ "$FIRSTRUN_ACTION" != "none" ]; then

    reinstall_modules

    update_otrs_settings
    set_ticket_counter
    set_default_language
    set_fetch_email_time

    cd ${OTRS_ROOT}var/cron
    shopt -s nullglob
    for foo in *.dist; do cp $foo `basename $foo .dist`; done
    shopt -u nullglob

    if [ "$OTRS_DISABLE_PHONE_HOME" == "yes" ]; then
      disable_phone_home_features;
    else
      enable_phone_home_features;
    fi

    ${OTRS_ROOT}bin/otrs.SetPermissions.pl --otrs-user=otrs --web-group=www-data ${OTRS_ROOT}
    su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Config::Rebuild" -s /bin/bash otrs
    su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Cache::Delete" -s /bin/bash otrs

    if [ "${FIRSTRUN_ACTION}" != "restore" ]; then
      #Set default admin user password
      print_info "Setting password for default admin account \e[92mroot@localhost\e[0m"
      [ -z "${OTRS_ROOT_PASSWORD}" ] && OTRS_ROOT_PASSWORD=$(random_string)$(random_string) && print_info "A password has been generated for the default admin account root@localhost.  The password is: \e[92m${OTRS_ROOT_PASSWORD}\e[0m"
      su -c "${OTRS_ROOT}bin/otrs.Console.pl Admin::User::SetPassword root@localhost $OTRS_ROOT_PASSWORD" -s /bin/bash otrs
    fi

    # update apache configuration with hostname and server admin email
    [ ! -z $OTRS_ADMIN_EMAIL ] && sed -i -e "s/ServerAdmin.*/ServerAdmin ${OTRS_ADMIN_EMAIL}/" /etc/apache2/conf.d/zzz_otrs.conf
    [ ! -z $OTRS_HOSTNAME ] && sed -i -e "s/ServerName.*/ServerName ${OTRS_HOSTNAME}/" /etc/apache2/conf.d/zzz_otrs.conf

  fi

fi

#Launch supervisord
print_info "Starting supervisord..."
cd /run
supervisord -c /etc/supervisord.conf &

print_info "Starting OTRS CRON..."
${OTRS_ROOT}bin/Cron.sh start otrs

print_info "Starting OTRS daemon..."
su -c "${OTRS_ROOT}bin/otrs.Daemon.pl start" -s /bin/bash otrs

if [ -n "${OTRS_HOSTNAME}" ]; then
  print_info "OTRS now available at http://${OTRS_HOSTNAME}"
else
  print_info "OTRS now available at http://localhost"
fi

exec sleep 2147483647 &
wait