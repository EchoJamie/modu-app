import { readFile, mkdir, copyFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(directory);
const output = path.join(directory, 'dist');
const plist = await readFile(path.join(root, 'Config/Info.plist'), 'utf8');
const minimumOS = plist.match(/<key>LSMinimumSystemVersion<\/key>\s*<string>([\d.]+)<\/string>/)?.[1];
if (!minimumOS) throw new Error('无法从 Config/Info.plist 读取 macOS 最低版本');
await mkdir(path.join(output, 'assets'), { recursive: true });
const html = (await readFile(path.join(directory, 'index.html'), 'utf8')).replaceAll('{{MIN_MACOS}}', minimumOS);
if (/\{\{[A-Z_]+\}\}/.test(html)) throw new Error('站点仍有未替换的构建变量');
await writeFile(path.join(output, 'index.html'), html);
for (const name of ['styles.css', 'sections.css', 'site.js']) await copyFile(path.join(directory, name), path.join(output, name));
await mkdir(path.join(output, 'assets/product'), { recursive: true });
for (const name of ['newsprint-light', 'newsprint-dark', 'github-light', 'github-dark']) {
  const filename = `modu-${name}.png`;
  await copyFile(path.join(directory, 'assets/product', filename), path.join(output, 'assets/product', filename));
}
await copyFile(path.join(root, 'Config/AppIcon-1024.png'), path.join(output, 'assets/icon.png'));
console.log('站点构建完成：website/dist');
