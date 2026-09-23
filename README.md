# MLOps Nginx Exam — Déploiement avancé avec Nginx

## Vue d'ensemble

Architecture MLOps conteneurisée où Nginx sert de passerelle unique (API Gateway)
devant deux versions d'une API FastAPI de prédiction de sentiment/émotion sur texte
(modèle `TfidfVectorizer` + `LogisticRegression`, scikit-learn).

## Architecture
                 Client
                   |
              HTTPS (443)
                   |
             +-----------+
             |   Nginx   |----(interne, port 8080)---> /nginx_status
             +-----------+                                   |
              /          \                                   v
      upstream api-v1   upstream api-v2              nginx_exporter (9113)
      (3 répliques)      (1 instance, "debug")               |
                                                              v
                                                         Prometheus (9090)
                                                              |
                                                              v
                                                          Grafana (3000)


Le routage vers `api-v1` ou `api-v2` dépend du header `X-Experiment-Group: debug`
(absent ou différent → `api-v1` ; valeur `debug` → `api-v2`), via une directive
`map` nginx — pas de logique métier dans les APIs elles-mêmes.

## Services (`docker-compose.yml`)

| Service         | Rôle                                              | Exposition          |
|-----------------|----------------------------------------------------|---------------------|
| `nginx`         | Reverse proxy, TLS, auth, rate limiting, A/B routing | 80, 443 (host)      |
| `api-v1-1/2/3`  | API standard, 3 répliques (load balancing)         | interne uniquement  |
| `api-v2`        | API "debug" (renvoie les probabilités par classe)  | interne uniquement  |
| `nginx_exporter`| Expose les métriques Nginx pour Prometheus         | interne (9113)      |
| `prometheus`    | Collecte des métriques                             | 9090 (host)         |
| `grafana`       | Visualisation                                      | 3000 (host)         |

## Lancement

```bash
make start-project   # build + démarrage de tous les services
make test             # exécute tests/run_tests.sh (6 tests fonctionnels)
make stop-project     # arrêt et nettoyage des conteneurs
```

Prérequis : générer les certificats auto-signés avant le premier démarrage
(non versionnés — à régénérer par chaque environnement) :

```bash
mkdir -p deployments/nginx/certs
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout deployments/nginx/certs/nginx.key \
  -out deployments/nginx/certs/nginx.crt \
  -subj "/CN=localhost"
```

## Utilisation

```bash
curl -k -X POST "https://localhost/predict" \
  -H "Content-Type: application/json" \
  -d '{"sentence": "Oh yeah, that was soooo cool!"}' \
  --user admin:admin
```

Ajouter `-H "X-Experiment-Group: debug"` pour router vers `api-v2` et obtenir
la distribution de probabilités par classe en plus de la prédiction.

## Sécurité

- **HTTPS** : TLS auto-signé, tout trafic HTTP (port 80) redirigé en 301 vers HTTPS.
- **Authentification** : basic auth (`.htpasswd`) sur `/predict` uniquement.
- **Rate limiting** : 10 req/s par IP avec burst de 5 (`limit_req_zone` / `limit_req`),
  requêtes rejetées en HTTP 503 (comportement par défaut nginx pour ce module).
- **Load balancing** : 3 services distincts (`api-v1-1/2/3`) plutôt qu'un service
  scalé via `deploy.replicas`, pour éviter le cache DNS de nginx sur la résolution
  d'un nom unique et garantir une répartition round-robin réelle entre requêtes.

## Limites connues

- `depends_on` dans `docker-compose.yml` garantit l'ordre de démarrage des
  conteneurs, pas leur disponibilité applicative — pas de `healthcheck` configuré.
- Le script de reproduction du modèle (`gen_model.py`) et le dataset d'entraînement
  ne sont pas inclus dans ce dépôt ; `model/model.joblib` est fourni tel quel
  (entraîné avec scikit-learn 1.6.1, version pinnée dans `requirements.txt`).

                                                         
