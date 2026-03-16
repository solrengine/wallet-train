import { Controller } from "@hotwired/stimulus"
import { visit } from "@hotwired/turbo"

// Periodically refreshes the page via Turbo visit (preserves scroll, morphs DOM).
// Only runs when the tab is visible.
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30 }
  }

  connect() {
    this.timer = setInterval(() => {
      if (document.visibilityState === "visible") {
        visit(window.location.href, { action: "replace" })
      }
    }, this.intervalValue * 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
