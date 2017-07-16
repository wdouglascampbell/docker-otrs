# docker-otrs
# OTRS 5 Ticketing System
This repository contains the Dockerfiles and other files needed to build, run and maintain an OTRS container in Docker.  I started by forking the repo of Juan Luis Baptiste at https://github.com/juanluisbaptiste/docker-otrs and making changes that fit more to my preferences.

#### Requirements:
  * MariaDB/MySQL server
  * Postfix server
  * Docker volumes for storing data:  otrs-Kernel, otrs-backup, otrs-article

## How to Use
There are four options that define how the container will run when initially started.  They are: none, freshinstall,restore and updateconfig.  These options are set using the FIRSTRUN_ACTION variable in otrs-setup.env.  If no actionhas been specified, the default action will be "none".

"none" indicates that the container will attempt to run using existing configuration files and database.  This would bea good choice to use once you have your container setup and running but want to make sure you don't accidently overwriteyour data in the situation that you need to re-create the container at some later point in time.

"freshinstall" indicates that a fresh "out-of-the-box" installation will be performed wiping any previous OTRS files anddatabase.  Any optional settings configured in otrs-setup.env will also be set.

"restore" indicates that OTRS will be restored from an existing backup.  The backup to be restored is indicated by thevalue of OTRS_BACKUP_DATE in the otrs-setup.env file.  The value will indicate the directory containing the backup filesin the path ${OTRS_ROOT}/backups.  Any optional settings configured in otrs-setup.env will also be set.

"updateconfig" indicates that any optional settings configured in otrs-setup.env will be set during the initial run ofthe container.

otrs-setup.env provides for configuring optional settings to customize OTRS:
  * OTRS_HOSTNAME  Sets the container's hostname
  * OTRS_SYSTEM_ID  Sets the system's ticketing ID.
  * OTRS_ADMIN_EMAIL  Sets the admin user email.
  * OTRS_ORGANIZATION  Sets the organization name (ex: MyCompany Ltd.)
  * OTRS_DATABASE  database name.  If it's not set the default of 'otrs' will be used.
  * OTRS_DB_USER  otrs user database username.  If it's not set the default of 'otrs" will be used.
  * OTRS_DB_PASSWORD  otrs user database password. If it's not set the password will be randomly generated (recommended).
  * OTRS_ROOT_PASSWORD  root@localhost user password. If it's not set the password will be randomly generated.
  * OTRS_POSTMASTER_FETCH_TIME  Sets the time interval that OTRS should fetch emails from the configured postmaster accounts.This value is 10 minutes by default. Email fetching can be disabled altogether by setting this variable to 0.
  * OTRS_LANGUAGE  Set the default language for both agent and customer interfaces (For example, "es" for spanish).
  * OTRS_TICKET_COUNTER  Sets the starting point for the ticket counter.
  * OTRS_NUMBER_GENERATOR  Sets the ticket number generator, possible values are : DateChecksum, Date, AutoIncrement or Random.
  * OTRS_DISABLE_PHONE_HOME  Setting to "yes" will cause OTRS business related features to not contact external services

Once you have fulfilled the requirements and configured the otrs-setup.env file build the image and create the otrs container using Docker Compose.
```bash
docker-compose build; docker-compose create
```

You may then start the containe with
docker start otrs
Check the logs to see what is happening during container startup.
docker logs -f otrs
The OTRS system can be reached at the following addresses:
Administration Interfacehttp://$OTRS_HOSTNAME
Customer Interfacehttp://$OTRS_HOSTNAME/customer.pl
Backups
Create a full backup by running the following from the Docker host system.
docker exec -it otrs /otrs_backup.sh
This will create a new directory using the current date and time under inside the container at /var/otrs/backups and store thefiles for the full backup.  Assuming you have used the distributed docker-compose.yml file and have mounted that directory asa host volume then you will have access to the backups files from the docker host server.
Upgrades
After a new version of OTRS is release you can upgrade to the latest release using the following command from the Docker host system.
docker exec -it otrs /upgrade_otrs.sh version source_checksum
where version is the latest version and checksum is the md5 checksum shown on the OTRS download page (https://www.otrs.com/download-open-source-help-desk-software-otrs-free/) for the gzip'd source files.
