# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "html5-qrcode", to: "html5-qrcode.js"

pin "jsqr", to: "jsqr-1.4.0.js" # @1.4.0

pin "scanning/camera"
