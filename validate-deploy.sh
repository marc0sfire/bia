#!/bin/bash

# Validador de Deploy BIA - Verificações pré-deploy

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[CHECK]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

ERRORS=0
WARNINGS=0

check_error() {
    if [ $? -ne 0 ]; then
        error "$1"
        ((ERRORS++))
        return 1
    else
        success "$1"
        return 0
    fi
}

check_warning() {
    if [ $? -ne 0 ]; then
        warn "$1"
        ((WARNINGS++))
        return 1
    else
        success "$1"
        return 0
    fi
}

echo "=== VALIDAÇÃO PRÉ-DEPLOY BIA ==="
echo

# 1. Verificar Git
log "Verificando repositório Git..."
git rev-parse --git-dir > /dev/null 2>&1
check_error "Repositório Git válido"

if [ $? -eq 0 ]; then
    commit_hash=$(git rev-parse --short=7 HEAD)
    echo "   Commit atual: $commit_hash"
    
    # Verificar se há mudanças não commitadas
    if ! git diff-index --quiet HEAD --; then
        warn "Há mudanças não commitadas"
        ((WARNINGS++))
    else
        success "Working directory limpo"
    fi
fi

echo

# 2. Verificar ferramentas necessárias
log "Verificando ferramentas..."

command -v aws > /dev/null 2>&1
check_error "AWS CLI instalado"

command -v docker > /dev/null 2>&1
check_error "Docker instalado"

command -v jq > /dev/null 2>&1
check_error "jq instalado"

echo

# 3. Verificar credenciais AWS
log "Verificando credenciais AWS..."
aws sts get-caller-identity > /dev/null 2>&1
if check_error "Credenciais AWS válidas"; then
    account_id=$(aws sts get-caller-identity --query Account --output text)
    echo "   Account ID: $account_id"
fi

echo

# 4. Verificar Docker
log "Verificando Docker..."
docker info > /dev/null 2>&1
check_error "Docker daemon rodando"

echo

# 5. Verificar ECR
log "Verificando repositório ECR..."
aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION > /dev/null 2>&1
check_error "Repositório ECR '$ECR_REPO' existe"

echo

# 6. Verificar cluster ECS
log "Verificando cluster ECS..."
cluster_status=$(aws ecs describe-clusters --clusters $CLUSTER --region $REGION --query 'clusters[0].status' --output text 2>/dev/null)
if [ "$cluster_status" = "ACTIVE" ]; then
    success "Cluster '$CLUSTER' ativo"
    
    # Verificar capacidade do cluster
    running_tasks=$(aws ecs describe-clusters --clusters $CLUSTER --region $REGION --query 'clusters[0].runningTasksCount' --output text)
    active_services=$(aws ecs describe-clusters --clusters $CLUSTER --region $REGION --query 'clusters[0].activeServicesCount' --output text)
    echo "   Tasks rodando: $running_tasks"
    echo "   Serviços ativos: $active_services"
else
    error "Cluster '$CLUSTER' não encontrado ou inativo"
    ((ERRORS++))
fi

echo

# 7. Verificar serviço ECS
log "Verificando serviço ECS..."
service_status=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].status' --output text 2>/dev/null)
if [ "$service_status" = "ACTIVE" ]; then
    success "Serviço '$SERVICE' ativo"
    
    desired_count=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].desiredCount' --output text)
    running_count=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION --query 'services[0].runningCount' --output text)
    echo "   Desired: $desired_count, Running: $running_count"
    
    if [ "$desired_count" != "$running_count" ]; then
        warn "Serviço não está estável (desired ≠ running)"
        ((WARNINGS++))
    fi
else
    error "Serviço '$SERVICE' não encontrado ou inativo"
    ((ERRORS++))
fi

echo

# 8. Verificar task definition
log "Verificando task definition..."
aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION > /dev/null 2>&1
if check_error "Task definition '$TASK_FAMILY' existe"; then
    current_revision=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition.revision' --output text)
    echo "   Revisão atual: $current_revision"
fi

echo

# 9. Verificar Dockerfile
log "Verificando Dockerfile..."
if [ -f "Dockerfile" ]; then
    success "Dockerfile encontrado"
    
    # Verificar se o Dockerfile parece válido
    if grep -q "FROM" Dockerfile && grep -q "EXPOSE" Dockerfile; then
        success "Dockerfile parece válido"
    else
        warn "Dockerfile pode estar incompleto"
        ((WARNINGS++))
    fi
else
    error "Dockerfile não encontrado"
    ((ERRORS++))
fi

echo

# 10. Verificar conectividade com ECR
log "Testando conectividade com ECR..."
account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ ! -z "$account_id" ]; then
    ecr_endpoint="$account_id.dkr.ecr.$REGION.amazonaws.com"
    if aws ecr get-login-password --region $REGION > /dev/null 2>&1; then
        success "Conectividade com ECR OK"
    else
        error "Falha na conectividade com ECR"
        ((ERRORS++))
    fi
fi

echo

# Resumo final
echo "=== RESUMO DA VALIDAÇÃO ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    success "Tudo OK! Pronto para deploy"
    echo
    echo "Para fazer o deploy:"
    echo "  ./deploy-simple.sh"
    echo
    echo "Para gerenciar versões:"
    echo "  ./version-manager.sh list"
    echo "  ./version-manager.sh current"
elif [ $ERRORS -eq 0 ]; then
    warn "$WARNINGS warning(s) encontrado(s), mas deploy pode prosseguir"
    echo
    echo "Para fazer o deploy:"
    echo "  ./deploy-simple.sh"
else
    error "$ERRORS erro(s) encontrado(s) - corrija antes do deploy"
    if [ $WARNINGS -gt 0 ]; then
        warn "$WARNINGS warning(s) também encontrado(s)"
    fi
    echo
    exit 1
fi

echo "=========================="
