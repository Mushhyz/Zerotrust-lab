#!/bin/bash

set -e

echo "🔑 Initialisation du realm Keycloak Zero Trust..."

export KC_REALM="zero-trust"
export KEYCLOAK_URL="http://keycloak.localhost"

# Attendre que Keycloak soit disponible
echo "⏳ Attente de la disponibilité de Keycloak..."
timeout 300 bash -c 'until curl -s -f -o /dev/null $KEYCLOAK_URL; do sleep 5; done'

# Configuration des credentials
kcadm.sh config credentials --server $KEYCLOAK_URL --realm master --user admin --password admin123

# Création du realm
echo "🌐 Création du realm $KC_REALM..."
kcadm.sh create realms -s realm=$KC_REALM -s enabled=true

# Création de l'utilisateur admin
echo "👤 Création de l'utilisateur admin..."
kcadm.sh create users -r $KC_REALM -s username=admin -s enabled=true
kcadm.sh set-password -r $KC_REALM --username admin --new-password admin123

# Création des clients OIDC
echo "🔐 Création des clients OIDC..."
for client in grafana vault gitea; do
  echo "  - Création du client $client..."
  kcadm.sh create clients -r $KC_REALM \
    -s clientId=$client \
    -s enabled=true \
    -s publicClient=false \
    -s directAccessGrantsEnabled=true \
    -s standardFlowEnabled=true \
    -s "redirectUris=[\"http://$client.localhost/*\"]" \
    -s "webOrigins=[\"http://$client.localhost\"]"
done

echo "✅ Configuration Keycloak terminée!"
echo "🔗 Realm: $KEYCLOAK_URL/realms/$KC_REALM"
