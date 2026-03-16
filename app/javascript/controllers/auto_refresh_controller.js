import { Controller } from "@hotwired/stimulus"
import { session } from "@hotwired/turbo"

// Periodically refreshes the page using Turbo's morph-based page refresh.
// Only morphs DOM elements that changed — no flash, no scroll reset.
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 30 }
  }

  connect() {
    this.timer = setInterval(() => {
      if (document.visibilityState === "visible") {
        session.refresh(document.baseURI)
      }
    }, this.intervalValue * 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
