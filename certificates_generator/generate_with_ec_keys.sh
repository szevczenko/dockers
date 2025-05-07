#!/bin/bash
set -e

# Passwords for CA key Server Key and Keystore
CA_KEY_PASSWORD=$(openssl rand -hex 32)
SERVER_KEY_PASSWORD=$(openssl rand -hex 32)
KEYSTORE_PASSWORD=$(openssl rand -hex 32)

# CA Certificate Configuration
CA_CONFIG=openssl.cnf
CA_PRIVATE_KEY=ca/private/ca_key.pem
CA_CERTIFICATE=ca/certs/ca_cert.pem
CA_SUBJECT="/CN=HQC_ROOT_CA/ST=Krakow/C=PL"
CA_EC_KEY_ALGORITHM=prime256v1

# Server Certificate Configuration
SERVER_CONFIG=openssl.cnf
SERVER_PRIVATE_KEY=server/private/server.key.pem
SERVER_CERTIFICATE=server/certs/server.cert.pem
SERVER_REQUEST=server/certs/server.csr.pem
SERVER_SUBJECT="/CN=HQC_SERVER/ST=Krakow/C=PL"
SERVER_CHAIN=server/certs/ca-chain.cert.pem
SERVER_EC_KEY_ALGORITHM=prime256v1

SERVER_DNS_NAMES="DNS:test.hawkbit.com,DNS:hawkbit.com"
export SERVER_DNS_NAMES=$SERVER_DNS_NAMES

# Prepare directories
mkdir -p ca/certs ca/crl ca/newcerts ca/private
mkdir -p server/certs server/crl server/newcerts server/private
mkdir -p out
rm -f ca/index.txt ca/index.txt.attr server/index.txt server/index.txt.attr
touch ca/index.txt ca/index.txt.attr server/index.txt server/index.txt.attr
echo 1000 > ca/serial
echo 1000 > server/serial


# Generate CA Key
OPENSSL_CONF=$CA_CONFIG; openssl ecparam -name $CA_EC_KEY_ALGORITHM -genkey -noout -out $CA_PRIVATE_KEY
OPENSSL_CONF=$CA_CONFIG; openssl ec -in $CA_PRIVATE_KEY -passout pass:$CA_KEY_PASSWORD -aes256 -out $CA_PRIVATE_KEY

# Generate CA certificate
openssl req -config $CA_CONFIG \
      -key $CA_PRIVATE_KEY \
      -passin pass:$CA_KEY_PASSWORD \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out $CA_CERTIFICATE \
      -subj $CA_SUBJECT

# Generate Server Key
OPENSSL_CONF=$SERVER_CONFIG; openssl ecparam -name $SERVER_EC_KEY_ALGORITHM -genkey -noout -out $SERVER_PRIVATE_KEY
# OPENSSL_CONF=$SERVER_CONFIG; openssl ec -in $SERVER_PRIVATE_KEY -passout pass:$SERVER_KEY_PASSWORD -aes256 -out $SERVER_PRIVATE_KEY


# Generate Request For Server Key
openssl req -config $SERVER_CONFIG -new -sha256 \
        -key $SERVER_PRIVATE_KEY \
        -out $SERVER_REQUEST \
        -subj $SERVER_SUBJECT \
        -extensions server_cert

#-passin pass:$SERVER_KEY_PASSWORD

# Sign with CA certificate Client Certificate we use CA config
echo generateing $SERVER_CERTIFICATE
openssl ca -config $CA_CONFIG -extensions server_cert \
      -days 7300 \
      -passin pass:$CA_KEY_PASSWORD \
      -in $SERVER_REQUEST \
      -out $SERVER_CERTIFICATE

# Create chain of certificates
cat $SERVER_CERTIFICATE \
      $CA_CERTIFICATE > $SERVER_CHAIN

# Verify so far
openssl verify -CAfile $CA_CERTIFICATE $CA_CERTIFICATE
openssl verify -CAfile $CA_CERTIFICATE $SERVER_CERTIFICATE
openssl verify -CAfile $CA_CERTIFICATE $SERVER_CHAIN

# Coppy files to output
# rm -f out/*
echo DONE

cp $CA_CERTIFICATE out/CA_Certificate.pem
cp $SERVER_CERTIFICATE out/server.pem
cp $SERVER_PRIVATE_KEY out/server_key.pem
