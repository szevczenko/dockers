#!/bin/bash
set -e

# Passwords for CA key Server Key and Keystore
CA_KEY_PASSWORD=$(openssl rand -hex 32)
SERVER_KEY_PASSWORD=$(openssl rand -hex 32)
KEYSTORE_PASSWORD=$(openssl rand -hex 32)

# CA Certificate Configuration
CA_CONFIG=ca/openssl_ca.cnf
CA_PRIVATE_KEY=ca/private/ca_key.pem
CA_CERTIFICATE=ca/certs/ca_cert.pem
CA_SUBJECT="/CN=HQC_ROOT_CA/ST=Krakow/C=PL"
CA_EC_KEY_ALGORITHM=prime256v1

# Server Certificate Configuration
SERVER_CONFIG=server/openssl.cnf
SERVER_PRIVATE_KEY=server/private/server.key.pem
SERVER_CERTIFICATE=server/certs/server.cert.pem
SERVER_REQUEST=server/certs/server.csr.pem
SERVER_SUBJECT="/CN=HQC_SERVER/ST=Krakow/C=PL"
SERVER_CHAIN=server/certs/ca-chain.cert.pem
SERVER_EC_KEY_ALGORITHM=prime256v1

# Java Keystore Settings
KEYSTORE=java_endcertificate/keystore.p12
KEYSTORE_MAIN_DOMAIN=plkrasap0035
KEYSTORE_CSR=java_endcertificate/certs/tomcat.csr
KEYSTORE_CERTIFICATE=java_endcertificate/certs/tomcat.pem
KEYSTORE_BUNDLE=java_endcertificate/certs/bundle.pem

SERVER_DNS_NAMES="DNS:plkrasap0035.ad.global,DNS:plkrasap0035.vlan.int,DNS:plkrasap0035"
export SERVER_DNS_NAMES=$SERVER_DNS_NAMES

# Prepare directories
mkdir -p ca/certs ca/crl ca/newcerts ca/private
mkdir -p server/certs server/crl server/newcerts server/private
mkdir -p java_endcertificate java_endcertificate/certs
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
        -subj $SERVER_SUBJECT

#-passin pass:$SERVER_KEY_PASSWORD

# Sign with CA certificate Client Certificate we use CA config
echo generateing $SERVER_CERTIFICATE
openssl ca -config $CA_CONFIG -extensions v3_server_ca \
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

# Now we generate Java Keystore
# rm -f $KEYSTORE
# echo adding extensions
# keytool -genkeypair -noprompt -alias tomcat -storetype PKCS12 -keyalg RSA -sigalg SHA256withRSA \
#         -keysize 4096  -keystore $KEYSTORE -validity 7300 -storepass $KEYSTORE_PASSWORD \
#         -dname CN=$KEYSTORE_MAIN_DOMAIN


# Generate CSR for Keystore
# keytool -certreq -noprompt -alias tomcat -keystore $KEYSTORE -storetype PKCS12 \
#         -file $KEYSTORE_CSR -storepass $KEYSTORE_PASSWORD

# Sign CSR from Keystore wit Server key

# openssl ca -config $SERVER_CONFIG \
#       -extensions server_cert -days 7300 -notext -md sha256 \
#       -in $KEYSTORE_CSR \
#       -out $KEYSTORE_CERTIFICATE

#-passin pass:$SERVER_KEY_PASSWORD

# openssl x509 -noout -text -in $KEYSTORE_CERTIFICATE

# Create chain of certificates
# cat $KEYSTORE_CERTIFICATE \
#     $SERVER_CERTIFICATE \
#     $CA_CERTIFICATE > $KEYSTORE_BUNDLE

# Import CA cert to keystore
# keytool -import -noprompt -trustcacerts -alias CA -keystore $KEYSTORE -storetype PKCS12 -file $CA_CERTIFICATE -storepass $KEYSTORE_PASSWORD

# Import Bundle
# keytool -import -noprompt -alias tomcat -file $KEYSTORE_BUNDLE -keystore $KEYSTORE -storetype PKCS12 -storepass $KEYSTORE_PASSWORD

# Coppy files to output
# rm -f out/*
echo DONE
# cp $KEYSTORE out/keystore.p12
cp $CA_CERTIFICATE out/CA_Certificate.pem
cp $SERVER_CERTIFICATE out/server.pem
cp $SERVER_PRIVATE_KEY out/server_key.pem
