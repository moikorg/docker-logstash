# Pull base image
#FROM hypriot/rpi-java:1.8.0
FROM openjdk:latest

MAINTAINER Michael Mäder <mike@moik.org>

# add raspbian jessie repository for some packages
#RUN echo "deb http://mirrordirector.raspbian.org/raspbian/ jessie main contrib non-free rpi" > /etc/apt/sources.list.d/raspbian-jessie.list

# install plugin dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        libzmq3 \
    && rm -rf /var/lib/apt/lists/* 

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
  && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
  && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
  && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc" \
  && export GNUPGHOME="$(mktemp -d)" \
  && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
  && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
  && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
  && chmod +x /usr/local/bin/gosu \
  && gosu nobody true

# the "ffi-rzmq-core" gem is very picky about where it looks for libzmq.so
RUN mkdir -p /usr/local/lib \
    && ln -s /usr/lib/*/libzmq.so.3 /usr/local/lib/libzmq.so


# add our user and group first to make sure their IDs get assigned consistently
RUN groupadd -r logstash && useradd -r -m -g logstash logstash

# install logstash
ENV LOGSTASH_VERSION 5.0.1
RUN set -x \
    && cd /opt \
    && wget "https://artifacts.elastic.co/downloads/logstash/logstash-$LOGSTASH_VERSION.tar.gz" \
    && tar -xzf logstash-$LOGSTASH_VERSION.tar.gz \
    && rm logstash-$LOGSTASH_VERSION.tar.gz \
    && ln -s logstash-$LOGSTASH_VERSION logstash \
    && chown -R logstash:logstash logstash

# Workaround for bug https://github.com/jruby/jruby/issues/1561
ENV JFFI_VERSION jffi-1.2.12
RUN set -x \
    && apt-get update \
    && apt-get install -y build-essential ant \
    && cd /tmp \
    && wget https://github.com/jnr/jffi/archive/$JFFI_VERSION.tar.gz \
    && tar -xvzf $JFFI_VERSION.tar.gz \
    && cd jffi-$JFFI_VERSION/ \
    && ant jar \
    && cp build/jni/libjffi-1.2.so /opt/logstash/vendor/jruby/lib/jni/arm-Linux/ \
    && cd /tmp \
    && rm -rf jffi-$JFFI_VERSION

ENV PATH /opt/logstash/bin:$PATH

# necessary for 5.0+ (overriden via "--path.settings", ignored by < 5.0)
ENV LS_SETTINGS_DIR /etc/logstash

# comment out some troublesome configuration parameters
#   path.log: logs should go to stdout
#   path.config: No config files found: /etc/logstash/conf.d/*
RUN set -ex \
    && if [ -f "$LS_SETTINGS_DIR/logstash.yml" ]; then \
        sed -ri 's!^(path.log|path.config):!#&!g' "$LS_SETTINGS_DIR/logstash.yml"; \
    fi; \

# if the "log4j2.properties" file exists (logstash 5.x), let's empty it out so we get the default: "logging only errors to the console"
    if [ -f "$LS_SETTINGS_DIR/log4j2.properties" ]; then \
        cp "$LS_SETTINGS_DIR/log4j2.properties" "$LS_SETTINGS_DIR/log4j2.properties.dist"; \
        truncate --size=0 "$LS_SETTINGS_DIR/log4j2.properties"; \
    fi

COPY docker-entrypoint.sh /
RUN set -ex \
	&& chmod +x /docker-entrypoint.sh \
	&& chmod 777 /opt/logstash/data 

COPY config/ /etc/logstash
EXPOSE 5044

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["-e", ""]

