FROM node:10-alpine as node
FROM ruby:2.6-alpine3.9

ARG VERSION=v2.7.1
ARG REPOSITORY=tootsuite/mastodon
ARG LIBICONV_VERSION=1.15

ENV UID=991 GID=991 \
    RUN_DB_MIGRATIONS=true \
    SIDEKIQ_WORKERS=5 \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_ENV=production \
    NODE_ENV=production \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mastodon/bin

WORKDIR /mastodon

# Copy node from node:10-alpine
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY --from=node /opt/yarn-* /opt/yarn
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn \
 && ln -s /opt/yarn/bin/yarnpkg /usr/local/bin/yarnpkg

# Install dependencies
RUN apk -U upgrade \
 && apk add \
    ca-certificates \
    ffmpeg \
    file \
    git \
    icu-libs \
    imagemagick \
    libidn \
    libpq \
    libxml2 \
    libxslt \
    libressl \
    protobuf \
    s6 \
    su-exec \
    tzdata \

# Install build dependencies
 && apk add -t build-dependencies \
    build-base \
    icu-dev \
    libidn-dev \
    openssl \
    libtool \
    libxml2-dev \
    libxslt-dev \
    postgresql-dev \
    protobuf-dev \
    python \
    tar \

# Update CA certificates
 && update-ca-certificates \

# Install GNU Libiconv
 && wget http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz -O /tmp/libiconv-${LIBICONV_VERSION}.tar.gz \
 && mkdir /tmp/src && tar xzf /tmp/libiconv-${LIBICONV_VERSION}.tar.gz -C /tmp/src \
 && cd /tmp/src/libiconv-${LIBICONV_VERSION} \
 && ./configure --prefix=/usr/local \
 && make -j$(getconf _NPROCESSORS_ONLN) && make install && libtool --finish /usr/local/lib \

# Install Mastodon
 && cd /mastodon \
 && wget -qO- https://github.com/${REPOSITORY}/archive/${VERSION}.tar.gz | tar xz --strip 1 \
 && bundle config build.nokogiri --use-system-libraries --with-iconv-lib=/usr/local/lib --with-iconv-include=/usr/local/include \
 && bundle install -j$(getconf _NPROCESSORS_ONLN) --deployment --clean --no-cache --without test development \
 && yarn --ignore-optional --pure-lockfile \

# Precompile Mastodon assets
 && SECRET_KEY_BASE=$(bundle exec rake secret) OTP_SECRET=$(bundle exec rake secret) SMTP_FROM_ADDRESS= bundle exec rake assets:precompile \

# Clean
 && npm -g --force cache clean && yarn cache clean \
 && apk del build-dependencies \
 && rm -rf /var/cache/apk/* /tmp/src

COPY rootfs /

RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

VOLUME /mastodon/public/system /mastodon/log

EXPOSE 3000 4000

LABEL maintainer="Wonderfall <wonderfall@targaryen.house>" \
      description="Your self-hosted, globally interconnected microblogging community"

ENTRYPOINT ["/usr/local/bin/run"]
CMD ["/bin/s6-svscan", "/etc/s6.d"]
