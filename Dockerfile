FROM bitwalker/alpine-elixir:1.7.0

ENV TERM=xterm

RUN apk --no-cache add \
      git make g++ &&\
    rm -rf /var/cache/apk/*

RUN apk add --update libffi-dev ruby-dev
RUN apk update && apk upgrade && apk --update add \
    libstdc++ tzdata bash ca-certificates \
    &&  echo 'gem: --no-document' > /etc/gemrc

RUN addgroup docker -g 1000 && \
adduser docker -u 1000 -s /bin/ash -SDG docker && \
apk add --update sudo openssh && \
echo "docker ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

ENV USER docker
ENV APP phoenix_pubsub_nats
ENV HOME=/home/$USER

USER $USER
WORKDIR $HOME/$APP

RUN mix local.hex --force && \
    mix local.rebar --force

ENV SHELL=/bin/sh

CMD mix test
