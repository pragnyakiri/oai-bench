# oai-bench

This repository is for creating a new profile in Powder platform.

Free5gc docker - CN (node 1)
OAI RAN - X310 (node 2)
OAI UE - X310 (node 3)

# Start CN:
cd /var/tmp/free5gc-compose/

sudo docker-compose up -d

sudo docker logs -f amf

# Start gnodeb:

Edit gnb conf file with IP address of docker amf

vim /var/tmp/etc/oai/gnb.sa.band78.fr1.106PRB.usrpx310.conf

sudo /var/tmp/oairan/cmake_targets/ran_build/build/nr-softmodem -E   -O /var/tmp/etc/oai/gnb.sa.band78.fr1.106PRB.usrpx310.conf --sa

# Start UE

Add UE details in free5gc console

Then run UE:

sudo /var/tmp/oairan/cmake_targets/ran_build/build/nr-uesoftmodem -E   -O /var/tmp/etc/oai/ue.conf   -r 106   -C 3619200000   --usrp-args "clock_source=external,type=x300"   --band 78   --numerology 1   --ue-txgain 0   --ue-rxgain 104   --nokrnmod   --dlsch-parallel 4   --sa

After the UE associates, open another session and add the following route. Also check the UE IP address.

# add route
sudo route add -net 192.168.70.0/24 dev oaitun_ue1

# check UE IP address
ifconfig oaitun_ue1

You should now be able to generate traffic in either direction:

# from UE to CN traffic gen node (in session on ue node)
ping -I oaitun_ue1 192.168.70.135

# from CN traffic generation service to UE (in session on cn node)
sudo docker exec -it oai-ext-dn ping <UE IP address>
