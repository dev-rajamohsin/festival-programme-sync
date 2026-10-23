import { Controller } from "@hotwired/stimulus"

// debounced so a search doesn't fire a request on every keystroke. The form
// targets the #screenings Turbo Frame, so only the results reload.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
