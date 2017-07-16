#!/bin/bash
# upgrade_otrs.sh

if [ $# -ne 2 ]; then
  echo "Usage: upgrade_otrs.sh version source_checksum" && exit 64
fi

OTRS_VERSION=$1
OTRS_SOURCE_CHECKSUM=$2

# retrieve OTRS source
cd /tmp
wget http://ftp.otrs.org/pub/otrs/otrs-${OTRS_VERSION}.tar.gz
echo "${OTRS_SOURCE_CHECKSUM}  otrs-${OTRS_VERSION}.tar.gz" | md5sum -s -c
if [ $? ]; then
  echo "OTRS source checksum is valid"
else
  echo "OTRS source checksum is invalid"
  exit 1
fi

# stop services
echo "Shutting down OTRS..."
supervisorctl stop all
echo "Cron.sh - start/stop OTRS cronjobs"
echo "Copyright (C) 2001-2017 OTRS AG, http://otrs.com/"
crontab -d -u otrs
echo "done"
su -c "/opt/otrs/bin/otrs.Daemon.pl stop" -s /bin/bash otrs
echo "OTRS stopped!"

# create backup of unique files
tmpdir=$(mktemp -d)
cp ${OTRS_ROOT}Kernel/Config.pm $tmpdir/
cp ${OTRS_ROOT}Kernel/Config/Files/ZZZAuto.pm $tmpdir/
cp ${OTRS_ROOT}var/log/TicketCounter.log $tmpdir/
mkdir -p $tmpdir/cron
find ${OTRS_ROOT}var/cron -maxdepth 1 -type f -not -name "*.dist" -exec mv {} $tmpdir/cron/ \;
mkdir -p $tmpdir/stats
cp *.installed $tmpdir/stats/ 2>/dev/null

# remove files
cd ${OTRS_ROOT}
find -maxdepth 1 -type f -exec rm -f {} \;
find -maxdepth 1 -type d -not -name Kernel -not -name "." -not -name "var" -exec rm -r {} \;
rm -rf ${OTRS_ROOT}Kernel/*
cd var
find -maxdepth 1 -type f -exec rm -f {} \;
find -maxdepth 1 -type d -not -name article -not -name "." -exec rm -r {} \;

# extract new version
tar -xzf /tmp/otrs-${OTRS_VERSION}.tar.gz -C ${OTRS_ROOT} --strip-components=1
rm -f /tmp/otrs-${OTRS_VERSION}.tar.gz

# move back saved files
mv $tmpdir/Config.pm ${OTRS_ROOT}Kernel/
mv $tmpdir/ZZZAuto.pm ${OTRS_ROOT}Kernel/Config/Files/
mv $tmpdir/TicketCounter.log ${OTRS_ROOT}var/log/
mv $tmpdir/cron/* ${OTRS_ROOT}var/cron/
mv $tmpdir/stats/* ${OTRS_ROOT}var/stats/ 2>/dev/null
rm -rf $tmpdir

# fix PostmasterFollowUpState config var, this line on Ticket.xml disallow the edition of that field through SysConfig
sed -i -e '/<ValidateModule>Kernel::System::SysConfig::StateValidate<\/ValidateModule>/ s/^#*/#/' -i ${OTRS_ROOT}Kernel/Config/Files/Ticket.xml

if [ "$OTRS_DISABLE_PHONE_HOME" == "yes" ]; then
  sed -i -e '/Task###OTRSBusinessEntitlementCheck/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###OTRSBusinessAvailabilityCheck"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###SupportDataCollectAsynchronous"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###RegistrationUpdateSend"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\10\20\30\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
else
  sed -i -e '/Task###OTRSBusinessEntitlementCheck/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###OTRSBusinessAvailabilityCheck"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###SupportDataCollectAsynchronous"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
  sed -i -e '/Task###RegistrationUpdateSend"/ s/\(.*Required="\).\(" Valid="\).\(" ReadOnly="\).\(".*\)/\11\21\31\4/' -i ${OTRS_ROOT}Kernel/Config/Files/Daemon.xml
fi

# fix permissions
${OTRS_ROOT}bin/otrs.SetPermissions.pl --otrs-user=otrs --web-group=www-data ${OTRS_ROOT}

# delete cache and rebuild configuration cache
su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Cache::Delete" -s /bin/bash otrs
su -c "${OTRS_ROOT}bin/otrs.Console.pl Maint::Config::Rebuild" -s /bin/bash otrs

echo "Upgrade complete!"
echo
echo "You must now run the following command to restart the container for the changes to take effect:"
echo -e "  \e[33mdocker restart otrs\e[0m"
echo
