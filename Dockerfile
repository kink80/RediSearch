FROM redislabsmodules/rmbuilder:latest as builder
MAINTAINER Slavek Tecl <slavomir.tecl@gmail.com>

# Build the source
ADD ./src /src
WORKDIR /src
RUN set -ex;\
    deps="$DEPS";\
    make all -j 4; \
    make test;

# Package the runner
FROM redis:latest
ENV LIBDIR /usr/lib/redis/modules
WORKDIR /data
RUN set -ex;\
    mkdir -p "$LIBDIR";
COPY --from=builder /src/redisearch.so  "$LIBDIR"

# This is the release of Consul to pull in.
ENV CONSUL_VERSION=1.0.3

# This is the location of the releases.
ENV HASHICORP_RELEASES=https://releases.hashicorp.com

# Create a consul user and group first so the IDs get set the same way, even as
# the rest of this may change over time.
RUN addgroup consul && \
    adduser --system --group consul


# Set up certificates, base tools, and Consul.
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg libpcap-dev openssl wget unzip iproute2 && \
    gpg --keyserver pgp.mit.edu --recv-keys 91A6E7F85D05C65630BEF18951852D87348FFC4C && \
    mkdir -p /tmp/build && \
    cd /tmp/build && \
    wget ${HASHICORP_RELEASES}/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip && \
    wget ${HASHICORP_RELEASES}/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS && \
    wget ${HASHICORP_RELEASES}/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_SHA256SUMS.sig && \
    gpg --batch --verify consul_${CONSUL_VERSION}_SHA256SUMS.sig consul_${CONSUL_VERSION}_SHA256SUMS && \
    grep consul_${CONSUL_VERSION}_linux_amd64.zip consul_${CONSUL_VERSION}_SHA256SUMS | sha256sum -c && \
    unzip -d /bin consul_${CONSUL_VERSION}_linux_amd64.zip && \
    cd /tmp && \
    rm -rf /tmp/build && \
    rm -rf /root/.gnupg

# The /consul/data dir is used by Consul to store state. The agent will be started
# with /consul/config as the configuration directory so you can add additional
# config files in that location.
RUN mkdir -p /consul/data && \
    mkdir -p /consul/config && \
    chown -R consul:consul /consul

# Expose the consul data directory as a volume since there's mutable state in there.
VOLUME /consul/data

# Server RPC is used for communication between Consul clients and servers for internal
# request forwarding.
EXPOSE 8300

# Serf LAN and WAN (WAN is used only by Consul servers) are used for gossip between
# Consul agents. LAN is within the datacenter and WAN is between just the Consul
# servers in all datacenters.
EXPOSE 8301 8301/udp 8302 8302/udp

# HTTP and DNS (both TCP and UDP) are the primary interfaces that applications
# use to interact with Consul.
EXPOSE 8500 8600 8600/udp

# Consul doesn't need root privileges so we run it as the consul user from the
# entry point script. The entry point script also uses dumb-init as the top-level
# process to reap any zombie processes created by Consul sub-processes.
COPY ./setup/docker-trap.sh /usr/local/bin/docker-trap.sh
COPY ./setup/redis-check.sh /usr/local/bin/redis-check.sh
COPY ./setup/consul-redis.json /consul/config

RUN chown -R consul:consul /consul

ENTRYPOINT ["/usr/local/bin/docker-trap.sh"]
