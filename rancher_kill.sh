#!/bin/bash

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis
NAMESPACES=(
    cattle-system
    cattle-fleet-clusters-system
    cattle-fleet-local-system
    cattle-fleet-system
    cattle-global-data
    cattle-impersonation-system
    cattle-provisioning-capi-system
    cattle-ui-plugin-system
    fleet-default
    fleet-local
    local
    p-gm6hl
    p-th688
    cert-manager
    metallb-system
)

CRD_PATTERNS=(
    "cattle.io"
    "rancher"
    "fleet"
    "provisioning"
    "cert-manager"
    "metallb.io"
)

# Funções
print_usage() {
    echo "Uso: $0 [--rancher|--metallb|--certmanager|--all|--check]"
    echo "  --rancher     : Remove apenas o Rancher"
    echo "  --metallb     : Remove apenas o MetalLB"
    echo "  --certmanager : Remove apenas o Cert Manager"
    echo "  --all         : Remove todos os componentes (padrão)"
    echo "  --check       : Mostra status atual"
    echo "  --help        : Mostra esta ajuda"
}

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Função para verificar status
check_status() {
    log "=== STATUS DO CLUSTER ==="
    
    info "### Cert Manager ###"
    kubectl get pods -n cert-manager 2>/dev/null || echo "Namespace cert-manager não encontrado"
    echo ""
    kubectl get svc -n cert-manager 2>/dev/null || echo "Namespace cert-manager não encontrado"
    echo ""
    
    info "### MetalLB ###"
    kubectl get pods -n metallb-system 2>/dev/null || echo "Namespace metallb-system não encontrado"
    echo ""
    kubectl get svc -n metallb-system 2>/dev/null || echo "Namespace metallb-system não encontrado"
    echo ""
    kubectl get ipaddresspools -n metallb-system 2>/dev/null || echo "Recursos MetalLB não encontrados"
    echo ""
    kubectl get l2advertisements -n metallb-system 2>/dev/null || echo "Recursos MetalLB não encontrados"
    echo ""
    
    info "### Rancher ###"
    kubectl get pods -n cattle-system 2>/dev/null || echo "Namespace cattle-system não encontrado"
    echo ""
    kubectl get svc -n cattle-system 2>/dev/null || echo "Namespace cattle-system não encontrado"
    echo ""
    kubectl get ingress -n cattle-system 2>/dev/null || echo "Namespace cattle-system não encontrado"
    echo ""
    
    info "### Todos os Recursos Relacionados ###"
    kubectl get all --all-namespaces | grep -E -i 'metallb|cattle|cert-manager|rancher' || echo "Nenhum recurso relacionado encontrado"
    echo ""
    
    info "### CRDs ###"
    kubectl get crd | grep -E '(cattle.io|rancher|fleet|provisioning|cert-manager|metallb.io)' || echo "Nenhum CRD relacionado encontrado"
    echo ""
    
    info "### Namespaces ###"
    kubectl get namespaces | grep -E '(cattle|fleet|local|metallb|cert-manager)' || echo "Nenhum namespace relacionado encontrado"
    echo ""
    
    info "### Helm Releases ###"
    helm list --all-namespaces | grep -E '(rancher|cert-manager)' || echo "Nenhum release Helm relacionado encontrado"
}

delete_specific_svcs() {
    local namespace=$1
    shift
    local services=("$@")
    
    for svc in "${services[@]}"; do
        log "Deletando serviço $svc em $namespace"
        kubectl delete svc $svc -n $namespace --force --grace-period=0 --wait=false 2>/dev/null || true
    done
    # Exemplo de uso na clean_rancher:
    delete_specific_svcs "cattle-system" "rancher" "rancher-webhook" "imperative-api-extension"
}

