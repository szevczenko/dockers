#!/bin/bash
set -e

# This script generates certificates for mutual TLS authentication:
# - Separate Client CA and Server CA
# - Client certificate signed by Client CA (with common CN)
# - Server certificate signed by Server CA

echo "========================================="
echo "Generating Mutual TLS Certificates"
echo "========================================="

# Passwords
CLIENT_CA_PASSWORD=$(openssl rand -hex 32)
SERVER_CA_PASSWORD=$(openssl rand -hex 32)

# Algorithm (EC prime256v1 or secp384r1)
EC_ALGORITHM=prime256v1

# Server Domain Configuration
SERVER_DOMAIN=${SERVER_DOMAIN:-"update-hqc.duckdns.org"}
export SERVER_DNS_NAMES="DNS:${SERVER_DOMAIN}"

# Client Configuration (common CN for all devices)
CLIENT_CN=${CLIENT_CN:-"test-hqc-device"}

# Configuration files
CLIENT_CA_CONFIG="client_ca.cnf"
SERVER_CA_CONFIG="server_ca.cnf"
SERVER_EXT_CONFIG="server_ext.cnf"

# Output directories
CLIENT_DIR="out/client"
SERVER_DIR="out/server"

# Clean and prepare directories
rm -rf out
mkdir -p $CLIENT_DIR $SERVER_DIR
mkdir -p client_ca/private client_ca/certs client_ca/newcerts
mkdir -p server_ca/private server_ca/certs server_ca/newcerts

# Initialize CA database files
touch client_ca/index.txt
echo 1000 > client_ca/serial
touch server_ca/index.txt
echo 1000 > server_ca/serial

echo ""
echo "Step 1: Generate Client CA"
echo "-------------------------------------------"

# Generate Client CA private key
openssl ecparam -name $EC_ALGORITHM -genkey -noout -out client_ca/private/client_ca.key
openssl ec -in client_ca/private/client_ca.key -passout pass:$CLIENT_CA_PASSWORD -aes256 -out client_ca/private/client_ca.key

# Generate Client CA certificate
openssl req -new -x509 -days 3650 -sha256 \
    -config $CLIENT_CA_CONFIG \
    -key client_ca/private/client_ca.key \
    -passin pass:$CLIENT_CA_PASSWORD \
    -out client_ca/certs/client_ca.crt \
    -subj "/C=PL/ST=Krakow/O=HQC/CN=HQC Client CA"

echo "✓ Client CA generated"

echo ""
echo "Step 2: Generate Server CA"
echo "-------------------------------------------"

# Generate Server CA private key
openssl ecparam -name $EC_ALGORITHM -genkey -noout -out server_ca/private/server_ca.key
openssl ec -in server_ca/private/server_ca.key -passout pass:$SERVER_CA_PASSWORD -aes256 -out server_ca/private/server_ca.key

# Generate Server CA certificate
openssl req -new -x509 -days 3650 -sha256 \
    -config $SERVER_CA_CONFIG \
    -key server_ca/private/server_ca.key \
    -passin pass:$SERVER_CA_PASSWORD \
    -out server_ca/certs/server_ca.crt \
    -subj "/C=PL/ST=Krakow/O=HQC/CN=HQC Server CA"

echo "✓ Server CA generated"

echo ""
echo "Step 3: Generate Client Certificate"
echo "-------------------------------------------"

echo "  Generating certificate with CN: $CLIENT_CN"

# Generate client private key (no password for client key)
openssl ecparam -name $EC_ALGORITHM -genkey -noout -out "$CLIENT_DIR/client.key"

# Generate client CSR
openssl req -new -sha256 \
    -config $CLIENT_CA_CONFIG \
    -key "$CLIENT_DIR/client.key" \
    -out "$CLIENT_DIR/client.csr" \
    -subj "/C=PL/ST=Krakow/O=HQC/CN=$CLIENT_CN"

# Sign client certificate with Client CA using openssl ca command
openssl ca -batch -config $CLIENT_CA_CONFIG \
    -extensions client_cert \
    -days 3650 \
    -notext \
    -md sha256 \
    -passin pass:$CLIENT_CA_PASSWORD \
    -in "$CLIENT_DIR/client.csr" \
    -out "$CLIENT_DIR/client.crt"

# Copy server CA for client to verify server
cp server_ca/certs/server_ca.crt "$CLIENT_DIR/server_ca.crt"

# Clean up CSR
rm -f "$CLIENT_DIR/client.csr"

