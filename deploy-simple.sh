#!/bin/bash

# Deploy Simples BIA - Versionamento com Commit Hash
# Complementa o deploy-ecs.sh existente com foco em simplicidade

set -e

# Configurações
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="tesk-def-bia"

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Obter commit hash
get_commit_hash() {
    git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown"
}

# Verificar pré-requisitos
check_prereqs() {
    log "Verificando pré-requisitos..."
    
    # Git
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "Não é um repositório Git"
        exit 1
    fi
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI não encontrado"
        exit 1
    fi
    
    # Docker
    if ! command -v docker &> /dev/null; then
        error "Docker não encontrado"
        exit 1
    fi
    
    # jq
    if ! command -v jq &> /dev/null; then
        error "jq não encontrado"
        exit 1
    fi
    
    success "Pré-requisitos OK"
}

# Mostrar informações do deploy
show_deploy_info() {
    local commit_hash=$1
    local account_id=$2
    local image_uri="$account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$commit_hash"
    
    echo
    echo "=== INFORMAÇÕES DO DEPLOY ==="
    echo "Commit Hash: $commit_hash"
    echo "Região: $REGION"
    echo "ECR Repo: $ECR_REPO"
    echo "Cluster: $CLUSTER"
    echo "Service: $SERVICE"
    echo "Task Family: $TASK_FAMILY"
    echo "Image URI: $image_uri"
    echo "=========================="
    echo
}

# Build e push da imagem
build_and_push() {
    local commit_hash=$1
    local account_id=$2
    local ecr_uri="$account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"
    
    log "Login no ECR..."
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ecr_uri
    
    log "Build da imagem (tag: $commit_hash)..."
    docker build -t $ecr_uri:$commit_hash -t $ecr_uri:latest .
    
    log "Push para ECR..."
    docker push $ecr_uri:$commit_hash
    docker push $ecr_uri:latest
    
    success "Imagem enviada para ECR"
}

# Criar task definition
create_task_def() {
    local commit_hash=$1
    local account_id=$2
    local image_uri="$account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$commit_hash"
    
    log "Obtendo task definition atual..."
    local current_task=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition')
    
    log "Criando nova task definition..."
    local new_task=$(echo "$current_task" | jq --arg image "$image_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    local temp_file=$(mktemp)
    echo "$new_task" > "$temp_file"
    
    local revision=$(aws ecs register-task-definition --region $REGION --cli-input-json file://"$temp_file" --query 'taskDefinition.revision' --output text)
    rm -f "$temp_file"
    
    success "Task definition criada: $TASK_FAMILY:$revision"
    echo $revision
}

# Atualizar serviço
update_service() {
    local revision=$1
    
    log "Atualizando serviço ECS..."
    aws ecs update-service \
        --region $REGION \
        --cluster $CLUSTER \
        --service $SERVICE \
        --task-definition $TASK_FAMILY:$revision > /dev/null
    
    success "Serviço atualizado para $TASK_FAMILY:$revision"
    
    log "Aguardando estabilização..."
    aws ecs wait services-stable --region $REGION --cluster $CLUSTER --services $SERVICE
    
    success "Deploy concluído!"
}

# Função principal
main() {
    echo "=== DEPLOY SIMPLES BIA ==="
    
    check_prereqs
    
    local commit_hash=$(get_commit_hash)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    
    show_deploy_info $commit_hash $account_id
    
    # Confirmação
    read -p "Continuar com o deploy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Deploy cancelado"
        exit 0
    fi
    
    build_and_push $commit_hash $account_id
    local revision=$(create_task_def $commit_hash $account_id)
    update_service $revision
    
    echo
    success "Deploy finalizado com sucesso!"
    echo "Versão: $commit_hash"
    echo "Task Definition: $TASK_FAMILY:$revision"
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
