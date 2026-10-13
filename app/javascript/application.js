// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Progress bars declare their width as data-width="42" (percent), and swatches their color as
// data-swatch="#8e2b4f". Setting them through the CSSOM keeps us compatible with the strict
// Content-Security-Policy (no inline style attributes), including in content Turbo Streams add later.
function applyDataStyles(root = document) {
  root.querySelectorAll("[data-width]").forEach((el) => {
    const value = Math.max(0, Math.min(100, Number(el.dataset.width) || 0))
    el.style.width = `${value}%`
  })
  root.querySelectorAll("[data-swatch]").forEach((el) => {
    if (/^#[0-9a-f]{3,8}$/i.test(el.dataset.swatch)) el.style.backgroundColor = el.dataset.swatch
  })
}
document.addEventListener("turbo:load", () => applyDataStyles())
document.addEventListener("turbo:render", () => applyDataStyles())
document.addEventListener("turbo:before-stream-render", (event) => {
  const render = event.detail.render
  event.detail.render = async (stream) => {
    await render(stream)
    applyDataStyles()
  }
})
