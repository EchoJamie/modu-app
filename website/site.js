const options = document.querySelector('.screenshot-options');
const screenshot = document.querySelector('#theme-screenshot');
const original = document.querySelector('#theme-original');
const caption = document.querySelector('#screenshot-caption');

if (options && screenshot && original && caption) {
  const buttons = [...options.querySelectorAll('button[data-shot]')];
  for (const button of buttons) {
    button.addEventListener('click', () => {
      const label = button.textContent.trim();
      const source = `./assets/product/modu-${button.dataset.shot}.png`;
      screenshot.src = source;
      screenshot.alt = `墨读 ${label}真实截图，展示文件树、Markdown 正文和大纲`;
      original.href = source;
      original.setAttribute('aria-label', `查看 ${label}完整截图（新窗口）`);
      caption.textContent = label;
      for (const item of buttons) item.setAttribute('aria-pressed', String(item === button));
    });
  }
  options.hidden = false;
}
