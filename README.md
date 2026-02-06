# 🚀 Atelier API-Driven Infrastructure

> **Architecture API-first avec LocalStack sur GitHub Codespaces**

[![LocalStack](https://img.shields.io/badge/LocalStack-Ready-blue)](https://localstack.cloud/)
[![GitHub Codespaces](https://img.shields.io/badge/GitHub-Codespaces-green)](https://github.com/features/codespaces)
[![Docker](https://img.shields.io/badge/Docker-Required-2496ED)](https://www.docker.com/)

## 📋 Table des matières

- [Vue d'ensemble](#-vue-densemble)
- [Architecture](#-architecture)
- [Pré-requis](#-pré-requis)
- [Installation rapide](#-installation-rapide)
- [Utilisation](#-utilisation)
- [BONUS : Pilotage Docker](#-bonus--pilotage-docker)
- [Architecture technique](#-architecture-technique)
- [Troubleshooting](#-troubleshooting)
- [Nettoyage](#-nettoyage)

---

## 🎯 Vue d'ensemble

Ce projet implémente une **infrastructure API-driven** complète où chaque action infrastructure est déclenchée par une simple requête HTTP :

```
HTTP Request → API Gateway → Lambda → Infrastructure (EC2 / Docker)
```

### Fonctionnalités principales

✅ **API Gateway** exposée publiquement  
✅ **Lambda** pour orchestrer l'infrastructure  
✅ **EC2** start/stop via LocalStack  
✅ **BONUS** : Gestion de conteneurs Docker via API  
✅ **Zero localhost** : tout fonctionne via URLs publiques Codespaces  
✅ **Architecture cloud-native** simulée localement  

### Contrainte respectée : No Localhost

> 🔒 **Principe fondamental** : Aucune dépendance à `localhost` côté utilisateur.  
> 
> - Les appels externes utilisent l'URL publique Codespaces (`AWS_ENDPOINT_PUBLIC`)
> - Les communications internes (Lambda ↔ LocalStack/Docker) utilisent l'IP gateway Docker (`172.17.0.1`)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Codespaces                         │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                          │ │
│  │  👤 User (External)                                     │ │
│  │    │                                                     │ │
│  │    │ HTTPS (Public URL)                                 │ │
│  │    ▼                                                     │ │
│  │  ┌─────────────────────────────────┐                   │ │
│  │  │   LocalStack (Port 4566)        │                   │ │
│  │  │  ┌──────────────────────────┐   │                   │ │
│  │  │  │   API Gateway            │   │                   │ │
│  │  │  │   /infra?action=start    │   │                   │ │
│  │  │  └──────────┬───────────────┘   │                   │ │
│  │  │             │                    │                   │ │
│  │  │             ▼                    │                   │ │
│  │  │  ┌──────────────────────────┐   │                   │ │
│  │  │  │   Lambda Function        │───┼───┐               │ │
│  │  │  │   (infrastructure.py)    │   │   │               │ │
│  │  │  └──────────────────────────┘   │   │               │ │
│  │  │             │                    │   │               │ │
│  │  │             │                    │   │               │ │
│  │  │  ┌──────────▼──────────┐        │   │               │ │
│  │  │  │   EC2 Instance      │        │   │               │ │
│  │  │  │   (i-xxxxx)         │        │   │               │ │
│  │  │  └─────────────────────┘        │   │               │ │
│  │  └─────────────────────────────────┘   │               │ │
│  │                                         │               │ │
│  │                          172.17.0.1:2375│               │ │
│  │                                         ▼               │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │   Docker Proxy (BONUS)                           │  │ │
│  │  │   ┌──────────────────────────┐                   │  │ │
│  │  │   │  Container: mycontainer  │                   │  │ │
│  │  │   │  (nginx:alpine)          │                   │  │ │
│  │  │   └──────────────────────────┘                   │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │                                                          │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Flux de données

1. **Requête externe** : `curl https://<codespace>-4566.app.github.dev/restapis/{API_ID}/dev/_user_request_/infra?action=start`
2. **API Gateway** reçoit la requête et l'achemine vers Lambda
3. **Lambda** analyse les paramètres (`action`, `target`, `name`)
4. **Lambda** communique avec :
   - LocalStack EC2 API via `http://172.17.0.1:4566`
   - Docker API via `http://172.17.0.1:2375` (bonus)
5. **Réponse** : statut de l'opération en JSON

---

## 🔧 Pré-requis

### Environnement requis

- **GitHub Codespaces** (ou environnement Linux avec Docker)
- **Docker** installé et en cours d'exécution
- **Make** pour l'automatisation
- **curl** pour les tests
- **jq** (optionnel, pour formater JSON)

### Vérification rapide

```bash
# Vérifier Docker
docker --version

# Vérifier Make
make --version

# Vérifier curl
curl --version
```

---

## ⚡ Installation rapide

### 1️⃣ Configurer l'endpoint public

Dans GitHub Codespaces, allez dans l'onglet **PORTS** et :

1. Rendez le port **4566** **public** (visibilité : Public)
2. Copiez l'URL générée (format : `https://<ton-codespace>-4566.app.github.dev`)

Ensuite, exportez les variables d'environnement :

```bash
export AWS_ENDPOINT_PUBLIC="https://<TON-CODESPACE>-4566.app.github.dev"
export AWS_REGION="us-east-1"
```

> 💡 **Astuce** : Ajoutez ces exports dans votre `~/.bashrc` pour les rendre permanents.

### 2️⃣ Démarrer LocalStack

```bash
make up
```

Cette commande :
- Lance LocalStack dans un conteneur Docker
- Expose le port 4566
- Configure les services AWS simulés

**Vérification** :
```bash
# Vérifier que LocalStack est en cours d'exécution
docker ps | grep localstack
```

### 3️⃣ Déployer l'infrastructure

```bash
make deploy
```

Cette commande :
1. Crée une instance EC2 dans LocalStack
2. Package et déploie la fonction Lambda
3. Configure API Gateway avec une route `/infra`
4. Affiche l'`API_ID` généré
5. Sauvegarde les IDs dans `.instance_id` et `.api_id`

**Sortie attendue** :
```
🚀 Création de l'instance EC2...
✅ Instance créée : i-abc123def456
📦 Packaging de la Lambda...
✅ Lambda déployée : infrastructure-handler
🌐 Configuration de l'API Gateway...
✅ API Gateway créée : r7zy8k1b2m
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✨ Déploiement terminé !
API_ID: r7zy8k1b2m
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 4️⃣ Tester l'infrastructure

```bash
make test
```

Cette commande effectue les tests suivants :
1. ✅ Start de l'instance EC2
2. ✅ Stop de l'instance EC2
3. ✅ Vérification du statut

**Sortie attendue** :
```
🧪 Test 1: Démarrage de l'instance EC2...
✅ Réponse : {"status":"started","instance_id":"i-abc123def456"}

🧪 Test 2: Arrêt de l'instance EC2...
✅ Réponse : {"status":"stopped","instance_id":"i-abc123def456"}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Tous les tests sont passés !
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 📡 Utilisation

### Récupérer l'API ID

```bash
API_ID=$(cat .api_id)
echo "Votre API ID : $API_ID"
```

### Démarrer une instance EC2

```bash
curl "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?action=start"
```

**Réponse** :
```json
{
  "status": "started",
  "instance_id": "i-abc123def456",
  "state": "running"
}
```

### Arrêter une instance EC2

```bash
curl "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?action=stop"
```

**Réponse** :
```json
{
  "status": "stopped",
  "instance_id": "i-abc123def456",
  "state": "stopped"
}
```

### Obtenir le statut de l'instance

```bash
curl "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?action=status"
```

**Réponse** :
```json
{
  "instance_id": "i-abc123def456",
  "state": "running",
  "type": "t2.micro"
}
```

### Utilisation avec jq (formatage JSON)

```bash
# Installation de jq (si nécessaire)
sudo apt-get install -y jq

# Requête avec formatage
curl -s "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?action=start" | jq .
```

---

## 🎁 BONUS : Pilotage Docker

Ce projet inclut un **bonus** permettant de contrôler des conteneurs Docker via la même API.

### 1️⃣ Déployer le proxy Docker

```bash
make bonus
```

Cette commande :
1. Lance un proxy Docker API sur le port 2375
2. Crée un conteneur de test `mycontainer` (nginx:alpine)
3. Configure les permissions nécessaires

**Vérification** :
```bash
# Vérifier les conteneurs
docker ps -a | grep mycontainer
```

### 2️⃣ Arrêter un conteneur via API

```bash
curl "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?target=docker&action=stop&name=mycontainer"
```

**Réponse** :
```json
{
  "status": "stopped",
  "target": "docker",
  "container": "mycontainer"
}
```

### 3️⃣ Démarrer un conteneur via API

```bash
curl "$AWS_ENDPOINT_PUBLIC/restapis/$API_ID/dev/_user_request_/infra?target=docker&action=start&name=mycontainer"
```

**Réponse** :
```json
{
  "status": "started",
  "target": "docker",
  "container": "mycontainer"
}
```

### 4️⃣ Tester le workflow complet

```bash
make test-bonus
```

Cette commande effectue :
1. ✅ Stop du conteneur
2. ✅ Vérification du statut (exited)
3. ✅ Start du conteneur
4. ✅ Vérification du statut (running)

---

## 🔍 Architecture technique

### Pourquoi `172.17.0.1` ?

Dans un environnement Docker, les conteneurs ont besoin d'accéder à des services tournant sur l'hôte. Voici pourquoi nous utilisons `172.17.0.1` :

#### Le problème

Lorsque la Lambda s'exécute dans LocalStack (qui est lui-même dans un conteneur Docker), elle ne peut pas :
- ❌ Utiliser `localhost` (référence à elle-même)
- ❌ Résoudre `localstack` ou `docker-proxy` (noms de conteneurs)
- ❌ Accéder directement aux ports de l'hôte

#### La solution : Gateway Docker

```
┌──────────────────────────────────────────────────────┐
│  Hôte (Codespaces)                                   │
│                                                       │
│  ┌─────────────────────┐                            │
│  │ Docker Gateway      │ ← IP: 172.17.0.1           │
│  │ (bridge network)    │                            │
│  └──────────┬──────────┘                            │
│             │                                        │
│    ┌────────┴────────┐                              │
│    │                 │                               │
│    ▼                 ▼                               │
│  Port 4566       Port 2375                          │
│  (LocalStack)    (Docker Proxy)                     │
│    │                 │                               │
│    ▼                 ▼                               │
│  ┌─────────┐    ┌──────────┐                        │
│  │LocalStack│   │docker-   │                        │
│  │Container │   │proxy     │                        │
│  └─────────┘    └──────────┘                        │
└──────────────────────────────────────────────────────┘
```

**Avantages** :
- ✅ Connexion fiable depuis n'importe quel conteneur
- ✅ Pas de configuration DNS complexe
- ✅ Standard Docker (fonctionne partout)
- ✅ Performance optimale (réseau bridge local)

### Configuration réseau

```python
# Dans la Lambda
LOCALSTACK_ENDPOINT = "http://172.17.0.1:4566"  # LocalStack
DOCKER_API_ENDPOINT = "http://172.17.0.1:2375"   # Docker Proxy

# Ces IPs fonctionnent depuis :
# - Les conteneurs Lambda dans LocalStack
# - Les scripts de déploiement
# - Les tests automatisés
```

### Sécurité

> ⚠️ **Note importante** : Ce setup est destiné au développement local uniquement.  
> En production, utilisez :
> - TLS/SSL pour Docker API
> - Authentification robuste
> - Pare-feu et règles de sécurité
> - VPC et sous-réseaux privés

---

## 🐛 Troubleshooting

### Problème : LocalStack ne démarre pas

**Symptôme** :
```
Error: Cannot connect to LocalStack
```

**Solution** :
```bash
# Vérifier que Docker fonctionne
docker ps

# Redémarrer LocalStack
make down
make up

# Vérifier les logs
docker logs localstack-main
```

### Problème : API Gateway ne répond pas

**Symptôme** :
```
curl: (7) Failed to connect
```

**Solution** :
```bash
# Vérifier que le port 4566 est public
# Dans Codespaces : Onglet PORTS → Port 4566 → Visibilité: Public

# Vérifier la variable d'environnement
echo $AWS_ENDPOINT_PUBLIC

# Redéployer si nécessaire
make deploy
```

### Problème : Lambda ne trouve pas l'instance EC2

**Symptôme** :
```json
{"error": "Instance not found"}
```

**Solution** :
```bash
# Vérifier que l'instance existe
aws --endpoint-url=$AWS_ENDPOINT_PUBLIC ec2 describe-instances

# Recréer l'instance
make clean
make deploy
```

### Problème : Docker proxy ne fonctionne pas

**Symptôme** :
```
Error: Cannot connect to Docker daemon
```

**Solution** :
```bash
# Vérifier que le proxy est en cours d'exécution
docker ps | grep docker-proxy

# Redémarrer le proxy
docker stop docker-proxy
make bonus

# Vérifier les permissions
docker inspect docker-proxy | grep -A5 Mounts
```

### Problème : Variables d'environnement non définies

**Symptôme** :
```
Error: AWS_ENDPOINT_PUBLIC not set
```

**Solution** :
```bash
# Définir les variables
export AWS_ENDPOINT_PUBLIC="https://<TON-CODESPACE>-4566.app.github.dev"
export AWS_REGION="us-east-1"

# Les rendre permanentes
echo 'export AWS_ENDPOINT_PUBLIC="https://<TON-CODESPACE>-4566.app.github.dev"' >> ~/.bashrc
echo 'export AWS_REGION="us-east-1"' >> ~/.bashrc
source ~/.bashrc
```

### Logs et debugging

```bash
# Logs LocalStack
docker logs -f localstack-main

# Logs Docker Proxy
docker logs -f docker-proxy

# Logs de déploiement
cat deploy.log

# Tester manuellement la Lambda
aws --endpoint-url=$AWS_ENDPOINT_PUBLIC lambda invoke \
  --function-name infrastructure-handler \
  --payload '{"action":"status"}' \
  response.json
```

---

## 🧹 Nettoyage

### Nettoyage complet

```bash
make clean
```

Cette commande :
1. Supprime l'API Gateway
2. Supprime la fonction Lambda
3. Termine l'instance EC2
4. Arrête et supprime les conteneurs Docker
5. Supprime les fichiers temporaires (`.instance_id`, `.api_id`)

### Nettoyage sélectif

```bash
# Arrêter uniquement LocalStack
make down

# Supprimer uniquement le bonus Docker
docker stop docker-proxy mycontainer
docker rm docker-proxy mycontainer

# Supprimer uniquement les fichiers temporaires
rm -f .instance_id .api_id deploy.log
```

### Reset complet

```bash
# Supprimer tous les conteneurs et images
make clean
docker system prune -a -f

# Redémarrer depuis zéro
make up
make deploy
```

---

## 📊 Commandes Makefile

| Commande | Description |
|----------|-------------|
| `make up` | Démarre LocalStack |
| `make down` | Arrête LocalStack |
| `make deploy` | Déploie l'infrastructure complète |
| `make test` | Teste les endpoints EC2 |
| `make bonus` | Déploie le proxy Docker + conteneur test |
| `make test-bonus` | Teste les endpoints Docker |
| `make clean` | Nettoyage complet |
| `make logs` | Affiche les logs LocalStack |
| `make status` | Affiche le statut de tous les composants |

---

## 📚 Ressources additionnelles

### Documentation

- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [Docker API Documentation](https://docs.docker.com/engine/api/)

### Architecture AWS simulée

Ce projet simule les services AWS suivants :
- **EC2** : Gestion d'instances virtuelles
- **Lambda** : Fonctions serverless
- **API Gateway** : Routage HTTP → Lambda
- **IAM** : Rôles et permissions

### Critères d'évaluation

✅ **Repository exécutable** : `make up && make deploy && make test`  
✅ **Fonctionnement conforme** : Endpoints HTTP EC2 + bonus Docker  
✅ **Automatisation** : Makefile complet avec toutes les commandes  
✅ **Qualité README** : Documentation complète et reproductible  
✅ **No localhost** : Architecture utilisant gateway Docker  
✅ **Process de travail** : Commits cohérents et structurés  

---

## 🤝 Contribution

Ce projet est un atelier pédagogique. Les contributions sont les bienvenues !

### Suggestions d'améliorations

- [ ] Ajouter des tests unitaires pour la Lambda
- [ ] Implémenter un monitoring avec CloudWatch (simulé)
- [ ] Ajouter support Terraform/Pulumi pour IaC
- [ ] Créer un dashboard web pour visualiser l'infrastructure
- [ ] Ajouter authentification API (API Keys)
- [ ] Support multi-région
- [ ] Intégration CI/CD avec GitHub Actions


---

## 👨‍💻 Auteur

Créé dans le cadre d'un atelier sur les architectures API-driven avec LocalStack.
@KarimBENRHIMA
---

<div align="center">


</div>
