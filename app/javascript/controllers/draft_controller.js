import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hint"]

  changed() {
    this.hintTarget.textContent = "Unsaved changes. Save this draft before reviewing; saving removes any previous approval."
  }
}
