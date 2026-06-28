import { Controller } from "@hotwired/stimulus"

const DEFAULT_FILTER = "all"
const RUNTIME_FILTERS = new Set([DEFAULT_FILTER, "codex", "opencode", "pi"])
const STATUS_FILTERS = new Set([DEFAULT_FILTER, "running", "completed"])
const RUNNING_STATUSES = new Set(["starting", "running"])

export default class extends Controller {
  static targets = ["button", "empty", "group", "item", "project"]
  static values = { storageKey: String, statusStorageKey: String }

  connect() {
    this.currentRuntimeFilter = this.normalizeRuntime(this.read(this.runtimeStorageKey) || DEFAULT_FILTER)
    this.currentStatusFilter = this.normalizeStatus(this.read(this.statusStorageKey) || DEFAULT_FILTER)
    this.apply()
  }

  selectRuntime(event) {
    this.currentRuntimeFilter = this.normalizeRuntime(event.currentTarget.dataset.sessionFilterRuntimeValue)
    this.write(this.runtimeStorageKey, this.currentRuntimeFilter)
    this.apply()
  }

  selectStatus(event) {
    this.currentStatusFilter = this.normalizeStatus(event.currentTarget.dataset.sessionFilterStatusValue)
    this.write(this.statusStorageKey, this.currentStatusFilter)
    this.apply()
  }

  apply() {
    this.itemTargets.forEach((item) => {
      item.hidden = !this.itemMatches(item)
    })

    this.groupTargets.forEach((group) => {
      group.hidden = !this.hasVisibleItem(group)
    })

    this.projectTargets.forEach((project) => {
      project.hidden = !this.hasVisibleItem(project)
    })

    this.updateButtons()
    this.updateEmptyState()
  }

  itemMatches(item) {
    return this.runtimeMatches(item) && this.statusMatches(item)
  }

  runtimeMatches(item) {
    return this.currentRuntimeFilter === DEFAULT_FILTER || item.dataset.runtimeName === this.currentRuntimeFilter
  }

  statusMatches(item) {
    if (this.currentStatusFilter === DEFAULT_FILTER) return true
    if (this.currentStatusFilter === "running") return RUNNING_STATUSES.has(item.dataset.runStatus)

    return item.dataset.runStatus === this.currentStatusFilter
  }

  hasVisibleItem(container) {
    return this.itemTargets.some((item) => container.contains(item) && !item.hidden)
  }

  updateButtons() {
    this.buttonTargets.forEach((button) => {
      const active = this.buttonActive(button)
      button.classList.toggle("ap-quiet-link-active", active)
      button.setAttribute("aria-pressed", active ? "true" : "false")
    })
  }

  buttonActive(button) {
    if (button.dataset.sessionFilterRuntimeValue !== undefined) {
      return this.normalizeRuntime(button.dataset.sessionFilterRuntimeValue) === this.currentRuntimeFilter
    }

    return this.normalizeStatus(button.dataset.sessionFilterStatusValue) === this.currentStatusFilter
  }

  updateEmptyState() {
    if (!this.hasEmptyTarget) return

    this.emptyTarget.hidden = this.projectTargets.some((project) => !project.hidden)
  }

  normalizeRuntime(value) {
    const filter = String(value || DEFAULT_FILTER)
    return RUNTIME_FILTERS.has(filter) ? filter : DEFAULT_FILTER
  }

  normalizeStatus(value) {
    const filter = String(value || DEFAULT_FILTER)
    return STATUS_FILTERS.has(filter) ? filter : DEFAULT_FILTER
  }

  read(key) {
    try {
      return localStorage.getItem(key)
    } catch {
      return null
    }
  }

  write(key, value) {
    try {
      localStorage.setItem(key, value)
    } catch {
      // Storage can be unavailable in private browsing; filtering still works.
    }
  }

  get runtimeStorageKey() {
    return this.hasStorageKeyValue ? this.storageKeyValue : "agent-control-room:session-runtime-filter"
  }

  get statusStorageKey() {
    return this.hasStatusStorageKeyValue ? this.statusStorageKeyValue : "agent-control-room:session-status-filter"
  }
}
