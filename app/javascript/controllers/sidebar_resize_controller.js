import { Controller } from "@hotwired/stimulus"

const DEFAULT_MIN_WIDTH = 176
const DEFAULT_MAX_WIDTH = 420
const DEFAULT_STORAGE_KEY = "agent-control-room:session-sidebar-width"
const DEFAULT_RESERVED_WIDTH = 360
const DEFAULT_KEYBOARD_STEP = 16
const DEFAULT_PANEL_NAME = "session"
const DEFAULT_WIDTH_VARIABLE = "--ap-session-sidebar-width"
const DEFAULT_STORAGE_PREFIX = "agent-control-room"

export default class extends Controller {
  static targets = ["sidebar", "panel", "handle"]
  static values = {
    max: Number,
    min: Number,
    reservedWidth: Number,
    storageKey: String
  }

  connect() {
    this.dragging = false
    this.widths = new Map()
    this.drag = this.drag.bind(this)
    this.stop = this.stop.bind(this)
    this.syncToViewport = this.syncToViewport.bind(this)

    this.restoreWidths()
    this.updateHandles()
    this.element.dataset.sidebarResizeReady = "true"
    window.addEventListener("resize", this.syncToViewport)
  }

  disconnect() {
    window.removeEventListener("resize", this.syncToViewport)
    delete this.element.dataset.sidebarResizeReady
    this.stop()
  }

  start(event) {
    if (event.button !== undefined && event.button !== 0) return
    if (this.isStackedLayout) return

    const config = this.configForHandle(event.currentTarget)
    if (!config.panel) return

    event.preventDefault()

    this.dragging = true
    this.activeConfig = config
    this.startX = event.clientX
    this.startWidth = this.currentWidth(config)
    config.handle.classList.add("ap-sidebar-resizer-active")
    document.documentElement.classList.add("ap-sidebar-resizing")

    window.addEventListener("pointermove", this.drag)
    window.addEventListener("pointerup", this.stop, { once: true })
    window.addEventListener("pointercancel", this.stop, { once: true })

    try {
      config.handle.setPointerCapture(event.pointerId)
    } catch {
      // Pointer capture can fail if the browser has already released the pointer.
    }
  }

  drag(event) {
    if (!this.dragging) return

    event.preventDefault()
    this.setWidth(this.activeConfig, this.startWidth + event.clientX - this.startX)
  }

  stop() {
    if (!this.dragging) return

    this.dragging = false
    this.activeConfig.handle.classList.remove("ap-sidebar-resizer-active")
    document.documentElement.classList.remove("ap-sidebar-resizing")
    window.removeEventListener("pointermove", this.drag)
    window.removeEventListener("pointerup", this.stop)
    window.removeEventListener("pointercancel", this.stop)
    this.persistWidth(this.activeConfig)
    this.activeConfig = null
  }

  handleKeydown(event) {
    if (this.isStackedLayout) return

    const config = this.configForHandle(event.currentTarget)
    if (!config.panel) return

    const step = event.shiftKey ? DEFAULT_KEYBOARD_STEP * 2 : DEFAULT_KEYBOARD_STEP
    let nextWidth

    if (event.key === "ArrowLeft") {
      nextWidth = this.currentWidth(config) - step
    } else if (event.key === "ArrowRight") {
      nextWidth = this.currentWidth(config) + step
    } else if (event.key === "Home") {
      nextWidth = config.minWidth
    } else if (event.key === "End") {
      nextWidth = this.maxAvailableWidth(config)
    } else {
      return
    }

    event.preventDefault()
    this.setWidth(config, nextWidth)
    this.persistWidth(config)
  }

  syncToViewport() {
    if (this.isStackedLayout) return

    this.resizableConfigs().forEach((config) => {
      this.setWidth(config, this.currentWidth(config))
    })
  }

  restoreWidths() {
    this.resizableConfigs().forEach((config) => {
      const storedWidth = this.readStoredWidth(config)
      if (storedWidth) this.setWidth(config, storedWidth)
    })
  }

  setWidth(config, width) {
    const nextWidth = this.clampWidth(config, width)

    this.widths.set(config.panelName, nextWidth)
    this.element.style.setProperty(config.widthVariable, `${nextWidth}px`)
    this.updateHandles()
  }

  persistWidth(config) {
    try {
      localStorage.setItem(config.storageKey, String(Math.round(this.currentWidth(config))))
    } catch {
      // Storage can be unavailable in private browsing; resizing still works.
    }
  }

  readStoredWidth(config) {
    try {
      const value = Number.parseInt(localStorage.getItem(config.storageKey), 10)
      return Number.isFinite(value) ? value : null
    } catch {
      return null
    }
  }

