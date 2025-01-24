#!/bin/bash

# Passwords for CA key Intermediate Key and Keystore
CA_KEY_PASSWORD=$(openssl rand -hex 32)
INTERMEDIATE_KEY_PASSWORD=$(openssl rand -hex 32)
KEYSTORE_PASSWORD=$(openssl rand -hex 32)

# CA Certificate Configuration
CA_CONFIG=ca/openssl_ca.cnf
CA_PRIVATE_KEY=ca/private/ca_key.pem
CA_CERTIFICATE=ca/certs/ca_cert.pem
CA_SUBJECT="/CN=MBS_ROOT_CA/ST=Krakow/C=PL"

# Intermediate Certificate Configuration
INTERMEDIATE_CONFIG=intermediate/openssl.cnf
INTERMEDIATE_PRIVATE_KEY=intermediate/private/intermediate.key.pem
INTERMEDIATE_CERTIFICATE=intermediate/certs/intermediate.cert.pem
INTERMEDIATE_REQUEST=intermediate/certs/intermediate.csr.pem
INTERMEDIATE_SUBJECT="/CN=MBS_INTERMEDIATE/ST=Krakow/C=PL"
INTERMEDIATE_CHAIN=intermediate/certs/ca-chain.cert.pem

# Java Keystore Settings
KEYSTORE=java_endcertificate/keystore.p12
KEYSTORE_DOMAIN=plkrasap0035.ad.global
KEYSTORE_CSR=java_endcertificate/certs/tomcat.csr
KEYSTORE_CERTIFICATE=java_endcertificate/certs/tomcat.pem
KEYSTORE_BUNDLE=java_endcertificate/certs/bundle.pem

# Prepare directories
mkdir -p ca/certs ca/crl ca/newcerts ca/private
mkdir -p intermediate/certs intermediate/crl intermediate/newcerts intermediate/private
mkdir -p java_endcertificate java_endcertificate/certs
mkdir -p out
rm -f ca/index.txt ca/index.txt.attr intermediate/index.txt intermediate/index.txt.attr
touch ca/index.txt ca/index.txt.attr intermediate/index.txt intermediate/index.txt.attr
echo 1000 > ca/serial
echo 1000 > intermediate/serial


# Generate CA Key
OPENSSL_CONF=$CA_CONFIG; openssl genrsa -aes256 -passout pass:$CA_KEY_PASSWORD -out $CA_PRIVATE_KEY 4096

# Generate CA certificate
openssl req -config $CA_CONFIG \
      -key $CA_PRIVATE_KEY \
      -passin pass:$CA_KEY_PASSWORD \
      -new -x509 -days 7300 -sha512 -extensions v3_ca \
      -out $CA_CERTIFICATE \
      -subj $CA_SUBJECT

# Generate Intermediate Key
OPENSSL_CONF=$INTERMEDIATE_CONFIG; openssl genrsa -aes256 -passout pass:$INTERMEDIATE_KEY_PASSWORD -out $INTERMEDIATE_PRIVATE_KEY 4096

# Generate Request For Intermediate Key
openssl req -config $INTERMEDIATE_CONFIG -new -sha512 \
        -key $INTERMEDIATE_PRIVATE_KEY \
        -passin pass:$INTERMEDIATE_KEY_PASSWORD \
        -out $INTERMEDIATE_REQUEST \
        -subj $INTERMEDIATE_SUBJECT

# Sign with CA certificate Client Certificate we use CA config
echo generateing $INTERMEDIATE_CERTIFICATE
openssl ca -config $CA_CONFIG -extensions v3_intermediate_ca \
      -days 7300 \
      -passin pass:$CA_KEY_PASSWORD \
      -in $INTERMEDIATE_REQUEST \
      -out $INTERMEDIATE_CERTIFICATE

# Create chain of certificates
cat $INTERMEDIATE_CERTIFICATE \
      $CA_CERTIFICATE > $INTERMEDIATE_CHAIN

# Verify so far
openssl verify -CAfile $CA_CERTIFICATE $CA_CERTIFICATE
openssl verify -CAfile $CA_CERTIFICATE $INTERMEDIATE_CERTIFICATE
openssl verify -CAfile $CA_CERTIFICATE $INTERMEDIATE_CHAIN

# Now we generate Java Keystore
rm -f $KEYSTORE
keytool -genkeypair -alias tomcat -storetype PKCS12 -keyalg RSA -sigalg SHA256withRSA \
        -keysize 4096  -keystore $KEYSTORE -validity 7300 -storepass $KEYSTORE_PASSWORD \
        -dname CN=$KEYSTORE_DOMAIN

# Generate CSR for Keystore
keytool -certreq -alias tomcat -keystore $KEYSTORE -storetype PKCS12 \
        -file $KEYSTORE_CSR -storepass $KEYSTORE_PASSWORD

# Sign CSR from Keystore wit Intermediate key
openssl ca -config $INTERMEDIATE_CONFIG \
      -extensions server_cert -days 7300 -notext -md sha256 \
      -passin pass:$INTERMEDIATE_KEY_PASSWORD \
      -in $KEYSTORE_CSR \
      -out $KEYSTORE_CERTIFICATE

# Create chain of certificates
cat $KEYSTORE_CERTIFICATE \
    $INTERMEDIATE_CERTIFICATE \
    $CA_CERTIFICATE > $KEYSTORE_BUNDLE

# Import CA cert to keystore
keytool -import -trustcacerts -alias CA -keystore $KEYSTORE -storetype PKCS12 -file $CA_CERTIFICATE -storepass $KEYSTORE_PASSWORD

# Import Bundle
keytool -import -alias tomcat -file $KEYSTORE_BUNDLE -keystore $KEYSTORE -storetype PKCS12 -storepass $KEYSTORE_PASSWORD

# Coppy files to output
rm -f out/*
echo KEYSTORE PASSWORD:$KEYSTORE_PASSWORD
cp $KEYSTORE out/keystore.p12
cp $CA_CERTIFICATE out/CA_Certificate.pem