echo "✓ Client certificate generated with CN=$CLIENT_CN"

echo ""
echo "Step 4: Generate Server Certificate"
echo "-------------------------------------------"

# Generate server private key (no password)
openssl ecparam -name $EC_ALGORITHM -genkey -noout -out $SERVER_DIR/server.key

# Generate server CSR with SAN
openssl req -new -sha256 \
    -config $SERVER_CA_CONFIG \
    -key $SERVER_DIR/server.key \
    -out $SERVER_DIR/server.csr \
    -subj "/C=PL/ST=Krakow/O=HQC/CN=$SERVER_DOMAIN"

# Sign server certificate with Server CA using openssl ca command
openssl ca -batch -config $SERVER_CA_CONFIG \
    -extensions server_cert \
    -extfile $SERVER_EXT_CONFIG \
    -days 3650 \
    -notext \
    -md sha256 \
    -passin pass:$SERVER_CA_PASSWORD \
    -in $SERVER_DIR/server.csr \
    -out $SERVER_DIR/server.crt

# Copy client CA for server to verify clients
cp client_ca/certs/client_ca.crt $SERVER_DIR/client_ca.crt

# Clean up
rm -f $SERVER_DIR/server.csr

echo "✓ Server certificate generated for $SERVER_DOMAIN"

echo ""
echo "Step 5: Verification"
echo "-------------------------------------------"

# Verify certificates
echo "Verifying Client CA..."
openssl x509 -in client_ca/certs/client_ca.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before|Not After)"

echo ""
echo "Verifying Server CA..."
openssl x509 -in server_ca/certs/server_ca.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before|Not After)"

echo ""
echo "Verifying Client Certificate..."
openssl verify -CAfile client_ca/certs/client_ca.crt $CLIENT_DIR/client.crt
openssl x509 -in $CLIENT_DIR/client.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before|Not After)"

echo ""
echo "Verifying Server Certificate..."
openssl verify -CAfile server_ca/certs/server_ca.crt $SERVER_DIR/server.crt
openssl x509 -in $SERVER_DIR/server.crt -noout -text | grep -E "(Subject:|Issuer:|Not Before|Not After)"

echo ""
echo "Get Client Certificate Issuer Hash (for HawkBit configuration):"
CLIENT_ISSUER_HASH=$(openssl x509 -in $CLIENT_DIR/client.crt -issuer_hash -noout)
echo "  Issuer Hash: $CLIENT_ISSUER_HASH"

echo ""
echo "========================================="
echo "Certificate Generation Complete!"
echo "========================================="
echo ""
echo "Generated files:"
echo ""
echo "CLIENT files (deploy to all devices):"
echo "  - $CLIENT_DIR/client.crt       (client certificate, CN=$CLIENT_CN)"
echo "  - $CLIENT_DIR/client.key       (client private key)"
echo "  - $CLIENT_DIR/server_ca.crt    (server CA to verify nginx)"
echo ""
echo "SERVER/NGINX files (deploy to reverse proxy):"
echo "  - $SERVER_DIR/server.crt       (server certificate for nginx)"
echo "  - $SERVER_DIR/server.key       (server private key for nginx)"
echo "  - $SERVER_DIR/client_ca.crt    (client CA to verify devices)"
echo ""
echo "HawkBit Configuration:"
echo "  - Enable 'Certificate Authentication by Reverse Proxy'"
echo "  - Set issuer hash to: $CLIENT_ISSUER_HASH"
echo "  - Or use fixed value 'Hawkbit' (as per documentation)"
echo ""
echo "IMPORTANT: All devices will use the same certificate with CN=$CLIENT_CN"
echo "  This means device identification in HawkBit will NOT be based on CN."
echo "  You'll need to use other methods (like target tokens) to identify devices."
echo ""
echo "Test with curl:"
echo "  curl -L -v --cert $CLIENT_DIR/client.crt --key $CLIENT_DIR/client.key \\"
echo "       --cacert $CLIENT_DIR/server_ca.crt \\"
echo "       https://$SERVER_DOMAIN/default/controller/v1/<device-id>"
echo ""
echo "Passwords (save securely):"
echo "  Client CA Password: $CLIENT_CA_PASSWORD"
echo "  Server CA Password: $SERVER_CA_PASSWORD"
echo ""
echo "To use a different common name:"
echo "  CLIENT_CN=\"your-common-name\" ./generate_mtls_certs.sh"
echo ""
