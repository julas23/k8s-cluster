#!/bin/bash

set -e

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
RANCHER_HOSTNAME=${RANCHER_HOSTNAME:-"rancher.home.lan"}
METALLB_IP=${METALLB_IP:-"10.0.0.10"}
RANCHER_PASSWORD=${RANCHER_PASSWORD:-"admin"}
TIMEOUT=${TIMEOUT:-300}

# Funções
print_usage() {
    echo "Uso: $0 [--certmanager|--metallb|--rancher|--all]"
    echo "  --certmanager : Instala apenas o Cert Manager"
    echo "  --metallb     : Instala apenas o MetalLB"
    echo "  --rancher     : Instala apenas o Rancher"
    echo "  --all         : Instala todos os componentes (padrão)"
    echo "  --help        : Mostra esta ajuda"
    echo ""
    echo "Variáveis de ambiente:"
    echo "  RANCHER_HOSTNAME  : Hostname do Rancher (padrão: rancher.home.lan)"
    echo "  METALLB_IP        : IP do MetalLB (padrão: 10.0.0.10)"
    echo "  RANCHER_PASSWORD  : Senha admin do Rancher (padrão: admin)"
    echo "  TIMEOUT           : Timeout em segundos (padrão: 300)"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Adicionar esta função ao script
check_status() {
    log "=== STATUS DA INSTALAÇÃO ==="
    
    info "### Cert Manager ###"
    kubectl get pods -n cert-manager 2>/dev/null || warn "Cert Manager não instalado"
    echo ""
    kubectl get svc -n cert-manager 2>/dev/null || warn "Cert Manager não instalado"
    echo ""
    
    info "### MetalLB ###"
    kubectl get pods -n metallb-system 2>/dev/null || warn "MetalLB não instalado"
    echo ""
    kubectl get svc -n metallb-system 2>/dev/null || warn "MetalLB não instalado"
    echo ""
    kubectl get ipaddresspools -n metallb-system 2>/dev/null || warn "MetalLB não configurado"
    echo ""
    kubectl get l2advertisements -n metallb-system 2>/dev/null || warn "MetalLB não configurado"
    echo ""
    
    info "### Rancher ###"
    kubectl get pods -n cattle-system 2>/dev/null || warn "Rancher não instalado"
    echo ""
    kubectl get svc -n cattle-system 2>/dev/null || warn "Rancher não instalado"
    echo ""
    kubectl get ingress -n cattle-system 2>/dev/null || warn "Ingress do Rancher não configurado"
    echo ""
    
    info "### LoadBalancer Services ###"
    kubectl get svc --all-namespaces --field-selector type=LoadBalancer || warn "Nenhum serviço LoadBalancer encontrado"
    echo ""
    
    info "### Verificação de DNS ###"
    if command -v nslookup &>/dev/null; then
        nslookup rancher.home.lan || warn "DNS não resolvido"
    else
        warn "nslookup não disponível para verificar DNS"
    fi
    echo ""
    
    info "### Verificação de Conectividade ###"
    local lb_ip=$(kubectl get svc -n cattle-system rancher -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -n "$lb_ip" ]; then
        info "Testando conectividade com $lb_ip..."
        if command -v nc &>/dev/null; then
            nc -zv $lb_ip 443 && info "Porta 443 acessível" || warn "Porta 443 inacessível"
            nc -zv $lb_ip 80 && info "Porta 80 acessível" || warn "Porta 80 inacessível"
        else
            warn "netcat não disponível para teste de conectividade"
        fi
    else
        warn "Nenhum IP de LoadBalancer encontrado"
    fi
    echo ""
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-}
    local condition=${4:-"Ready"}
    local timeout=${5:-$TIMEOUT}
    
    log "Aguardando $resource_type/$resource_name ficar $condition (timeout: ${timeout}s)"
    
    local cmd
    if [ -z "$namespace" ]; then
        cmd="kubectl get $resource_type $resource_name"
    else
        cmd="kubectl get $resource_type $resource_name -n $namespace"
    fi
    
    local count=0
    local interval=5
    
    while [ $count -lt $timeout ]; do
        if eval "$cmd" 2>/dev/null | grep -q "$condition"; then
            log "$resource_type/$resource_name está $condition"
            return 0
        fi
        sleep $interval
        count=$((count + interval))
    done
    
    warn "Timeout aguardando $resource_type/$resource_name ficar $condition"
    return 1
}

