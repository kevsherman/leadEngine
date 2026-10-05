import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["email", "password"]

  fill() {
    this.emailTarget.value = "kevin@example.test"
    this.passwordTarget.value = "local-demo-password"
    this.passwordTarget.focus()
  }
}
