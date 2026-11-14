import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "submit", "status"]

  async submit(event) {
    event.preventDefault()
    this.submitTarget.disabled = true
    this.statusTarget.textContent = "Preparing the score preview..."

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        body: new FormData(this.formTarget),
        headers: { Accept: "application/json" }
      })
      const result = await response.json()

      if (!response.ok) throw new Error(result.error || "Could not preview this score.")

      window.location.assign(result.preview_url)
    } catch (error) {
      this.statusTarget.textContent = error.message || "Could not render this score."
    } finally {
      this.submitTarget.disabled = false
    }
  }
}
