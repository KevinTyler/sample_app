// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Progress bars declare their width as data-width="42" (percent). Setting it through the CSSOM
// keeps us compatible with the strict Content-Security-Policy (no inline style attributes).
function applyWidths() {
  document.querySelectorAll("[data-width]").forEach((el) => {
    const value = Math.max(0, Math.min(100, Number(el.dataset.width) || 0))
    el.style.width = `${value}%`
  })
}
document.addEventListener("turbo:load", applyWidths)
document.addEventListener("turbo:render", applyWidths)
