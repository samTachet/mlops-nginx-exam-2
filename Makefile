#run-project remplacé par start-project, qui fait un vrai docker compose up --build cette fois, pas juste un echo
# et remplacé test-api par test pointant sur le script complet plutôt qu'un seul curl

.PHONY: start-project stop-project test

start-project:
	docker compose up --build -d
	@echo "Nginx Gateway : https://localhost"
	@echo "Grafana UI    : http://localhost:3000"
	@echo "Prometheus UI : http://localhost:9090"

stop-project:
	docker compose down

test:
	bash tests/run_tests.sh