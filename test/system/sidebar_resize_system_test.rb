require "application_system_test_case"

class SidebarResizeSystemTest < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 900] do |options|
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--force-prefers-reduced-motion")
  end

  setup do
    page.driver.browser.manage.window.resize_to(1280, 900)
  end

  test "developer can drag workspace vertical dividers wider" do
    run = demo_run

    visit run_path(run)

    assert_selector ".ap-workspace[data-sidebar-resize-ready='true']"
    assert_selector ".ap-sidebar-resizer[role='separator']", count: 2

    initial_sidebar_width = panel_width("session")

    drag_resizer("Resize sessions sidebar", 96)

    resized_sidebar_width = panel_width("session")
    stored_sidebar_width = page.evaluate_script("Number(localStorage.getItem('agent-control-room:session-sidebar-width'))")

    assert_operator resized_sidebar_width, :>, initial_sidebar_width + 70
    assert_equal resized_sidebar_width.round, stored_sidebar_width

    initial_lineage_width = panel_width("lineage")

    drag_resizer("Resize runtime lineage", 80)

    resized_lineage_width = panel_width("lineage")
    stored_lineage_width = page.evaluate_script("Number(localStorage.getItem('agent-control-room:runtime-lineage-width'))")

    assert_operator resized_lineage_width, :>, initial_lineage_width + 50
    assert_equal resized_lineage_width.round, stored_lineage_width
  end

  private

  def drag_resizer(label, delta)
    page.execute_script(<<~JS)
      const handle = [...document.querySelectorAll(".ap-sidebar-resizer")].find((element) => {
        return element.getAttribute("aria-label") === #{label.to_json}
      })
      if (!handle) throw new Error(`Missing resize handle: #{label}`)

      const rect = handle.getBoundingClientRect()
      const startX = rect.left + rect.width / 2
      const endX = startX + #{delta}

      handle.dispatchEvent(new PointerEvent("pointerdown", {
        bubbles: true,
        button: 0,
        clientX: startX,
        pointerId: 1
      }))

      window.dispatchEvent(new PointerEvent("pointermove", {
        bubbles: true,
        clientX: endX,
        pointerId: 1
      }))

      window.dispatchEvent(new PointerEvent("pointerup", {
        bubbles: true,
        clientX: endX,
        pointerId: 1
      }))
    JS
  end

  def panel_width(panel_name)
    page.evaluate_script("document.querySelector('[data-sidebar-resize-panel-name=\"#{panel_name}\"]').getBoundingClientRect().width")
  end
end
