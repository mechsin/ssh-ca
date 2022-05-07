#!/bin/bash

PASSPHRASE=""
KEYTYPE=ed25519
# KEYTYPE=ecdsa
SERVER=pizero.local
USERNAME=pi
HOSTPRIVATE=host_ca_testing
HOSTPUBLIC=$HOSTPRIVATE.pub
#HOSTPUBLIC=ssh_host_$KEYTYPE\_$SERVER\_key.pub
HOSTCERT=$(sed -r 's/(.*)\./\1-cert./' <<< $HOSTPUBLIC)
CAHOST=ca_host_key
CAUSER=ca_user_key

# Function to generate random serial numbers
# In production you need to make sure not to issue
# two certs with the same serial number but for this 
# simple example we just trust we won't have a duplicate
serialnumber () { echo $(od -A n -t u4 -N 4 /dev/urandom); }

# Generate the CA for the user keys
if [[ ! -f $CAUSER ]]
    then
	ssh-keygen -q -t $KEYTYPE -N "$PASSPHRASE" -f $CAUSER
fi

# Generate the CA for the host keys
if [[ ! -f $CAHOST ]]
    then
	ssh-keygen -q -t $KEYTYPE -N "$PASSPHRASE" -f $CAHOST
fi

# Grab the server key of the target server for the target key type
# using ssh-keyscan and use awk to push the relevant bits to a file
# ssh-keyscan -t $KEYTYPE $SERVER | awk '{print $2 " "  $3 " " $1}' > $HOSTPUBLIC 
ssh-keygen -q -t $KEYTYPE -N "$PASSPHRASE" -f $HOSTPRIVATE 

# Sign the host key
# Generate a random serial number and create a certificate name 
# that includes the server host name for easier debugging.
SERIALNUMBER=$(serialnumber)
CERTNAME="$SERVER Host Cert"
ssh-keygen -s $CAHOST -P $PASSPHRASE -h -I "$CERTNAME" -z $SERIALNUMBER $HOSTPUBLIC

# Generate the known_hosts file 
cat <(echo -n "@cert-authority * ") $CAHOST.pub > known_hosts

# Generate several types of user certificates 
# In practice these files should be generated on the users computer
# and then the public key sent to the signing server so the private 
# half of the key never leaves the safety of the users computer.
ssh-keygen -q -t $KEYTYPE -N "$PASSPHRASE"  -f id_$KEYTYPE 

# This generates a key with the user name that we want to log in as 
# in the principal list. This method does not require a principal
# file to be populated as part of the ssh server. This key 
# can only be used to login as that user name. 
CERTNAME="$USERNAME Principal User Cert"
ssh-keygen -s $CAUSER -P "$PASSPHRASE" -I "$CERTNAME" -n $USERNAME,test1 -z $(serialnumber) id_$KEYTYPE

# cp sshd_defaults sshd_config
echo "TrustedUserCAKeys /etc/ssh/$CAUSER.pub" >> sshd_config
echo "HostCertificate /etc/ssh/$HOSTCERT" >> sshd_config 
# echo "AuthorizedPrincipalsFile /etc/ssh/principals" >> sshd_config
cat sshd_defaults >> sshd_config

# This is a cool bit of code it creates a ssh connection 
# at the given location and then that connection can be 
# shared in order to avoid resubmitting credentials over and over
# again. The ssh command uses the -S option and scp used the 
# -o option with the ControlPath option.
# !! Note this connection has to be closed after your done
# using it.
ssh -fNM -S ~/.ssh/sock $USERNAME@$SERVER

TEMPFOLDER=ssh_cert_files
ssh -S ~/.ssh/sock $USERNAME@$SERVER "test -d ~/$TEMPFOLDER && (rm -rf ~/$TEMPFOLDER); mkdir ~/$TEMPFOLDER"
scp -o "ControlPath= ~/.ssh/sock" $HOSTPRIVATE $HOSTPUBLIC $HOSTCERT sshd_config $CAUSER.pub $USERNAME@$SERVER:~/$TEMPFOLDER
ssh -S ~/.ssh/sock -t $USERNAME@$SERVER "sudo cp ~/$TEMPFOLDER/* /etc/ssh;"
ssh -S ~/.ssh/sock -t $USERNAME@$SERVER "sudo systemctl restart sshd"

ssh -S ~/.ssh/sock -O exit $USERNAME@$SERVER

# cp id_* ~/.ssh
cp known_hosts ~/.ssh/known_hosts