wait_for_pods() {
    local namespace=$1
    local selector=${2:-}
    local timeout=${3:-$TIMEOUT}
    
    log "Aguardando pods no namespace $namespace ficarem Ready"
    
    local count=0
    local interval=5
    
    while [ $count -lt $timeout ]; do
        local pods
        if [ -z "$selector" ]; then
            pods=$(kubectl get pods -n $namespace --field-selector=status.phase=Running --no-headers 2>/dev/null || true)
        else
            pods=$(kubectl get pods -n $namespace -l $selector --field-selector=status.phase=Running --no-headers 2>/dev/null || true)
        fi
        
        if [ -n "$pods" ] && ! echo "$pods" | grep -q "0/"; then
            log "Todos os pods em $namespace estão Ready"
            return 0
        fi
        
        sleep $interval
        count=$((count + interval))
    done
    
    warn "Timeout aguardando pods em $namespace"
    return 1
}

install_certmanager() {
    log "Instalando Cert Manager..."
    
    # Adicionar repositório
    helm repo add jetstack https://charts.jetstack.io --force-update 2>/dev/null || true
    helm repo update
    
    # Criar namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Instalar Cert Manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set installCRDs=true \
        --set webhook.timeoutSeconds=30 \
        --wait \
        --timeout ${TIMEOUT}s
    
    # Aguardar pods
    wait_for_pods "cert-manager"
    
    log "Cert Manager instalado com sucesso"
}

install_metallb() {
    log "Instalando MetalLB..."
    
    # Aplicar manifestos
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
    
    # Aguardar pods
    wait_for_pods "metallb-system"
    
    # Configurar IP pool
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: rancher-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_IP}-${METALLB_IP}
EOF

    # Configurar L2Advertisement
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: rancher-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - rancher-pool
EOF

    log "MetalLB instalado com sucesso"
}

install_rancher() {
    log "Instalando Rancher..."
    
    # Adicionar repositório
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update 2>/dev/null || true
    helm repo update
    
    # Criar namespace
    kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Instalar Rancher
    helm upgrade --install rancher rancher-latest/rancher \
        --namespace cattle-system \
        --set hostname=${RANCHER_HOSTNAME} \
        --set replicas=1 \
        --set bootstrapPassword=${RANCHER_PASSWORD} \
        --set ingress.extraAnnotations."kubernetes\.io/ingress\.class"=traefik \
        --wait \
        --timeout ${TIMEOUT}s
    
    # Aguardar pods
    wait_for_pods "cattle-system"
    
    # Configurar serviço como LoadBalancer
    kubectl patch svc rancher -n cattle-system -p '{"spec":{"type":"LoadBalancer"}}'
    
    log "Rancher instalado com sucesso"
    info "Acesse: https://${RANCHER_HOSTNAME}"
    info "Usuário: admin"
    info "Senha: ${RANCHER_PASSWORD}"
}

install_all() {
    log "Instalando todos os componentes..."
    install_certmanager
    install_metallb
    install_rancher
    log "Instalação completa concluída"
}

# Main execution
main() {
    local mode="all"
    
    case "${1:-}" in
        --certmanager)
            mode="certmanager"
            ;;
        --metallb)
            mode="metallb"
            ;;
        --rancher)
            mode="rancher"
            ;;
        --all|"")
            mode="all"
            ;;
        --check|"")
            mode="check"
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            error "Parâmetro inválido: $1"
            print_usage
            exit 1
            ;;
    esac
    
    info "Iniciando instalação no modo: $mode"
    info "Hostname: ${RANCHER_HOSTNAME}"
    info "MetalLB IP: ${METALLB_IP}"
    
    case "$mode" in
        certmanager)
            install_certmanager
            ;;
        metallb)
            install_metallb
            ;;
        rancher)
            install_rancher
            ;;
        check)
            check_status
            ;;
        all)
            install_all
            ;;
    esac
    
    log "Verificando estado final..."
    kubectl get namespaces
    kubectl get pods --all-namespaces --field-selector=status.phase=Running
    
    log "Instalação concluída!"
}

# Executar main com parâmetros
main "$@"