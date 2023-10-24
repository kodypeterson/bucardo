# Use postgres:15.3 image as base
FROM postgres:15.3

# Environment variables for Postgres
ENV POSTGRES_USER postgres
ENV POSTGRES_PASSWORD postgres
ENV POSTGRES_DB postgres

# Update and Install needed software
RUN apt-get update \
    && apt-get install -y perl make postgresql-plperl-15 libdbix-safe-perl libboolean-perl libjson-perl git cpanminus libpq-dev build-essential jq curl net-tools netcat-traditional iputils-ping vim locales python3

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# Copy the installation script
COPY install-modules.sh /tmp/install-modules.sh

# Run the installation script
RUN /bin/bash /tmp/install-modules.sh

# Clone bucardo repo
RUN git clone https://github.com/bucardo/bucardo.git

# Change owner of the bucardo directory to postgres
RUN chown -R postgres:postgres /bucardo

WORKDIR /bucardo

RUN mkdir -p /var/log/bucardo /var/run/bucardo && chown -R postgres:postgres /var/log/bucardo /var/run/bucardo

# Build and install Bucardo
RUN perl Makefile.PL \
    && make \
    && make install \
    && chown -R postgres:postgres /usr/local/bin/bucardo /var/log/bucardo /var/run/bucardo

# Create /media directory if it doesn't exist
RUN mkdir -p /media && chown -R postgres:postgres /media

# Expose Postgres port
EXPOSE 5432

# Switch to the postgres user
USER postgres

# create file owned by postgres to allow execution 'bucardo restart sync' as postgres user
RUN touch bucardo.restart.reason.txt

# Copy the bucardo install script
COPY  install-bucardo.sh /docker-entrypoint-initdb.d/

# Copy bucardo.json script
COPY apply-bucardo-config.sh /usr/local/bin/

COPY docker-start-up.sh /usr/local/bin/

# Add metadata to an image
LABEL maintainer="rafalszymonduda@outlook.com"

# Remove not needed
CMD apt-get remove build-essential libpq-dev && \
    apt-get autoremove -yqq -purge && \
    apt-get clean

ENV LANG="en_US.UTF-8" 
ENV LC_ALL="en_US.UTF-8" 
ENV LC_CTYPE="en_US.UTF-8"

# Override PostgreSQL entrypoint
ENTRYPOINT ["/bin/bash"]

CMD ["docker-start-up.sh"]