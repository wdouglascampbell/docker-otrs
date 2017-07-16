#OTRS ticketing system docker image.
FROM alpine:3.5

ENV OTRS_ROOT="/opt/otrs/"

RUN apk add --no-cache \
        bash supervisor rsyslog \
        tzdata build-base dcron mysql-client \
        perl perl-dev perl-dbd-mysql \
        apache2 apache2-dev apache2-utils \
        perl-archive-zip perl-crypt-eksblowfish \
        perl-crypt-ssleay perl-date-format \
        perl-encode-hanextra perl-io-socket-ssl \
        perl-mail-imapclient perl-net-dns perl-template-toolkit \
        perl-text-csv_xs perl-xml-libxml perl-xml-libxslt \
        perl-xml-parser perl-yaml-xs perl-ldap \
        perl-text-csv ttf-dejavu && \
    perl -MCPAN -e 'my $c = "CPAN::HandleConfig"; $c->load(doit => 1, autoconfig => 1); $c->edit(prerequisites_policy => "follow"); $c->edit(build_requires_install_policy => "yes"); $c->commit' && \
    cpan JSON::XS && \
    cpan ModPerl::Util && \

    # set timezone to China time
    cp /usr/share/zoneinfo/Asia/Chongqing /etc/localtime && \

    # clean up and remove unneeded files and applications
    rm -rf /root/.cpan && \
    apk --no-cache del tzdata perl-dev apache2-dev build-base && \

    # activate Apache modules: mod_perl, mod_deflate, mod_filter, mod_headers and mod_version
    sed -i -e '/^# Dynamic Shared Object (DSO) Support/{:a;n;/^#\?LoadModule/!ba;i\LoadModule perl_module modules/mod_perl.so' -e '}' /etc/apache2/httpd.conf && \
    sed -i -e 's/^#\(LoadModule deflate_module modules\/mod_deflate.so\)/\1/' /etc/apache2/httpd.conf && \
    sed -i -e 's/^#\(LoadModule filter_module modules\/mod_filter.so\)/\1/' /etc/apache2/httpd.conf && \
    sed -i -e 's/^#\(LoadModule headers_module modules\/mod_headers.so\)/\1/' /etc/apache2/httpd.conf && \
    sed -i -e 's/^#\(LoadModule version_module modules\/mod_version.so\)/\1/' /etc/apache2/httpd.conf && \

    # add OTRS user
    mkdir -p $OTRS_ROOT && \
    adduser -D -h $OTRS_ROOT -g 'OTRS user' -G www-data otrs && \

    # create missing directories
    mkdir -p /run/apache2 && \
    mkdir -p /var/log/supervisor && \
    mkdir -p /var/otrs/backups && \

    # configure supervisord
    sed -i -e "s/^nodaemon=false/nodaemon=true/" /etc/supervisord.conf && \
    sed -i -e "/\[unix_http_server\]\|\[supervisorctl\]/a username=dummy\npassword=XvQRBUyWcUKtXJxxFZDOj1UDXdsmjKIakFolI1c2ALsb7sTbzLvqBWcUX9IfhDZ" /etc/supervisord.conf

ENV OTRS_VERSION=5.0.20 \
    OTRS_SOURCE_CHECKSUM=f07a53ffb821021cf3a2503a9f1b7575 \
    OTRS_CONFIG_DIR="${OTRS_ROOT}Kernel"

RUN apk add --no-cache tar wget && \
    wget http://ftp.otrs.org/pub/otrs/otrs-${OTRS_VERSION}.tar.gz && \
    echo "${OTRS_SOURCE_CHECKSUM}  otrs-${OTRS_VERSION}.tar.gz" | md5sum -s -c && echo "OTRS source checksum is valid" || { echo "OTRS source checksum is invalid" ; exit 1; } && \
    tar -xzf otrs-${OTRS_VERSION}.tar.gz -C ${OTRS_ROOT} --strip-components=1 && \
    apk del --no-cache tar wget && \
    rm -rf otrs-${OTRS_VERSION}* && \
    cp /opt/otrs/Kernel/Config.pm.dist /opt/otrs/Kernel/Config.pm && \
    cd /opt/otrs && \
    bin/otrs.SetPermissions.pl --web-group=www-data && \

    #Fix PostmasterFollowUpState config var, this line on Ticket.xml disallow the edition of that field through SysConfig
    sed -i -e '/<ValidateModule>Kernel::System::SysConfig::StateValidate<\/ValidateModule>/ s/^#*/#/' -i ${OTRS_ROOT}Kernel/Config/Files/Ticket.xml && \

    mkdir -p ${OTRS_ROOT}var/{run,tmp}/ && \
    touch ${OTRS_ROOT}var/tmp/firsttime && \

    #To be able to use a host-mounted volume for OTRS configuration we need to move
    #away the contents of ${OTRS_CONFIG_DIR} to another place and move them back
    #on first container run (see check_host_mount_dir on functions.sh), after the
    #host-volume is mounted.
    mv ${OTRS_CONFIG_DIR} / && \
    mkdir -p /opt/otrs/Kernel && \
    chown otrs:www-data /opt/otrs/Kernel

# Add scripts and function files
COPY scripts/*.sh /
COPY scripts/*.pl /

# Add supervisord configuration
COPY etc/supervisor.d/otrs.ini /etc/supervisor.d/otrs.ini

# Add OTRS customized configuration for Apache
COPY etc/apache2/conf.d/zzz_otrs.conf /etc/apache2/conf.d/

EXPOSE 80

CMD ["/run.sh"]
