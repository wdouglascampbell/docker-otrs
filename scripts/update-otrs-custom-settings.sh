#!/bin/sh

[ -n "${OTRS_HOSTNAME}" ] && /otrs-update-setting.pl "FQDN" string-mod-item -value "${OTRS_HOSTNAME}"
[ -n "${OTRS_HOSTNAME}" ] && /otrs-update-setting.pl "PostMaster::PreFilterModule::NewTicketReject::Sender" string-mod-item -value "noreply@${OTRS_HOSTNAME}"
[ -n "${OTRS_ADMIN_EMAIL}" ] && /otrs-update-setting.pl "AdminEmail" string-mod-item -value "${OTRS_ADMIN_EMAIL}"
[ -n "${OTRS_ORGANIZATION}" ] && /otrs-update-setting.pl "Organization" string-mod-item -value "${OTRS_ORGANIZATION}"
[ -n "${OTRS_ORGANIZATION}" ] && /otrs-update-setting.pl "CustomerHeadline" string-mod-item -value "${OTRS_ORGANIZATION}"
[ -n "${OTRS_SYSTEM_ID}" ] && /otrs-update-setting.pl "SystemID" string-mod-item -value "${OTRS_SYSTEM_ID}"

# NOTE: Other OTRS settings can be customized here as well by using the otrs-update-setting.pl Perl script and just hard coding the
#       parameters.

print_info "Updating send mail options in configuration file..."
/otrs-update-setting.pl "SendmailModule" option-mod-item -value "Kernel::System::Email::SMTP"
/otrs-update-setting.pl "SendmailModule::Host" string-mod-item -value "postfix"
/otrs-update-setting.pl "SendmailModule::Port" string-mod-item -value "25"
