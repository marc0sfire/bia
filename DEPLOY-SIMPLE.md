# Deploy Simples BIA - Versionamento com Commit Hash

Scripts complementares ao `deploy-ecs.sh` existente, focados em simplicidade e versionamento baseado em commit hash.

## Scripts Disponíveis

### 1. `validate-deploy.sh` - Validação Pré-Deploy
Verifica se tudo está OK antes do deploy.

```bash
./validate-deploy.sh
```

**Verificações realizadas:**
- ✅ Repositório Git válido
- ✅ Ferramentas necessárias (AWS CLI, Docker, jq)
- ✅ Credenciais AWS
- ✅ Docker daemon rodando
- ✅ Repositório ECR existe
- ✅ Cluster ECS ativo
- ✅ Serviço ECS funcionando
- ✅ Task definition válida
- ✅ Dockerfile presente
- ✅ Conectividade com ECR

### 2. `deploy-simple.sh` - Deploy Simplificado
Deploy com versionamento automático baseado no commit hash atual.

```bash
./deploy-simple.sh
```

**O que faz:**
1. Obtém o commit hash atual (7 caracteres)
2. Faz build da imagem Docker com tag do commit
3. Faz push para ECR
4. Cria nova task definition com a imagem versionada
5. Atualiza o serviço ECS
6. Aguarda estabilização

### 3. `version-manager.sh` - Gerenciador de Versões
Gerencia versões e permite rollbacks.

```bash
# Listar versões disponíveis
./version-manager.sh list

# Ver versão atual do serviço
./version-manager.sh current

# Fazer rollback para versão específica
./version-manager.sh rollback abc1234

# Comparar duas versões
./version-manager.sh compare abc1234 def5678

# Limpar versões antigas (mantém 10 mais recentes)
./version-manager.sh cleanup
```

## Fluxo de Trabalho Recomendado

### Deploy Normal
```bash
# 1. Validar ambiente
./validate-deploy.sh

# 2. Se tudo OK, fazer deploy
./deploy-simple.sh

# 3. Verificar versão deployada
./version-manager.sh current
```

### Rollback
```bash
# 1. Listar versões disponíveis
./version-manager.sh list

# 2. Fazer rollback para versão desejada
./version-manager.sh rollback abc1234

# 3. Confirmar rollback
./version-manager.sh current
```

## Configurações

Todos os scripts usam as mesmas configurações padrão:

```bash
REGION="us-east-1"
ECR_REPO="bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
TASK_FAMILY="task-def-bia"
```

## Versionamento

- **Tag da imagem:** Commit hash de 7 caracteres (ex: `abc1234`)
- **Tag latest:** Sempre aponta para a versão mais recente
- **Task definitions:** Uma nova revisão para cada deploy
- **Rollback:** Cria nova task definition apontando para versão anterior

## Diferenças do deploy-ecs.sh Existente

| Recurso | deploy-ecs.sh | deploy-simple.sh |
|---------|---------------|------------------|
| Complexidade | Completo, muitas opções | Simples, configuração fixa |
| Parâmetros | Muitos parâmetros CLI | Sem parâmetros |
| Rollback | Integrado | Script separado |
| Validação | Básica | Script separado |
| Uso | Produção/CI/CD | Desenvolvimento/testes |

## Pré-requisitos

- Git (para obter commit hash)
- AWS CLI configurado
- Docker instalado e rodando
- jq (para manipular JSON)
- Permissões AWS para ECS, ECR e STS

## Troubleshooting

### Erro: "Repositório Git não encontrado"
```bash
git init
git add .
git commit -m "Initial commit"
```

### Erro: "Docker daemon não está rodando"
```bash
sudo systemctl start docker
```

### Erro: "Credenciais AWS inválidas"
```bash
aws configure
# ou
aws sts get-caller-identity
```

### Erro: "jq não encontrado"
```bash
# Amazon Linux/CentOS
sudo yum install jq

# Ubuntu/Debian
sudo apt-get install jq
```
