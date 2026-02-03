#!/bin/bash

# Gerenciador de Versões BIA - Complemento ao deploy-simple.sh

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

# Listar versões no ECR
list_versions() {
    log "Versões disponíveis no ECR:"
    echo
    aws ecr describe-images \
        --repository-name $ECR_REPO \
        --region $REGION \
        --query 'sort_by(imageDetails,&imagePushedAt)[*].[imageTags[0],imagePushedAt]' \
        --output table
}

# Mostrar versão atual do serviço
current_version() {
    log "Obtendo versão atual do serviço..."
    
    local task_def_arn=$(aws ecs describe-services \
        --cluster $CLUSTER \
        --services $SERVICE \
        --region $REGION \
        --query 'services[0].taskDefinition' \
        --output text)
    
    local image_uri=$(aws ecs describe-task-definition \
        --task-definition $task_def_arn \
        --region $REGION \
        --query 'taskDefinition.containerDefinitions[0].image' \
        --output text)
    
    local version=$(echo $image_uri | cut -d':' -f2)
    
    echo
    echo "=== VERSÃO ATUAL ==="
    echo "Task Definition: $task_def_arn"
    echo "Image: $image_uri"
    echo "Versão: $version"
    echo "==================="
    echo
}

# Rollback para versão específica
rollback() {
    local target_version=$1
    
    if [ -z "$target_version" ]; then
        error "Versão não especificada"
        echo "Uso: $0 rollback <versao>"
        exit 1
    fi
    
    log "Verificando se versão $target_version existe..."
    
    if ! aws ecr describe-images \
        --repository-name $ECR_REPO \
        --region $REGION \
        --image-ids imageTag=$target_version > /dev/null 2>&1; then
        error "Versão $target_version não encontrada no ECR"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local image_uri="$account_id.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO:$target_version"
    
    echo
    echo "=== ROLLBACK ==="
    echo "Versão de destino: $target_version"
    echo "Image URI: $image_uri"
    echo "================"
    echo
    
    read -p "Confirmar rollback? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Rollback cancelado"
        exit 0
    fi
    
    log "Criando task definition para rollback..."
    
    local current_task=$(aws ecs describe-task-definition --task-definition $TASK_FAMILY --region $REGION --query 'taskDefinition')
    
    local new_task=$(echo "$current_task" | jq --arg image "$image_uri" '
        .containerDefinitions[0].image = $image |
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
    ')
    
    local temp_file=$(mktemp)
    echo "$new_task" > "$temp_file"
    
    local revision=$(aws ecs register-task-definition --region $REGION --cli-input-json file://"$temp_file" --query 'taskDefinition.revision' --output text)
    rm -f "$temp_file"
    
    log "Atualizando serviço..."
    aws ecs update-service \
        --region $REGION \
        --cluster $CLUSTER \
        --service $SERVICE \
        --task-definition $TASK_FAMILY:$revision > /dev/null
    
    log "Aguardando estabilização..."
    aws ecs wait services-stable --region $REGION --cluster $CLUSTER --services $SERVICE
    
    success "Rollback concluído!"
    echo "Versão atual: $target_version"
    echo "Task Definition: $TASK_FAMILY:$revision"
}

# Comparar duas versões
compare_versions() {
    local version1=$1
    local version2=$2
    
    if [ -z "$version1" ] || [ -z "$version2" ]; then
        error "Duas versões devem ser especificadas"
        echo "Uso: $0 compare <versao1> <versao2>"
        exit 1
    fi
    
    echo "=== COMPARAÇÃO DE VERSÕES ==="
    echo "Versão 1: $version1"
    echo "Versão 2: $version2"
    echo
    
    # Mostrar informações das imagens
    for version in $version1 $version2; do
        echo "--- Versão $version ---"
        aws ecr describe-images \
            --repository-name $ECR_REPO \
            --region $REGION \
            --image-ids imageTag=$version \
            --query 'imageDetails[0].[imagePushedAt,imageSizeInBytes]' \
            --output table 2>/dev/null || echo "Versão não encontrada"
        echo
    done
}

# Limpar versões antigas (manter apenas as 10 mais recentes)
cleanup_old_versions() {
    log "Identificando versões antigas..."
    
    local versions_to_delete=$(aws ecr describe-images \
        --repository-name $ECR_REPO \
        --region $REGION \
        --query 'sort_by(imageDetails,&imagePushedAt)[:-10].[imageDigest]' \
        --output text)
    
    if [ -z "$versions_to_delete" ] || [ "$versions_to_delete" = "None" ]; then
        success "Nenhuma versão antiga para limpar"
        return
    fi
    
    echo "Versões que serão removidas:"
    echo "$versions_to_delete"
    echo
    
    read -p "Confirmar limpeza? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Limpeza cancelada"
        return
    fi
    
    echo "$versions_to_delete" | while read digest; do
        if [ ! -z "$digest" ] && [ "$digest" != "None" ]; then
            log "Removendo imagem: $digest"
            aws ecr batch-delete-image \
                --repository-name $ECR_REPO \
                --region $REGION \
                --image-ids imageDigest=$digest > /dev/null
        fi
    done
    
    success "Limpeza concluída"
}

# Ajuda
show_help() {
    cat << EOF
Gerenciador de Versões BIA

COMANDOS:
    list            Lista versões disponíveis no ECR
    current         Mostra versão atual do serviço
    rollback <ver>  Faz rollback para versão específica
    compare <v1> <v2>  Compara duas versões
    cleanup         Remove versões antigas (mantém 10 mais recentes)
    help            Mostra esta ajuda

EXEMPLOS:
    $0 list
    $0 current
    $0 rollback abc1234
    $0 compare abc1234 def5678
    $0 cleanup

EOF
}

# Main
case "${1:-help}" in
    list)
        list_versions
        ;;
    current)
        current_version
        ;;
    rollback)
        rollback $2
        ;;
    compare)
        compare_versions $2 $3
        ;;
    cleanup)
        cleanup_old_versions
        ;;
    help|*)
        show_help
        ;;
esac
