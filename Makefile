# juku-desk（Rails 本体・ルート）と apps/schedule-web（静的サイト + Supabase）の共通入口。
# 使い方: make setup / make dev / make test
SCHEDULE_PORT ?= 8000

.PHONY: setup dev test setup-rails setup-web dev-rails dev-web test-rails test-web

setup: setup-rails setup-web

dev:
	@trap 'kill 0' INT TERM EXIT; \
	$(MAKE) dev-web & \
	$(MAKE) dev-rails & \
	wait

test: test-rails test-web

setup-rails:
	bundle install
	bin/rails db:prepare

# schedule-web は package.json を持たず、依存パッケージ無しで動く（Node 23.6 以降が必要）。
setup-web:
	@node -e 'process.exit(+process.versions.node.split(".")[0] >= 24 ? 0 : 1)' \
	  || { echo "Node 24 以上が必要です（mise install）"; exit 1; }

dev-rails:
	bin/dev

dev-web:
	python3 -m http.server $(SCHEDULE_PORT) -d apps/schedule-web/public

test-rails:
	bin/rails test

test-web:
	cd apps/schedule-web && node --test scripts/backup.test.mjs scripts/pickup-api.test.mjs scripts/pickup-common.test.mjs scripts/nav.test.mjs scripts/headers.test.mjs