# Adicionar esta função
clean_rancher_dependencies() {
    log "Limpando dependências do Rancher..."
    
    # Deletar helm releases específicas do Rancher
    helm uninstall rancher-webhook -n cattle-system --no-hooks 2>/dev/null || true
    helm uninstall rancher-provisioning-capi -n cattle-provisioning-capi-system --no-hooks 2>/dev/null || true
    
    # Namespaces adicionais que podem persistir
    local additional_namespaces=(
        cattle-fleet-system
        cattle-provisioning-capi-system
        fleet-local
        local
    )
    
    for ns in "${additional_namespaces[@]}"; do
        force_delete_namespace "$ns"
    done
    
    # Deletar CRDs específicos desses componentes
    delete_crds "provisioning\.cluster\.x-k8s\.io"
    delete_crds "fleet"
    
    log "Limpeza de dependências do Rancher concluída"
}

clean_stubborn_namespaces() {
    log "Limpando namespaces teimosos..."
    
    local stubborn_namespaces=(
        cattle-fleet-system
        cattle-provisioning-capi-system
        fleet-local
        local
    )
    
    for ns in "${stubborn_namespaces[@]}"; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            log "Limpando namespace teimoso: $ns"
            
            # Remover finalizers de todos os recursos dentro do namespace
            kubectl get all -n $ns -o name 2>/dev/null | while read resource; do
                kubectl patch $resource -n $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
            
            # Deletar todos os recursos manualmente
            kubectl delete all --all -n $ns --force --grace-period=0 --wait=false 2>/dev/null || true
            
            # Remover finalizers do namespace
            kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            
            # Forçar deleção do namespace
            kubectl delete namespace $ns --force --grace-period=0 --wait=false 2>/dev/null || true
        fi
    done
    for ns in cattle-fleet-system cattle-provisioning-capi-system; do
        kubectl delete all --all -n $ns --force --grace-period=0
        kubectl patch namespace $ns -p '{"metadata":{"finalizers":[]}}' --type=merge
        kubectl delete namespace $ns --force --grace-period=0
    done
    log "Limpeza de namespaces teimosos concluída"
}

remove_finalizers() {
    local resource_type=$1
    local pattern=$2
    local namespace=${3:-}
    
    log "Removendo finalizers de $resource_type com pattern: $pattern"
    
    local resources
    if [ -z "$namespace" ]; then
        resources=$(kubectl get $resource_type -o name 2>/dev/null | grep -E "$pattern" || true)
    else
        resources=$(kubectl get $resource_type -n $namespace -o name 2>/dev/null | grep -E "$pattern" || true)
    fi
    
    if [ -z "$resources" ]; then
        log "Nenhum $resource_type encontrado para pattern: $pattern"
        return
    fi
    
    echo "$resources" | while read -r resource; do
        log "Removendo finalizers de $resource"
        kubectl patch $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
}

force_delete_pods() {
    local namespace=$1
    local pattern=${2:-".*"}
    
    log "Forçando deleção de pods em $namespace com pattern: $pattern"
    
    # Primeiro remover finalizers
    kubectl get pods -n $namespace -o name 2>/dev/null | grep -E "$pattern" | while read -r pod; do
        log "Removendo finalizers de $pod"
        kubectl patch $pod -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    
    # Depois forçar deleção
    kubectl delete pods -n $namespace --field-selector status.phase=Running --force --grace-period=0 2>/dev/null || true
    kubectl delete pods -n $namespace --field-selector status.phase=Terminating --force --grace-period=0 2>/dev/null || true
    kubectl delete pods -n $namespace --field-selector status.phase=Pending --force --grace-period=0 2>/dev/null || true
    
    # Deletar todos os pods restantes
    kubectl delete pods -n $namespace --all --force --grace-period=0 --wait=false 2>/dev/null || true
}

