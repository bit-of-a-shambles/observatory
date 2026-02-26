import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "pane", "insight"]

  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab
    
    // Update tabs
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === tabName) {
        tab.classList.add("text-[#c8a84e]", "border-b-2", "border-[#c8a84e]")
        tab.classList.remove("text-white/30", "border-transparent")
      } else {
        tab.classList.remove("text-[#c8a84e]", "border-b-2", "border-[#c8a84e]")
        tab.classList.add("text-white/30", "border-transparent")
      }
    })

    // Update panes
    this.paneTargets.forEach(pane => {
      if (pane.dataset.pane === tabName) {
        pane.classList.remove("hidden")
      } else {
        pane.classList.add("hidden")
      }
    })
  }

  toggleInsight(event) {
    const content = event.currentTarget.querySelector("[data-details]")
    if (content) {
      content.classList.toggle("hidden")
    }
  }
}