  updateHandles() {
    if (!this.hasHandleTarget) return

    this.handleTargets.forEach((handle) => {
      const config = this.configForHandle(handle)
      if (!config.panel) return

      handle.setAttribute("aria-valuemin", String(config.minWidth))
      handle.setAttribute("aria-valuemax", String(this.maxAvailableWidth(config)))
      handle.setAttribute("aria-valuenow", String(Math.round(this.currentWidth(config))))
    })
  }

  clampWidth(config, width) {
    return Math.round(Math.min(Math.max(width, config.minWidth), this.maxAvailableWidth(config)))
  }

  currentWidth(config) {
    return this.currentPanelWidth(config.panelName, config.panel) || config.minWidth
  }

  currentPanelWidth(panelName, panel) {
    return this.widths.get(panelName) || panel.getBoundingClientRect().width || this.numberSetting(null, panel, "min", DEFAULT_MIN_WIDTH)
  }

  configForHandle(handle) {
    const panelName = this.stringSetting(handle, null, "panelName") || DEFAULT_PANEL_NAME
    const panel = this.panelFor(panelName)
    const minWidth = this.numberSetting(handle, panel, "min", this.hasMinValue ? this.minValue : DEFAULT_MIN_WIDTH)
    const maxWidth = this.numberSetting(handle, panel, "max", this.hasMaxValue ? this.maxValue : DEFAULT_MAX_WIDTH)

    return {
      handle,
      panel,
      panelName,
      minWidth,
      maxWidth,
      reservedWidth: this.numberSetting(handle, panel, "reservedWidth", this.hasReservedWidthValue ? this.reservedWidthValue : DEFAULT_RESERVED_WIDTH),
      reservedPanelNames: this.listSetting(handle, panel, "reservedPanelNames"),
      storageKey: this.stringSetting(handle, panel, "storageKey") || this.defaultStorageKey(panelName),
      widthVariable: this.stringSetting(handle, panel, "widthVariable") || this.defaultWidthVariable(panelName)
    }
  }

  panelFor(panelName) {
    const panel = this.panelTargets.find((target) => target.dataset.sidebarResizePanelName === panelName)
    if (panel) return panel

    if (panelName === DEFAULT_PANEL_NAME && this.hasSidebarTarget) return this.sidebarTarget

    return null
  }

  maxAvailableWidth(config) {
    const reservedWidth = config.reservedWidth + this.reservedPanelWidth(config)
    const availableWidth = this.element.getBoundingClientRect().width - reservedWidth
    const widthLimit = Number.isFinite(availableWidth) && availableWidth > 0 ? availableWidth : config.maxWidth

    return Math.max(config.minWidth, Math.min(config.maxWidth, widthLimit))
  }

  reservedPanelWidth(config) {
    return config.reservedPanelNames.reduce((sum, panelName) => {
      const panel = this.panelFor(panelName)
      if (!panel) return sum

      return sum + this.currentPanelWidth(panelName, panel)
    }, 0)
  }

  resizableConfigs() {
    const seen = new Set()

    return this.handleTargets.map((handle) => this.configForHandle(handle)).filter((config) => {
      if (!config.panel || seen.has(config.panelName)) return false

      seen.add(config.panelName)
      return true
    })
  }

  stringSetting(handle, panel, name) {
    const datasetName = `sidebarResize${this.capitalize(name)}`

    return handle?.dataset?.[datasetName] || panel?.dataset?.[datasetName] || null
  }

  numberSetting(handle, panel, name, fallback) {
    const rawValue = this.stringSetting(handle, panel, name)
    const value = Number.parseInt(rawValue, 10)

    return Number.isFinite(value) ? value : fallback
  }

  listSetting(handle, panel, name) {
    const value = this.stringSetting(handle, panel, name)
    if (!value) return []

    return value.split(/[\s,]+/).filter(Boolean)
  }

  defaultStorageKey(panelName) {
    if (panelName === DEFAULT_PANEL_NAME && this.hasStorageKeyValue) return this.storageKeyValue
    if (panelName === DEFAULT_PANEL_NAME) return DEFAULT_STORAGE_KEY

    return `${DEFAULT_STORAGE_PREFIX}:${panelName}-width`
  }

  defaultWidthVariable(panelName) {
    return panelName === DEFAULT_PANEL_NAME ? DEFAULT_WIDTH_VARIABLE : `--ap-${panelName}-width`
  }

  capitalize(value) {
    return `${value.charAt(0).toUpperCase()}${value.slice(1)}`
  }

  get isStackedLayout() {
    return window.matchMedia("(max-width: 1180px)").matches
  }
}