force_delete_namespace() {
    local namespace=$1
    
    if ! kubectl get namespace $namespace >/dev/null 2>&1; then
        return
    fi
    
    log "Forçando deleção do namespace: $namespace"
    
    # Primeiro, forçar deleção de todos os pods (especialmente os teimosos)
    force_delete_pods "$namespace"
    
    # Remover finalizers de todos os recursos no namespace
    remove_finalizers "services" ".*" "$namespace"
    remove_finalizers "deployments" ".*" "$namespace"
    remove_finalizers "daemonsets" ".*" "$namespace"
    remove_finalizers "jobs" ".*" "$namespace"
    remove_finalizers "configmaps" ".*" "$namespace"
    remove_finalizers "secrets" ".*" "$namespace"
    remove_finalizers "ingress" ".*" "$namespace"
    
    # Remover finalizers do namespace
    kubectl patch namespace $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    
    # Tentar deleção normal
    kubectl delete namespace $namespace --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Método alternativo com JSON
    local temp_file="/tmp/${namespace}.json"
    kubectl get namespace $namespace -o json 2>/dev/null | \
        jq 'del(.spec.finalizers)' > "$temp_file" 2>/dev/null && \
    kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f "$temp_file" 2>/dev/null || true
    
    rm -f "$temp_file" 2>/dev/null
    
    # Verificar se ainda existe e tentar método nuclear
    if kubectl get namespace $namespace >/dev/null 2>&1; then
        warn "Namespace $namespace ainda existe, usando método nuclear..."
        kubectl get namespace $namespace -o json | \
            jq 'del(.metadata.finalizers)' | \
            jq 'del(.spec.finalizers)' > "$temp_file" 2>/dev/null && \
        kubectl replace --raw "/api/v1/namespaces/${namespace}/finalize" -f "$temp_file" 2>/dev/null || true
        rm -f "$temp_file" 2>/dev/null
    fi
}

delete_crds() {
    local pattern=$1
    
    log "Deletando CRDs com pattern: $pattern"
    
    local crds=$(kubectl get crd -o name 2>/dev/null | grep -E "$pattern" || true)
    
    if [ -z "$crds" ]; then
        log "Nenhum CRD encontrado para pattern: $pattern"
        return
    fi
    
    # Primeiro remover finalizers
    echo "$crds" | while read -r crd; do
        log "Removendo finalizers de CRD: $crd"
        kubectl patch $crd -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    
    # Depois deletar
    echo "$crds" | while read -r crd; do
        log "Deletando CRD: $crd"
        kubectl delete $crd --force --grace-period=0 --wait=false 2>/dev/null || true
    done
}

delete_svcs() {
    local namespace=$1
    local pattern=${2:-".*"}
    
    log "Deletando serviços em $namespace com pattern: $pattern"
    
    if ! kubectl get namespace $namespace >/dev/null 2>&1; then
        log "Namespace $namespace não existe, pulando deleção de serviços"
        return
    fi
    
    # Obter todos os serviços do namespace
    local services=$(kubectl get svc -n $namespace -o name 2>/dev/null | grep -E "$pattern" || true)
    
    if [ -z "$services" ]; then
        log "Nenhum serviço encontrado em $namespace para pattern: $pattern"
        return
    fi
    
    # Primeiro remover finalizers dos serviços
    echo "$services" | while read -r svc; do
        log "Removendo finalizers de $svc"
        kubectl patch $svc -n $namespace -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
    
    # Depois deletar todos os serviços
    echo "$services" | while read -r svc; do
        log "Deletando $svc"
        kubectl delete $svc -n $namespace --force --grace-period=0 --wait=false 2>/dev/null || true
    done
    
    # Deletar todos os serviços restantes (fallback)
    kubectl delete svc -n $namespace --all --force --grace-period=0 --wait=false 2>/dev/null || true
}

clean_metallb_pods() {
    log "Limpando pods travados do MetalLB..."
    
    # Verificar se há pods do MetalLB em terminating
    local terminating_pods=$(kubectl get pods --all-namespaces --field-selector status.phase=Terminating -o name | grep metallb || true)
    
    if [ -n "$terminating_pods" ]; then
        log "Removendo finalizers de pods travados do MetalLB"
        echo "$terminating_pods" | while read -r pod; do
            kubectl patch $pod -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
        
        # Deletar os pods
        echo "$terminating_pods" | while read -r pod; do
            kubectl delete $pod --force --grace-period=0 --wait=false 2>/dev/null || true
        done
    fi
    
    # Deletar todos os pods do MetalLB restantes
    kubectl delete pods -n metallb-system --all --force --grace-period=0 --wait=false 2>/dev/null || true
}

