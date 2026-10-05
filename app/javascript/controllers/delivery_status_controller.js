import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.timer = setTimeout(() => {
      this.element.src = window.location.href
    }, 2000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
