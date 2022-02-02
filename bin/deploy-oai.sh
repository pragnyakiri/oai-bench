set -ex
COMMIT_HASH=$1
NODE_ROLE=$2
ETCDIR=/local/repository/etc
SRCDIR=/var/tmp
CFGDIR=/local/repository/etc
OAI_RAN_MIRROR="https://gitlab.flux.utah.edu/powder-mirror/openairinterface5g"
OAI_CN5G_REPO="https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed"
CN5G_REPO="https://github.com/pragnyakiri/free5gc-compose"
SRS_REPO="https://github.com/srsran/srsRAN"

if [ -f $SRCDIR/oai-setup-complete ]; then
    echo "setup already ran; not running again"
    if [ $NODE_ROLE == "cn" ]; then
        sudo sysctl net.ipv4.conf.all.forwarding=1
        sudo iptables -P FORWARD ACCEPT
    elif [ $NODE_ROLE == "nodeb" ]; then
        LANIF=`ip r | awk '/192\.168\.1\.2/{print $3}'`
        if [ ! -z $LANIF ]; then
          echo LAN IFACE is $LANIF...
          echo adding route to CN
          sudo ip route add 192.168.70.128/26 via 192.168.1.1 dev $LANIF
        fi
    fi
    exit 0
fi

function setup_cn_node {
    # Install docker, docker compose, wireshark/tshark
    echo setting up cn node
    sudo apt-get update && sudo apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    echo "adding docker gpg key"
    until curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    do
        echo "."
        sleep 2
    done

    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo add-apt-repository -y ppa:wireshark-dev/stable
    echo "wireshark-common wireshark-common/install-setuid boolean false" | sudo debconf-set-selections

    sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        wireshark \
        tshark

    sudo systemctl enable docker
    echo "sudo usermod -aG docker $USER"
    #sudo usermod -aG docker $USER

    echo "installing compose"
    until sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    do
        echo "."
        sleep 2
    done
    
    sudo chmod +x /usr/local/bin/docker-compose

    #Install gtp5g for upf to work
    cd $SRCDIR
    git clone https://github.com/PrinzOwO/gtp5g.git gtp5g
    cd gtp5g
    make
    sudo make install

    echo creating demo-oai bridge network...
    sudo docker network create \
      --driver=bridge \
      --subnet=192.168.70.128/26 \
      -o "com.docker.network.bridge.name"="demo-oai" \
      demo-oai-public-net
    echo creating demo-oai bridge network... done.

    sudo sysctl net.ipv4.conf.all.forwarding=1
    sudo iptables -P FORWARD ACCEPT

    echo cloning and syncing free5gc-compose...
    cd $SRCDIR
    git clone $CN5G_REPO free5gc-compose
    cd free5gc-compose
    git checkout $COMMIT_HASH
    echo cloning and syncing free5gc-compose... done.
    sudo make base
    sudo docker-compose build
    echo setting up cn node... done.

}

function setup_ran_node {
    echo cloning and building oai ran...
    cd $SRCDIR
    git clone $OAI_RAN_MIRROR oairan
    cd oairan
    git checkout $COMMIT_HASH

    if [ $COMMIT_HASH == "efc696cce989d7434604cacc1a77790f5fdda70c" ]; then
      git apply /local/repository/etc/oai/gnb_drb_and_ue_stall.patch
    fi

    source oaienv
    cd cmake_targets
    ./build_oai -I
    ./build_oai -w USRP --build-lib all $BUILD_ARGS
    echo cloning and building oai ran... done.
}

function configure_nodeb {
    echo configuring nodeb...
    mkdir -p $SRCDIR/etc/oai
    cp -r $ETCDIR/oai/* $SRCDIR/etc/oai/
    LANIF=`ip r | awk '/192\.168\.1\.2/{print $3}'`
    if [ ! -z $LANIF ]; then
      echo LAN IFACE is $LANIF.. updating nodeb config
      find $SRCDIR/etc/oai/ -type f -exec sed -i "s/LANIF/$LANIF/" {} \;
      echo adding route to CN
      sudo ip route add 192.168.70.128/26 via 192.168.1.1 dev $LANIF
    else
      echo No LAN IFACE.. not updating nodeb config
    fi
    echo configuring nodeb... done.
}

function configure_ue {
    echo configuring ue...
    mkdir -p $SRCDIR/etc/oai
    cp -r $ETCDIR/oai/* $SRCDIR/etc/oai/
    echo configuring ue... done.
}

if [ $NODE_ROLE == "cn" ]; then
    setup_cn_node
elif [ $NODE_ROLE == "nodeb" ]; then
    BUILD_ARGS="--gNB"
    setup_ran_node
    configure_nodeb
elif [ $NODE_ROLE == "ue" ]; then
    BUILD_ARGS="--nrUE"
    setup_ran_node
    configure_ue
fi

touch $SRCDIR/oai-setup-complete