clean_metallb_resources() {
    log "Limpando recursos do MetalLB..."
    
    # Deletar configurações
    kubectl delete ipaddresspool,bfdprofile,bgpadvertisement,bgppeer,community,l2advertisement \
        -n metallb-system --all --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar serviços
    kubectl delete svc -n metallb-system --all --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar deployments e daemonsets
    kubectl delete deployment,daemonset -n metallb-system --all --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar webhooks
    kubectl delete validatingwebhookconfiguration metallb-webhook-configuration --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar service accounts, roles, etc.
    kubectl delete serviceaccount,role,rolebinding,clusterrole,clusterrolebinding -n metallb-system \
        -l app.kubernetes.io/component=speaker --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete serviceaccount,role,rolebinding,clusterrole,clusterrolebinding -n metallb-system \
        -l app.kubernetes.io/component=controller --force --grace-period=0 --wait=false 2>/dev/null || true
}

clean_metallb() {
    log "Limpando MetalLB..."
    
    # Limpar pods travados primeiro
    clean_metallb_pods

    # Limpar serviços do MetalLB
    delete_svcs "metallb-system"

    # Limpar recursos do MetalLB
    clean_metallb_resources
    
    # Deletar CRDs
    delete_crds "metallb.io"
    
    # Deletar namespace
    force_delete_namespace "metallb-system"
    
    log "Limpeza do MetalLB concluída"
}

clean_rancher() {
    log "Limpando Rancher..."
    
    # Desinstalar Helm
    helm uninstall rancher -n cattle-system --no-hooks 2>/dev/null || true
    
    # Limpar dependências primeiro
    clean_rancher_dependencies

    # Limpar namespaces teimosos primeiro
    clean_stubborn_namespaces

    # Forçar deleção de pods teimosos primeiro
    force_delete_pods "cattle-system" "rancher"
    force_delete_pods "cattle-system" "webhook"
    
    # Deletar todos os serviços do Rancher
    delete_svcs "cattle-system" "rancher"
    delete_svcs "cattle-system" "webhook"
    delete_svcs "cattle-system" "imperative"

    # Deletar serviços
    kubectl delete svc rancher -n cattle-system --force --grace-period=0 --wait=false 2>/dev/null || true
    kubectl delete job rancher-post-delete -n cattle-system --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar todos os deployments teimosos
    kubectl delete deployment -n cattle-system --all --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Deletar namespaces do Rancher
    for ns in "${NAMESPACES[@]}"; do
        if [[ $ns == cattle-* || $ns == fleet-* || $ns == local || $ns == p-* ]]; then
            force_delete_namespace "$ns"
        fi
    done
    
    # Deletar CRDs do Rancher
    delete_crds "cattle.io|rancher|fleet|provisioning"
    
    log "Limpeza do Rancher concluída"
}

clean_certmanager() {
    log "Limpando Cert Manager..."
    
    # Desinstalar Helm
    helm uninstall cert-manager -n cert-manager 2>/dev/null || true

    # Limpar serviços do Cert Manager
    delete_svcs "cert-manager"

    # Deletar namespace
    force_delete_namespace "cert-manager"
    
    # Deletar CRDs
    delete_crds "cert-manager"
    
    log "Limpeza do Cert Manager concluída"
}

clean_all() {
    log "Limpando todos os componentes..."
    clean_rancher
    clean_certmanager
    clean_metallb
    log "Limpeza completa concluída"
}

# Main execution
main() {
    local mode="all"
    
    case "${1:-}" in
        --rancher)
            mode="rancher"
            ;;
        --metallb)
            mode="metallb"
            ;;
        --certmanager)
            mode="certmanager"
            ;;
        --all|"")
            mode="all"
            ;;
        --check)
            check_status
            exit 0
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
    
    log "Iniciando limpeza no modo: $mode"
    
    case "$mode" in
        rancher)
            clean_rancher
            delete_specific_svcs
            ;;
        metallb)
            clean_metallb
            delete_specific_svcs
            ;;
        certmanager)
            clean_certmanager
            delete_specific_svcs
            ;;
        all)
            clean_all
            delete_specific_svcs
            ;;
    esac
    
    log "Verificando estado final..."
    kubectl get namespaces
    kubectl get crd | grep -E "$(IFS=\|; echo "${CRD_PATTERNS[*]}")" || true
    
    log "Operação concluída!"
}

# Executar main com parâmetros
main "$@"