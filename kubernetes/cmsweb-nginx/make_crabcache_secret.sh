#!/bin/bash
if [ $# != 3 ]; then
    echo "make_crabcache_secret.sh <robot_key> <robot_cert> <hmac>"
    exit 1
fi
rkey=`cat $1 | base64 | awk '{ORS=""; print $0}'`
rcert=`cat $2 | base64 | awk '{ORS=""; print $0}'`
hmac=`cat $3 | base64 | awk '{ORS=""; print $0}'`
cat > crabcache-secrets.yaml << EOF
apiVersion: v1
data:
  robotcert.pem: $rcert
  robotkey.pem: $rkey
  hmac: $hmac
kind: Secret
metadata:
  name: crabcache-secrets
  namespace: default
  selfLink: /api/v1/namespaces/default/secrets/crabcache-secrets
type: Opaque
EOF
