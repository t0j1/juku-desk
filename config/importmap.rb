# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/lib", under: "lib"
# KaTeX 0.19.0（CDN は使わず vendor に同梱。数式の描画はブラウザだけで行う）
pin "katex", to: "katex.js"
pin "katex-auto-render", to: "katex-auto-render.js"
