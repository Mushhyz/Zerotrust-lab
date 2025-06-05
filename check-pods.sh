#!/bin/bash

echo "🔍 Checking pod status across all namespaces..."

# Get all non-running pods
NON_RUNNING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)

if [ -z "$NON_RUNNING_PODS" ]; then
    echo "✅ All pods are running!"
    exit 0
fi

echo "⚠️ Found non-running pods:"
echo "$NON_RUNNING_PODS"

echo ""
echo "📋 Detailed status for problematic pods:"

# Get pods in specific problematic states
kubectl get pods --all-namespaces --field-selector=status.phase!=Running -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" 2>/dev/null || true

echo ""
echo "🔍 Recent events for problematic pods:"

# Check events for each non-running pod
while IFS= read -r line; do
    if [ -n "$line" ]; then
        NAMESPACE=$(echo "$line" | awk '{print $1}')
        POD_NAME=$(echo "$line" | awk '{print $2}')
        
        echo "--- Events for $POD_NAME in $NAMESPACE ---"
        kubectl describe pod "$POD_NAME" -n "$NAMESPACE" | grep -A5 "Events:" | tail -5 || echo "No recent events"
        echo ""
    fi
done <<< "$NON_RUNNING_PODS"

# Check specific critical services
echo "🎯 Checking critical services status:"
CRITICAL_SERVICES=("opa/gatekeeper-controller-manager" "monitoring/prometheus-server" "monitoring/grafana" "auth/keycloak" "gitea/gitea")

for service in "${CRITICAL_SERVICES[@]}"; do
    NAMESPACE=$(echo "$service" | cut -d'/' -f1)
    DEPLOYMENT=$(echo "$service" | cut -d'/' -f2)
    
    STATUS=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" --no-headers 2>/dev/null || echo "NOT_FOUND")
    if [ "$STATUS" != "NOT_FOUND" ]; then
        echo "  - $service: $STATUS"
    else
        echo "  - $service: NOT DEPLOYED"
    fi
done

echo ""
echo "💡 To get more details, run:"
echo "  kubectl describe pod <pod-name> -n <namespace>"
echo "  kubectl logs <pod-name> -n <namespace>"
