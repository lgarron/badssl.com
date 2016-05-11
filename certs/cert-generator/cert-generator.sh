#!/usr/bin/env bash

# Defense is the best offense
set -eu
cd "$(dirname ${0})"

# Certificate date calculations
d2016=1483055999 # the last second of Dec. 30, 2016 in UTC: $(( $(date -ud '12/30/2016' +%s) - 1 ))
dnow=$(date +%s)
du2016=$(( (d2016-dnow)/(3600*24) ))
du2017=$((du2016+365))

# Create the self-signed directory, since jekyll doesn't clone empty directories
if [[ ! -d ../self-signed ]]; then
  mkdir ../self-signed
fi

# Ask to regenerate keys if not invoked from make keys
if [[ $# -gt 0 ]]; then
  regen=${1}
else
  read -p "Regenerate the root and intermediate keys? Recommended for first installs. [y/N] " -n 1 regen
  echo
fi

# Ensure the directory exists, otherwise we can't populate certificates.
mkdir -p ../self-signed

if [[ $regen =~ ^[Yy]$ ]]; then
  echo "Generating BadSSL.com Root Certificate Authority"
  openssl req -new -x509 -days 7300 \
    -config badssl-root.conf \
    -out ../self-signed/badssl-root.pem
  echo

  echo "Generating BadSSL.com Intermediate Certificate Authority CSR"
  openssl req -new \
    -out badssl-intermediate.csr \
    -config badssl-intermediate.conf
  echo

  echo "Signing BadSSL.com Intermediate Certificate Authority"
  openssl x509 -req -CAcreateserial -days 3650 -sha256 \
    -in badssl-intermediate.csr \
    -CA ../self-signed/badssl-root.pem \
    -CAkey ../self-signed/badssl-root.key \
    -extfile badssl-intermediate.conf \
    -extensions req_v3_ca \
    -out ../self-signed/badssl-intermediate.pem
  rm badssl-intermediate.csr
  echo

  echo "Generating BadSSL.com Private Key"
  openssl genrsa -out ../self-signed/badssl.com.key 2048

  # If you're regenerating keys, then the "expired" cert won't work anymore
  rm -f ../self-signed/wildcard.expired.pem
fi

echo "Generating BadSSL Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out badssl-wildcard.csr \
  -config badssl-wildcard.conf
echo

echo "Generating BadSSL Fallback Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out badssl-fallback.csr \
  -config badssl-fallback.conf
echo

echo "Signing BadSSL Default Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.normal.pem
echo

echo "Generating incomplete certificate chain"
cp out.pem ../self-signed/wildcard.incomplete-chain.pem
rm out.pem
echo

echo "Signing BadSSL Invalid Signature Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
echo "Running the certificate invalidator to break the signature on the certificate"
./cert-signature-invalidator.py out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.invalid-signature.pem
echo

echo "Signing BadSSL SHA-1 Certificate, expiring 2016"
openssl x509 -req -days $du2016 -sha1 -CAcreateserial \
  -in badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.sha1-2016.pem
rm out.pem
echo

echo "Signing BadSSL SHA-1 Certificate, expiring 2017"
openssl x509 -req -days $du2017 -sha1 -CAcreateserial \
  -in badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.sha1-2017.pem
rm out.pem
echo

# Too lazy to setup the loathsome mess that is openssl ca when I could just wait a day
if [ ! -f ../self-signed/wildcard.expired.pem ]
  then
    echo "Signing BadSSL SHA-256 Certificate, expiring tomorrow"
    openssl x509 -req -days 1 -sha256 -CAcreateserial \
      -in badssl-wildcard.csr \
      -CA ../self-signed/badssl-intermediate.pem \
      -CAkey ../self-signed/badssl-intermediate.key \
      -extfile badssl-wildcard.conf \
      -extensions req_v3_usr \
      -out out.pem
    cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.expired.pem
    rm out.pem
    echo
  else
    echo -e "Not regenerating expiring certificate: delete ../self-signed/wildcard.expired.pem to regenerate\n"
fi

echo "Self-signing BadSSL SHA-256 Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-wildcard.csr \
  -signkey ../self-signed/badssl.com.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cp out.pem ../self-signed/wildcard.self-signed.pem
rm out.pem
echo

echo "Self-signing BadSSL Fallback Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-fallback.csr \
  -signkey "../self-signed/badssl.com.key" \
  -extfile badssl-fallback.conf \
  -extensions req_v3_usr \
  -out out.pem
cp out.pem ../self-signed/wildcard.fallback.pem
rm out.pem
echo

# The RSA-512 and RSA-1024 certs require us to do the whole song and dance all over again
echo "Generating BadSSL.com RSA-512 Private Key"
openssl genrsa -out ../self-signed/rsa512.badssl.com.key 512
echo

echo "Generating BadSSL RSA-512 Certificate Signing Request"
openssl req -new \
  -key ../self-signed/rsa512.badssl.com.key \
  -out rsa512.badssl-wildcard.csr \
  -config badssl-wildcard.conf
echo

echo "Signing BadSSL RSA-512 Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in rsa512.badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.rsa512.pem
rm out.pem

echo "Generating BadSSL.com RSA-1024 Private Key"
openssl genrsa -out ../self-signed/rsa1024.badssl.com.key 1024
echo

echo "Generating BadSSL RSA-1024 Certificate Signing Request"
openssl req -new \
  -key ../self-signed/rsa1024.badssl.com.key \
  -out rsa1024.badssl-wildcard.csr \
  -config badssl-wildcard.conf
echo

echo "Signing BadSSL RSA-1024 Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in rsa1024.badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/wildcard.rsa1024.pem
rm out.pem
echo

# Generate the RSA-8192 keys and certs
echo "Generating BadSSL.com RSA-8192 Private Key"
openssl genrsa -out ../self-signed/rsa8192.badssl.com.key 8192
echo

echo "Generating BadSSL RSA-8192 Certificate Signing Request"
openssl req -new \
  -key ../self-signed/rsa8192.badssl.com.key \
  -out rsa8192.badssl-wildcard.csr \
  -config badssl-wildcard.conf
echo

echo "Signing BadSSL RSA-8192 Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in rsa8192.badssl-wildcard.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-wildcard.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/rsa8192.badssl.com.pem
rm out.pem
echo

echo "Generating BadSSL.com 1000-sANs Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out badssl-1000-sans.csr \
  -config badssl-1000-sans.conf

echo "Signing BadSSL.com 1000-sANs Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-1000-sans.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-1000-sans.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/1000-sans.badssl.com.pem
rm out.pem
echo

echo "Generating BadSSL.com 10000-sANs Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out badssl-10000-sans.csr \
  -config badssl-10000-sans.conf

echo "Signing BadSSL.com 10000-sANs Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in badssl-10000-sans.csr \
  -CA ../self-signed/badssl-intermediate.pem \
  -CAkey ../self-signed/badssl-intermediate.key \
  -extfile badssl-10000-sans.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem ../self-signed/badssl-intermediate.pem ../self-signed/badssl-root.pem > ../self-signed/10000-sans.badssl.com.pem
rm out.pem
echo

# Generate Superfish cert
echo "Generating Superfish Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out superfish.csr \
  -config badssl-superfish.conf
echo

echo "Signing Superfish Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in superfish.csr \
  -CA ../foreign/superfish.crt \
  -CAkey ../foreign/superfish.key \
  -extfile badssl-superfish.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem > ../self-signed/superfish.pem
rm out.pem
echo

# Generate eDellRoot cert
echo "Generating eDellRoot Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out edellroot.csr \
  -config badssl-edellroot.conf
echo

echo "Signing eDellRoot Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in edellroot.csr \
  -CA ../foreign/eDellRoot.crt \
  -CAkey ../foreign/eDellRoot.key \
  -extfile badssl-edellroot.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem > ../self-signed/edellroot.pem
rm out.pem
echo

# Generate DSDTestProvider cert
echo "Generating DSDTestProvider Certificate Signing Request"
openssl req -new \
  -key ../self-signed/badssl.com.key \
  -out dsdtestprovider.csr \
  -config badssl-dsdtestprovider.conf
echo

echo "Signing DSDTestProvider Certificate"
openssl x509 -req -days 730 -sha256 -CAcreateserial \
  -in dsdtestprovider.csr \
  -CA ../foreign/DSDTestProvider.crt \
  -CAkey ../foreign/DSDTestProvider.key \
  -extfile badssl-dsdtestprovider.conf \
  -extensions req_v3_usr \
  -out out.pem
cat out.pem > ../self-signed/dsdtestprovider.pem
rm out.pem
echo

# Generate the Diffie-Hellman primes
if [[ $regen =~ ^[Yy]$ ]]; then
  openssl dhparam -out ../self-signed/dh480.pem 480
  openssl dhparam -out ../self-signed/dh512.pem 512
  openssl dhparam -out ../self-signed/dh1024.pem 1024
  openssl dhparam -out ../self-signed/dh2048.pem 2048
fi

# Clean up after ourselves
rm *.csr
