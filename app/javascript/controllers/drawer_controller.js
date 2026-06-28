import { Controller } from "@hotwired/stimulus"

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])"
].join(",")

export default class extends Controller {
  static targets = ["background", "dialog", "panel"]
  static values = { closeUrl: String }

  connect() {
    this.previouslyFocusedElement = document.activeElement
    this.beforeCache = this.beforeCache.bind(this)
    this.updateModality = this.updateModality.bind(this)
    this.compactDrawerQuery = window.matchMedia("(max-width: 640px)")
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.compactDrawerQuery.addEventListener("change", this.updateModality)
    this.updateModality()

    requestAnimationFrame(() => this.focusInitialElement())
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.compactDrawerQuery?.removeEventListener("change", this.updateModality)
    this.restoreBackground()
    this.dialogTarget.removeAttribute("aria-modal")
    this.restoreFocus()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }

    if (event.key === "Tab" && this.modal) {
      this.trapTab(event)
    }
  }

  beforeCache() {
    this.restoreBackground()
  }

  close() {
    if (this.hasCloseUrlValue && window.Turbo) {
      window.Turbo.visit(this.closeUrlValue)
    } else if (this.hasCloseUrlValue) {
      window.location.href = this.closeUrlValue
    }
  }

  focusInitialElement() {
    const focusable = this.focusableElements[0]
    const target = focusable || this.panelTarget

    target.focus({ preventScroll: true })
  }

  updateModality() {
    this.modal = this.compactDrawerQuery.matches

    if (this.modal) {
      this.backgroundTarget.inert = true
      this.backgroundTarget.setAttribute("aria-hidden", "true")
      this.dialogTarget.setAttribute("aria-modal", "true")
    } else {
      this.restoreBackground()
      this.dialogTarget.removeAttribute("aria-modal")
    }
  }

  trapTab(event) {
    const focusable = this.focusableElements

    if (focusable.length === 0) {
      event.preventDefault()
      this.panelTarget.focus({ preventScroll: true })
      return
    }

    const first = focusable[0]
    const last = focusable[focusable.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  restoreBackground() {
    if (!this.hasBackgroundTarget) return

    this.backgroundTarget.inert = false
    this.backgroundTarget.removeAttribute("inert")
    this.backgroundTarget.removeAttribute("aria-hidden")
  }

  restoreFocus() {
    if (this.previouslyFocusedElement?.isConnected) {
      this.previouslyFocusedElement.focus({ preventScroll: true })
    }
  }

  get focusableElements() {
    return [...this.dialogTarget.querySelectorAll(FOCUSABLE_SELECTOR)].filter((element) => {
      return element.getClientRects().length > 0 || element === document.activeElement
    })
  }
}
